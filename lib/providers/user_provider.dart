import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';
import '../core/account_preference_writes.dart';
import '../services/account_local_data_cleaner.dart';

class UserProvider extends ChangeNotifier {
  UserProfile _profile = UserProfile();
  int _storageGeneration = 0;
  bool _disposed = false;
  bool _storageLoaded = false;
  bool _statsDirty = false;
  bool _syncTimeDirty = false;
  int _derivedWritesPending = 0;
  Future<void> _storageTail = Future<void>.value();
  VoidCallback? onLocalMutationPersisted;

  UserProfile get profile => _profile;

  String syncSignature() {
    final profile = _profile;
    return [
      profile.username,
      profile.avatarInitials,
      profile.displayName,
      profile.email,
      profile.emailVerified.toString(),
      profile.avatarUrl,
      profile.bio,
      profile.updatedAt?.toIso8601String() ?? '',
    ].join('|');
  }

  /// Rebuild stats from data providers (called by MainShell periodically)
  void recalc({
    int completedTodos = 0,
    int totalFocusMinutes = 0,
    int currentStreak = 0,
    int bestStreak = 0,
  }) {
    if (_disposed) return;
    final unchanged =
        _profile.totalTodosCompleted == completedTodos &&
        _profile.totalFocusMinutes == totalFocusMinutes &&
        _profile.currentStreak == currentStreak &&
        _profile.bestStreak == bestStreak;
    if (unchanged) {
      if (_statsDirty && _derivedWritesPending == 0) _saveDerivedProfile();
      return;
    }

    _profile.totalTodosCompleted = completedTodos;
    _profile.totalFocusMinutes = totalFocusMinutes;
    _profile.currentStreak = currentStreak;
    _profile.bestStreak = bestStreak;
    _statsDirty = true;
    _saveDerivedProfile();
  }

  void _notifyListenersSafely() {
    if (_disposed) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks) {
      final generation = _storageGeneration;
      final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!_disposed &&
            generation == _storageGeneration &&
            AccountLocalDataCleaner.isCurrentAccountDataGeneration(
              accountGeneration,
            ) &&
            hasListeners) {
          notifyListeners();
        }
      });
      return;
    }
    notifyListeners();
  }

  Future<void> loadFromStorage() async {
    try {
      await _enqueueStorage((token, isCurrent) async {
        final prefs = await SharedPreferences.getInstance();
        _ensureCurrent(token, isCurrent);
        _hydrate(prefs);
        _notifyListenersSafely();
      });
    } on AccountPreferenceWriteCanceled {
      // A departed account's hydration must not restore its profile.
    }
  }

  void resetLocalState() {
    _storageGeneration++;
    _storageLoaded = false;
    _statsDirty = false;
    _syncTimeDirty = false;
    _profile = UserProfile();
    _notifyListenersSafely();
  }

  Future<T> _enqueueStorage<T>(
    Future<T> Function(AccountPreferenceWriteToken, bool Function()) operation,
  ) {
    final generation = _storageGeneration;
    final accountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    final preceding = _storageTail;
    final result = Future<T>.sync(
      () => AccountPreferenceWrites.runResult<T>((token) async {
        bool isCurrent() =>
            !_disposed &&
            generation == _storageGeneration &&
            AccountLocalDataCleaner.isCurrentAccountDataGeneration(
              accountGeneration,
            );
        await preceding;
        _ensureCurrent(token, isCurrent);
        return operation(token, isCurrent);
      }, canceledResult: () => throw const AccountPreferenceWriteCanceled()),
    );
    _storageTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  void _ensureCurrent(
    AccountPreferenceWriteToken token,
    bool Function() isCurrent,
  ) {
    token.ensureCurrent();
    if (!isCurrent()) throw const AccountPreferenceWriteCanceled();
  }

  UserProfile _copyProfile(UserProfile profile) =>
      UserProfile.fromJson(profile.toJson());

  void _mergeDerived(UserProfile target, UserProfile current) {
    target.totalTodosCompleted = current.totalTodosCompleted;
    target.totalFocusMinutes = current.totalFocusMinutes;
    target.currentStreak = current.currentStreak;
    target.bestStreak = current.bestStreak;
    target.lastSyncTime = current.lastSyncTime;
  }

  void _hydrate(SharedPreferences prefs) {
    final raw = prefs.getString('user_profile');
    final loaded = raw == null
        ? UserProfile()
        : UserProfile.fromJson(json.decode(raw));
    if (_statsDirty) {
      loaded.totalTodosCompleted = _profile.totalTodosCompleted;
      loaded.totalFocusMinutes = _profile.totalFocusMinutes;
      loaded.currentStreak = _profile.currentStreak;
      loaded.bestStreak = _profile.bestStreak;
    }
    if (_syncTimeDirty) loaded.lastSyncTime = _profile.lastSyncTime;
    _profile = loaded;
    _storageLoaded = true;
  }

  Future<void> _persistSnapshot(
    SharedPreferences prefs,
    UserProfile snapshot,
    AccountPreferenceWriteToken token,
    bool Function() isCurrent,
  ) async {
    _ensureCurrent(token, isCurrent);
    final transaction = AccountPreferenceTransaction(
      prefs,
      () => token.isCurrent && isCurrent(),
    );
    try {
      await transaction.setString(
        'user_profile',
        json.encode(snapshot.toJson()),
      );
      transaction.commit();
      _acknowledgeDerivedSnapshot(snapshot);
    } catch (_) {
      // Cleanup drains this tracked write before removing account keys.
      await transaction.rollback(canceledBeforeCleanup: true);
      rethrow;
    }
  }

  void _acknowledgeDerivedSnapshot(UserProfile snapshot) {
    if (snapshot.totalTodosCompleted == _profile.totalTodosCompleted &&
        snapshot.totalFocusMinutes == _profile.totalFocusMinutes &&
        snapshot.currentStreak == _profile.currentStreak &&
        snapshot.bestStreak == _profile.bestStreak) {
      _statsDirty = false;
    }
    if (snapshot.lastSyncTime == _profile.lastSyncTime) _syncTimeDirty = false;
  }

  void _saveDerivedProfile() {
    if (_disposed) return;
    _derivedWritesPending++;
    var operationEntered = false;
    unawaited(
      _enqueueStorage((token, isCurrent) async {
            operationEntered = true;
            try {
              final prefs = await SharedPreferences.getInstance();
              _ensureCurrent(token, isCurrent);
              if (!_storageLoaded) _hydrate(prefs);
              final snapshot = _copyProfile(_profile);
              await _persistSnapshot(prefs, snapshot, token, isCurrent);
              _ensureCurrent(token, isCurrent);
              _notifyListenersSafely();
            } finally {
              _derivedWritesPending--;
            }
          })
          .catchError((Object error, StackTrace stack) {
            if (error is! AccountPreferenceWriteCanceled) {
              debugPrint(
                '[UserProvider] derived profile save failed: $error\n$stack',
              );
            }
          })
          .whenComplete(() {
            if (!operationEntered) _derivedWritesPending--;
          }),
    );
  }

  Future<void> updateProfile({
    required String username,
    String? avatarInitials,
    String? displayName,
    String? email,
    bool? emailVerified,
    String? avatarUrl,
    String? bio,
  }) async {
    await _writeProfile(
      username: username,
      avatarInitials: avatarInitials,
      displayName: displayName,
      email: email,
      emailVerified: emailVerified,
      avatarUrl: avatarUrl,
      bio: bio,
      touchUpdatedAt: true,
      markLocalMutation: true,
    );
  }

  Future<void> applyAccountSnapshot({
    required String username,
    String? avatarInitials,
    String? displayName,
    String? email,
    bool? emailVerified,
    String? avatarUrl,
    String? bio,
  }) async {
    await _writeProfile(
      username: username,
      avatarInitials: avatarInitials,
      displayName: displayName,
      email: email,
      emailVerified: emailVerified,
      avatarUrl: avatarUrl,
      bio: bio,
      touchUpdatedAt: false,
      markLocalMutation: false,
    );
  }

  Future<void> _writeProfile({
    required String username,
    String? avatarInitials,
    String? displayName,
    String? email,
    bool? emailVerified,
    String? avatarUrl,
    String? bio,
    required bool touchUpdatedAt,
    required bool markLocalMutation,
  }) => _enqueueStorage((token, isCurrent) async {
    final prefs = await SharedPreferences.getInstance();
    _ensureCurrent(token, isCurrent);
    if (!_storageLoaded) _hydrate(prefs);
    final nextProfile = _copyProfile(_profile);
    final cleanName = username.trim().isEmpty ? '用户' : username.trim();
    final cleanInitials = (avatarInitials ?? '').trim();
    final nextAvatarInitials = cleanInitials.isNotEmpty
        ? _firstCodePoint(cleanInitials)
        : _firstCodePoint(cleanName);
    final nextDisplayName = displayName == null
        ? _profile.displayName
        : displayName.trim();
    final nextEmail = email == null ? _profile.email : email.trim();
    final nextEmailVerified = emailVerified ?? _profile.emailVerified;
    final nextAvatarUrl = avatarUrl == null
        ? _profile.avatarUrl
        : avatarUrl.trim();
    final nextBio = bio == null ? _profile.bio : bio.trim();

    final unchanged =
        _profile.username == cleanName &&
        _profile.avatarInitials == nextAvatarInitials &&
        _profile.displayName == nextDisplayName &&
        _profile.email == nextEmail &&
        _profile.emailVerified == nextEmailVerified &&
        _profile.avatarUrl == nextAvatarUrl &&
        _profile.bio == nextBio;
    if (unchanged) return;

    nextProfile.username = cleanName;
    nextProfile.avatarInitials = nextAvatarInitials;
    if (displayName != null) {
      nextProfile.displayName = nextDisplayName;
    }
    if (email != null) {
      nextProfile.email = nextEmail;
    }
    if (emailVerified != null) {
      nextProfile.emailVerified = nextEmailVerified;
    }
    if (avatarUrl != null) {
      nextProfile.avatarUrl = nextAvatarUrl;
    }
    if (bio != null) {
      nextProfile.bio = nextBio;
    }
    if (touchUpdatedAt || _profile.updatedAt == null) {
      nextProfile.updatedAt = DateTime.now();
    }
    await _persistSnapshot(prefs, nextProfile, token, isCurrent);
    _ensureCurrent(token, isCurrent);
    // Statistics and sync timestamps can change while a profile write waits.
    // Their queued save follows this one and persists the merged state.
    _mergeDerived(nextProfile, _profile);
    _profile = nextProfile;
    if (markLocalMutation) _notifyLocalMutationPersisted();
    _notifyListenersSafely();
  });

  Future<void> clearAccountProfileCache() async {
    if (AccountPreferenceWrites.isBoundaryActive) {
      // The cleaner owns key removal inside its boundary. Registering another
      // write here would reject cleanup or wait on the boundary that owns it.
      final cleared = _copyProfile(_profile);
      cleared.username = '用户';
      cleared.avatarInitials = _firstCodePoint(cleared.username);
      cleared.displayName = '';
      cleared.email = '';
      cleared.emailVerified = false;
      cleared.avatarUrl = '';
      cleared.bio = '';
      cleared.updatedAt = DateTime.now();
      _profile = cleared;
      _notifyListenersSafely();
      return;
    }
    await _writeProfile(
      username: '用户',
      avatarInitials: _firstCodePoint('用户'),
      displayName: '',
      email: '',
      emailVerified: false,
      avatarUrl: '',
      bio: '',
      touchUpdatedAt: true,
      markLocalMutation: false,
    );
  }

  Future<void> setUsername(String name) async {
    await updateProfile(username: name);
  }

  void updateLastSyncTime(DateTime time) {
    if (_disposed) return;
    _profile.lastSyncTime = time;
    _syncTimeDirty = true;
    _saveDerivedProfile();
  }

  String _firstCodePoint(String value) {
    return String.fromCharCode(value.runes.first);
  }

  void _notifyLocalMutationPersisted() {
    try {
      onLocalMutationPersisted?.call();
    } catch (error, stack) {
      debugPrint('[UserProvider] mutation callback failed: $error\n$stack');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _storageGeneration++;
    super.dispose();
  }
}
