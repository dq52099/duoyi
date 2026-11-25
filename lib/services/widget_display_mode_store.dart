import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../core/account_preference_writes.dart';

/// One durable record keeps the chosen mode and its delivery intent together.
class WidgetDisplayModeSelection {
  static const storageKey = 'duoyi_widget_display_selection_v1';
  static const legacyKey = 'duoyi_widget_display_mode';
  static const modes = {'compact', 'standard', 'detailed'};

  final String mode;
  final String? intentId;
  final bool pending;

  const WidgetDisplayModeSelection({
    required this.mode,
    this.intentId,
    this.pending = false,
  });

  static WidgetDisplayModeSelection read(SharedPreferences prefs) {
    final encoded = prefs.getString(storageKey);
    if (encoded == null) {
      final legacy = prefs.getString(legacyKey);
      return WidgetDisplayModeSelection(
        mode: modes.contains(legacy) ? legacy! : 'standard',
      );
    }
    final value = jsonDecode(encoded);
    if (value is! Map<String, dynamic> ||
        value['v'] != 1 ||
        !modes.contains(value['mode']) ||
        value['pending'] is! bool ||
        value['intentId'] is! String ||
        (value['intentId'] as String).isEmpty) {
      throw const FormatException('Invalid widget display selection');
    }
    return WidgetDisplayModeSelection(
      mode: value['mode'] as String,
      intentId: value['intentId'] as String,
      pending: value['pending'] as bool,
    );
  }

  String encode({bool? pending}) => jsonEncode({
    'v': 1,
    'mode': mode,
    'intentId': intentId,
    'pending': pending ?? this.pending,
  });
}

/// All pages share operation order; reads only wait for local transactions.
/// Native awaits must stay outside AccountPreferenceWrites tracked writes.
class WidgetDisplayModeStore {
  WidgetDisplayModeStore._();

  static Future<void>? _operationTail;
  static Future<void>? _preferenceTail;

  static Future<T> runOperation<T>(Future<T> Function() operation) {
    final previous = _operationTail;
    final result = previous == null
        ? Future<T>.sync(operation)
        : previous.then((_) => operation());
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _operationTail = tail;
    tail.then((_) {
      if (identical(_operationTail, tail)) _operationTail = null;
    });
    return result;
  }

  static Future<T> _withPreferences<T>(Future<T> Function() operation) {
    final previous = _preferenceTail;
    final result = previous == null
        ? Future<T>.sync(operation)
        : previous.then((_) => operation());
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _preferenceTail = tail;
    tail.then((_) {
      if (identical(_preferenceTail, tail)) _preferenceTail = null;
    });
    return result;
  }

  static Future<WidgetDisplayModeSelection> read() =>
      _withPreferences(() async {
        await AccountPreferenceWrites.waitForBoundary();
        return WidgetDisplayModeSelection.read(
          await SharedPreferences.getInstance(),
        );
      });

  static Future<WidgetDisplayModeSelection?> save(
    String mode, {
    required bool Function() isCurrent,
  }) => _withPreferences(() {
    return AccountPreferenceWrites.runResult((token) async {
      bool current() => token.isCurrent && isCurrent();
      if (!current()) return null;
      final prefs = await SharedPreferences.getInstance();
      if (!current()) return null;
      final selection = WidgetDisplayModeSelection(
        mode: mode,
        intentId: const Uuid().v4(),
        pending: true,
      );
      if (!WidgetDisplayModeSelection.modes.contains(mode)) {
        throw ArgumentError.value(mode, 'mode');
      }
      final transaction = AccountPreferenceTransaction(prefs, current);
      try {
        // The canonical record is complete even if the process stops before
        // the compatibility mirror. A confirmed failure rolls both back.
        await transaction.setString(
          WidgetDisplayModeSelection.storageKey,
          selection.encode(),
        );
        await transaction.setString(WidgetDisplayModeSelection.legacyKey, mode);
        transaction.commit();
        return selection;
      } on AccountPreferenceWriteCanceled {
        await transaction.rollback(canceledBeforeCleanup: true);
        return null;
      } catch (_) {
        await transaction.rollback();
        rethrow;
      }
    }, canceledResult: () => null);
  });

  static Future<bool> acknowledge(
    WidgetDisplayModeSelection selection, {
    required bool Function() isCurrent,
  }) => _withPreferences(() {
    return AccountPreferenceWrites.runResult((token) async {
      bool current() => token.isCurrent && isCurrent();
      if (!current()) return false;
      final prefs = await SharedPreferences.getInstance();
      if (!current()) return false;
      final saved = WidgetDisplayModeSelection.read(prefs);
      if (saved.intentId != selection.intentId ||
          saved.mode != selection.mode ||
          !saved.pending) {
        return false;
      }
      final transaction = AccountPreferenceTransaction(prefs, current);
      try {
        await transaction.setString(
          WidgetDisplayModeSelection.storageKey,
          saved.encode(pending: false),
        );
        transaction.commit();
        return true;
      } on AccountPreferenceWriteCanceled {
        await transaction.rollback(canceledBeforeCleanup: true);
        return false;
      } catch (_) {
        await transaction.rollback();
        rethrow;
      }
    }, canceledResult: () => false);
  });
}
