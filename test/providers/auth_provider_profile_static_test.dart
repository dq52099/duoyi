import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('AuthProvider supports account profile and password reset APIs', () {
    final source = File('lib/providers/auth_provider.dart').readAsStringSync();

    for (final field in [
      'final String? email;',
      'final String? displayName;',
      'final String? avatar;',
      'final String? bio;',
      'final int coinBalance;',
      'final int lifetimeCoins;',
      "'coin_balance': coinBalance",
      "'lifetime_coins': lifetimeCoins",
      "'display_name': displayName",
      "'avatar': avatar",
      "'bio': bio",
    ]) {
      expect(source, contains(field));
    }

    expect(source, contains("'/api/auth/profile'"));
    expect(source, contains('Future<void> updateProfile'));
    final updateProfileBody = source.substring(
      source.indexOf('Future<void> updateProfile({'),
      source.indexOf('Future<void> changePassword'),
    );
    expect(updateProfileBody, isNot(contains('String? username')));
    expect(updateProfileBody, isNot(contains("'username'")));
    expect(updateProfileBody, isNot(contains('String? avatar')));
    expect(updateProfileBody, isNot(contains("'avatar'")));
    expect(source, contains('Future<void> changePassword'));
    expect(source, contains("'/api/auth/change-password'"));
    expect(source, contains('Future<void> uploadAvatarBytes'));
    expect(source, contains("'/api/auth/avatar'"));
    expect(source, contains("fieldName: 'avatar'"));
    expect(
      source,
      contains(
        'Future<void> Function(AuthState state)? onAccountProfileChanged',
      ),
    );
    expect(source, contains('Future<void> Function()? onAccountLoggedOut'));
    expect(source, contains('await _notifyAccountProfileChanged();'));
    expect(source, contains('await _notifyAccountLoggedOut();'));
    expect(source, contains("'/api/auth/password-reset/request'"));
    expect(
      source,
      contains('Future<Map<String, dynamic>> requestPasswordReset'),
    );
    expect(source, contains("'/api/auth/password-reset/confirm'"));
    expect(source, contains('Future<void> confirmPasswordReset'));
    expect(source, contains('bool get registrationEmailRequired'));
    expect(
      source,
      contains("_serverConfig['registration_email_required'] != false"),
    );
    expect(source, contains('_stateFromAuthResponse'));
  });

  test(
    'Profile screen supports RE0-style profile, avatar and email binding UX',
    () {
      final mine = File('lib/screens/mine_screen.dart').readAsStringSync();
      final source = File('lib/screens/profile_screen.dart').readAsStringSync();

      expect(mine, contains("import 'profile_screen.dart';"));
      expect(
        mine,
        contains('MaterialPageRoute(builder: (_) => const ProfileScreen())'),
      );
      expect(mine, contains("label: '个人资料'"));
      expect(mine, contains("auth.state.isLoggedIn ? '账号' : '本地'"));
      expect(mine, isNot(contains("package:file_selector/file_selector.dart")));
      expect(mine, isNot(contains('class _ProfileEditDialog')));
      expect(mine, isNot(contains('class _LocalProfileEditDialog')));
      expect(mine, isNot(contains('openFile(')));

      for (final field in [
        "package:file_selector/file_selector.dart",
        'class ProfileScreen',
        'class _AccountProfileEditor',
        'class _ProfileMetricChip',
        'class _ProfileSectionHeader',
        "I18n.tr('profile.nickname')",
        "I18n.tr('auth.username')",
        "I18n.tr('profile.username.locked')",
        'readOnly: true',
        "I18n.tr('auth.email')",
        "I18n.tr('auth.email_code')",
        "I18n.tr('profile.email.binding')",
        'class _EmailBindingDialog',
        'builder: (_) => const _EmailBindingDialog()',
        "I18n.tr('profile.coins')",
        "I18n.tr('profile.account_id')",
        'addListener(_refreshPreview)',
        'removeListener(_refreshPreview)',
        'AuthProvider? _authProvider',
        '_authProvider?.removeListener(_handleAuthStateChanged)',
        'controller.addListener(_handleProfileFieldChanged)',
        'controller.removeListener(_handleProfileFieldChanged)',
        'void _handleAuthStateChanged()',
        'void _syncAccountStateIfClean(AuthState state)',
        'void _applyAccountState(AuthState state)',
        'bool _hasLocalProfileEdits = false',
        'if (_hasLocalProfileEdits || _busy || _avatarBusy)',
        'void _setControllerText(TextEditingController controller, String value)',
        'String _accountProfileSnapshot(AuthState state)',
        "I18n.tr('auth.error.username_length')",
        "I18n.tr('auth.error.username_no_space')",
        'openFile(',
        'XTypeGroup(',
        "extensions: ['jpg', 'jpeg', 'png', 'webp', 'gif']",
        'uploadAvatarBytes(',
        "I18n.tr('profile.avatar.saved')",
        "purpose: 'bind'",
        'emailCode: code',
        'final userProvider = context.read<UserProvider>()',
        'await userProvider.updateProfile(',
        'displayName: state.displayName ??',
        'email: state.email ??',
        'emailVerified: state.emailVerified',
        'avatarUrl: state.avatar ??',
        'bio: state.bio ??',
        'class _LocalProfileEditor',
        "I18n.tr('profile.display_name')",
        "I18n.tr('profile.local_nickname')",
        "I18n.tr('profile.email.local_display')",
        "I18n.tr('profile.bio')",
        'Future<void> _pickLocalAvatar()',
        '_copyLocalAvatarFile(file)',
        'await _save(showSnackBar: false)',
        "I18n.tr('profile.avatar.choose')",
        'await context.read<UserProvider>().updateProfile(',
        'final avatarIsLocalFile = _localAvatarPath(avatar) != null',
        'final avatarIsImage = avatarIsUrl || avatarIsLocalFile',
        'final avatarInitials = avatarIsImage',
        "avatarUrl: avatarIsImage ? avatar : ''",
        'bool _isHttpAvatar(String value)',
        'String? _localAvatarPath(String value)',
        'Future<String> _copyLocalAvatarFile(XFile file)',
        "final dir = Directory('\${root.path}/profile_avatars')",
        "I18n.tr('profile.local.updated')",
        "I18n.tr('profile.account_security')",
        "I18n.tr('profile.change_password')",
        'class _ChangePasswordDialog',
        'changePassword(',
        "I18n.tr('profile.current_password')",
        "I18n.tr('auth.new_password')",
        "I18n.tr('profile.confirm_new_password')",
      ]) {
        expect(source, contains(field));
      }

      final accountBody = source.substring(
        source.indexOf('class _AccountProfileEditor'),
        source.indexOf('class _LocalProfileEditor'),
      );
      expect(
        accountBody,
        isNot(contains("I18n.tr('profile.avatar.url_or_text')")),
      );
      expect(
        accountBody,
        isNot(contains("I18n.tr('profile.avatar.url_file_or_text')")),
      );
      expect(
        accountBody,
        isNot(contains('username: username')),
        reason: '账号唯一标识不能通过资料保存路径编辑',
      );
      expect(accountBody, isNot(contains('OutlinedButton.icon(')));
      expect(accountBody, contains('AppListTileCard('));
      expect(accountBody, isNot(contains('ListTile(')));
      expect(accountBody, contains("leading: const Icon(Icons.mail_outline)"));
      expect(
        accountBody,
        contains('trailing: const Icon(Icons.chevron_right)'),
      );
    },
  );

  test('UserProvider persists editable local profile fields', () {
    final source = File('lib/providers/user_provider.dart').readAsStringSync();
    final recalcBody = source.substring(
      source.indexOf('void recalc({'),
      source.indexOf('void _notifyListenersSafely()'),
    );

    for (final field in [
      'Future<void> updateProfile({',
      'required String username',
      'String? avatarInitials',
      'String? displayName',
      'String? email',
      'bool? emailVerified',
      'String? avatarUrl',
      'String? bio',
      'void recalc({',
      '// ignore: discarded_futures',
      '_profile.updatedAt = DateTime.now()',
      "_profile.username = cleanName",
      "_profile.avatarInitials = cleanInitials.isNotEmpty",
      '_profile.displayName = displayName.trim()',
      '_profile.email = email.trim()',
      '_profile.emailVerified = emailVerified',
      '_profile.avatarUrl = avatarUrl.trim()',
      '_profile.bio = bio.trim()',
      'await _save()',
      'Future<void> clearAccountProfileCache() async',
      "_profile.username = '用户'",
      "_profile.email = ''",
      '_profile.emailVerified = false',
      "_profile.avatarUrl = ''",
      "_profile.bio = ''",
      'Future<void> setUsername(String name) async',
      'await updateProfile(username: name)',
    ]) {
      expect(source, contains(field));
    }
    expect(recalcBody, contains('_profile.updatedAt = DateTime.now()'));
  });

  test('Mine screen uses synced local account profile as display fallback', () {
    final source = File('lib/screens/mine_screen.dart').readAsStringSync();

    for (final field in [
      'p.displayName',
      'p.avatarUrl',
      'p.bio',
      'p.email',
      'final avatarValue = auth.state.isLoggedIn',
      '_firstNonEmpty([auth.state.avatar, p.avatarUrl, p.avatarInitials])',
      '_firstNonEmpty([p.avatarUrl, p.avatarInitials])',
      'avatar: avatarValue',
      'Image.file(',
      'String? _localAvatarPath(String value)',
    ]) {
      expect(source, contains(field));
    }
  });

  test('Login screen supports password, email-code login and reset flow', () {
    final source = File('lib/screens/login_screen.dart').readAsStringSync();

    for (final field in [
      "I18n.tr('auth.password_login')",
      "I18n.tr('auth.email_code_login')",
      "I18n.tr('auth.account')",
      "I18n.tr('auth.verified_email')",
      'await auth.login(',
      'await auth.emailLogin(',
      "purpose: _isRegister ? 'bind' : 'login'",
      "I18n.tr('auth.email.optional')",
      "I18n.tr('auth.forgot_password')",
      'class _PasswordResetDialog',
      'requestPasswordReset(',
      'confirmPasswordReset(',
      "I18n.tr('auth.reset_account')",
      "I18n.tr('auth.reset_account.helper')",
      "I18n.tr('auth.email_code')",
      'account: account',
      'code: code',
      'bool _looksLikeEmail(String value)',
      'Timer? _emailCooldownTimer',
      'Timer? _cooldownTimer',
      "I18n.tr('auth.confirm_password')",
    ]) {
      expect(source, contains(field));
    }
    expect(source, isNot(contains("labelText: '邮件 token'")));
    expect(source, isNot(contains("setState(() => _error = '请填写账号已绑定邮箱')")));
    expect(source, isNot(contains('重置邮件已发送，请查收邮件中的 token。')));
  });

  test('Profile and auth email-code UX is responsive and guarded', () {
    final profile = File('lib/screens/profile_screen.dart').readAsStringSync();
    final login = File('lib/screens/login_screen.dart').readAsStringSync();

    for (final field in [
      'class _ProfileAvatarPicker',
      'Semantics(',
      'button: true',
      'onTap: _uploadAvatar',
      'onTap: _pickLocalAvatar',
      'SizedBox(width: 112, height: 56, child: action)',
      'bool get _canSend',
      'return _looksLikeEmail(_emailCtrl.text.trim());',
      'onPressed: _canSend ? _sendCode : null',
      "'\${_cooldownSeconds}s 后'",
      'if (_busy || _avatarBusy) return;',
      'onPressed: _busy || _avatarBusy ? null : _save',
    ]) {
      expect(profile, contains(field), reason: field);
    }

    expect(profile, isNot(contains('class _ProfileInlineActionField')));

    for (final field in [
      'class _LoginActionField',
      'final actionWidth = constraints.maxWidth < 360 ? 108.0 : 132.0',
      'SizedBox(width: actionWidth, height: 56, child: action)',
      '_userCtrl.addListener(_refreshControls)',
      '_emailCtrl.addListener(_refreshControls)',
      'if (_busy || _sendingEmailCode) return;',
      'if (!_canSendEmailCode) return;',
      'bool get _canSendEmailCode',
      'final canSend = _canSendEmailCode',
      'onPressed: canSend ? _sendEmailCode : null',
      "'\${_emailCooldownSeconds}s 后'",
      'Widget _emailSendField({',
      'Widget _emailCodeField({',
      '_emailSendField(',
      '_emailCodeField(',
      'Widget _emailCodeSendField({',
      '_emailCodeSendField(',
      'return email.isNotEmpty && _looksLikeEmail(email);',
      '_sendingEmailCode ||',
      "I18n.tr('auth.error.username_required')",
    ]) {
      expect(login, contains(field), reason: field);
    }

    expect(login, isNot(contains('class _LoginInlineActionField')));
  });

  test('App startup refreshes account profile into local profile cache', () {
    final source = File('lib/main.dart').readAsStringSync();

    for (final field in [
      'authProvider.onAccountProfileChanged = (state) async',
      'await userProvider.updateProfile(',
      'displayName: state.displayName ??',
      'email: state.email ??',
      'emailVerified: state.emailVerified',
      'avatarUrl: state.avatar ??',
      'bio: state.bio ??',
      'authProvider.onAccountLoggedOut = ()',
      'userProvider.clearAccountProfileCache()',
      "'auth profile refresh'",
      'authProvider.refreshMe()',
      'await authProvider.refreshMe();',
    ]) {
      expect(source, contains(field));
    }
  });

  test(
    'App refreshes account profile after cloud sync and foreground resume',
    () {
      final source = File('lib/main.dart').readAsStringSync();

      for (final field in [
        'void _refreshAccountProfileOnResume()',
        '_refreshAccountProfileOnResume();',
        'Provider.of<AuthProvider>(ctx, listen: false)',
        'if (!auth.state.isLoggedIn) return;',
        'await auth.refreshMe();',
        'refresh account profile failed',
        'cloudSyncProvider.onSynced = (changedCollections)',
        "changedCollections.contains('user_profile')",
        'futures.add(userProvider.loadFromStorage())',
        'await authProvider.refreshMe();',
      ]) {
        expect(source, contains(field));
      }
    },
  );
}
