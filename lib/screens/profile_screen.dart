import 'dart:async';
import 'dart:io' show Directory, File;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/user_provider.dart';
import '../services/api_client.dart';
import '../widgets/surface_components.dart';
import 'login_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return auth.state.isLoggedIn
        ? const _AccountProfileEditor()
        : const _LocalProfileEditor();
  }
}

class _ProfileAvatarPreview extends StatelessWidget {
  final String? avatar;
  final String displayName;
  final double radius;

  const _ProfileAvatarPreview({
    required this.avatar,
    required this.displayName,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final value = avatar?.trim() ?? '';
    final uri = Uri.tryParse(value);
    final isUrl =
        uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
    final localPath = _localAvatarPath(value);
    final fallback = value.isNotEmpty ? value : displayName;
    final letter = fallback.isNotEmpty ? fallback.characters.first : '我';

    return CircleAvatar(
      radius: radius,
      backgroundColor: cs.primary,
      child: isUrl
          ? ClipOval(
              child: Image.network(
                value,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _ProfileAvatarLetter(
                  letter: letter,
                  radius: radius,
                  color: cs.onPrimary,
                ),
              ),
            )
          : localPath != null
          ? ClipOval(
              child: Image.file(
                File(localPath),
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _ProfileAvatarLetter(
                  letter: letter,
                  radius: radius,
                  color: cs.onPrimary,
                ),
              ),
            )
          : _ProfileAvatarLetter(
              letter: letter,
              radius: radius,
              color: cs.onPrimary,
            ),
    );
  }
}

class _ProfileAvatarLetter extends StatelessWidget {
  final String letter;
  final double radius;
  final Color color;

  const _ProfileAvatarLetter({
    required this.letter,
    required this.radius,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      letter,
      style: TextStyle(
        fontSize: radius * 0.62,
        color: color,
        fontWeight: FontWeight.w400,
      ),
    );
  }
}

class _ProfileActionField extends StatelessWidget {
  final Widget field;
  final Widget action;

  const _ProfileActionField({required this.field, required this.action});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 360) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              field,
              const SizedBox(height: 8),
              SizedBox(height: 48, child: action),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: field),
            const SizedBox(width: 10),
            SizedBox(height: 56, child: action),
          ],
        );
      },
    );
  }
}

class _AccountProfileEditor extends StatefulWidget {
  const _AccountProfileEditor();

  @override
  State<_AccountProfileEditor> createState() => _AccountProfileEditorState();
}

class _AccountProfileEditorState extends State<_AccountProfileEditor> {
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _emailCodeCtrl;
  late final TextEditingController _displayNameCtrl;
  late final TextEditingController _avatarCtrl;
  late final TextEditingController _bioCtrl;
  AuthProvider? _authProvider;
  String? _lastAccountSnapshot;
  bool _syncingControllers = false;
  bool _hasLocalProfileEdits = false;
  bool _busy = false;
  bool _avatarBusy = false;
  bool _sendingEmailCode = false;
  int _emailCooldownSeconds = 0;
  Timer? _emailCooldownTimer;
  String? _error;
  String? _message;

  @override
  void initState() {
    super.initState();
    final state = context.read<AuthProvider>().state;
    _usernameCtrl = TextEditingController(text: state.username ?? '');
    _emailCtrl = TextEditingController(text: state.email ?? '');
    _emailCodeCtrl = TextEditingController();
    _displayNameCtrl = TextEditingController(text: state.displayName ?? '');
    _avatarCtrl = TextEditingController(text: state.avatar ?? '');
    _bioCtrl = TextEditingController(text: state.bio ?? '');
    _lastAccountSnapshot = _accountProfileSnapshot(state);
    for (final controller in [
      _usernameCtrl,
      _emailCtrl,
      _displayNameCtrl,
      _avatarCtrl,
      _bioCtrl,
    ]) {
      controller.addListener(_handleProfileFieldChanged);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextAuth = context.read<AuthProvider>();
    if (_authProvider == nextAuth) return;
    _authProvider?.removeListener(_handleAuthStateChanged);
    _authProvider = nextAuth..addListener(_handleAuthStateChanged);
    _syncAccountStateIfClean(nextAuth.state);
  }

  @override
  void dispose() {
    _emailCooldownTimer?.cancel();
    _authProvider?.removeListener(_handleAuthStateChanged);
    for (final controller in [
      _usernameCtrl,
      _emailCtrl,
      _displayNameCtrl,
      _avatarCtrl,
      _bioCtrl,
    ]) {
      controller.removeListener(_handleProfileFieldChanged);
    }
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _emailCodeCtrl.dispose();
    _displayNameCtrl.dispose();
    _avatarCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  void _refreshPreview() {
    if (mounted) setState(() {});
  }

  void _handleProfileFieldChanged() {
    if (_syncingControllers) return;
    _hasLocalProfileEdits = true;
    _refreshPreview();
  }

  void _handleAuthStateChanged() {
    final state = _authProvider?.state;
    if (state == null || !mounted) return;
    _syncAccountStateIfClean(state);
  }

  void _syncAccountStateIfClean(AuthState state) {
    final nextSnapshot = _accountProfileSnapshot(state);
    if (nextSnapshot == _lastAccountSnapshot) return;
    if (_hasLocalProfileEdits || _busy || _avatarBusy || _sendingEmailCode) {
      return;
    }
    _applyAccountState(state);
  }

  void _applyAccountState(AuthState state, {bool clearEmailCode = false}) {
    _syncingControllers = true;
    try {
      _setControllerText(_usernameCtrl, state.username ?? '');
      _setControllerText(_emailCtrl, state.email ?? '');
      _setControllerText(_displayNameCtrl, state.displayName ?? '');
      _setControllerText(_avatarCtrl, state.avatar ?? '');
      _setControllerText(_bioCtrl, state.bio ?? '');
      if (clearEmailCode) _emailCodeCtrl.clear();
    } finally {
      _syncingControllers = false;
    }
    _lastAccountSnapshot = _accountProfileSnapshot(state);
    _hasLocalProfileEdits = false;
    _refreshPreview();
  }

  void _setControllerText(TextEditingController controller, String value) {
    if (controller.text == value) return;
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  Future<void> _sendBindEmailCode() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _error = I18n.tr('auth.error.email_required'));
      return;
    }
    if (!_looksLikeEmail(email)) {
      setState(() => _error = I18n.tr('auth.error.email_invalid'));
      return;
    }
    setState(() {
      _sendingEmailCode = true;
      _error = null;
      _message = null;
    });
    try {
      final result = await context.read<AuthProvider>().sendEmailCode(
        email: email,
        purpose: 'bind',
      );
      final devCode = (result['dev_code'] ?? '').toString();
      final message = (result['message'] ?? I18n.tr('auth.email_code.sent'))
          .toString();
      if (!mounted) return;
      _startEmailCooldown();
      setState(() {
        _message = devCode.isEmpty
            ? message
            : '$message ${I18n.tr('auth.email_code.code_prefix')}$devCode';
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _sendingEmailCode = false);
    }
  }

  void _startEmailCooldown() {
    _emailCooldownTimer?.cancel();
    setState(() => _emailCooldownSeconds = 60);
    _emailCooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_emailCooldownSeconds <= 1) {
        timer.cancel();
        setState(() => _emailCooldownSeconds = 0);
      } else {
        setState(() => _emailCooldownSeconds -= 1);
      }
    });
  }

  Widget _bindEmailCodeButton() {
    return OutlinedButton(
      onPressed: _sendingEmailCode || _emailCooldownSeconds > 0
          ? null
          : _sendBindEmailCode,
      child: _sendingEmailCode
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(
              _emailCooldownSeconds > 0
                  ? '${_emailCooldownSeconds}s'
                  : I18n.tr('auth.send'),
            ),
    );
  }

  Future<void> _uploadAvatar() async {
    final auth = context.read<AuthProvider>();
    final userProvider = context.read<UserProvider>();
    setState(() {
      _avatarBusy = true;
      _error = null;
      _message = null;
    });
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Image',
            extensions: ['jpg', 'jpeg', 'png', 'webp', 'gif'],
            mimeTypes: ['image/jpeg', 'image/png', 'image/webp', 'image/gif'],
          ),
        ],
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        if (mounted) {
          setState(() => _error = I18n.tr('profile.avatar.empty'));
        }
        return;
      }
      await auth.uploadAvatarBytes(filename: file.name, bytes: bytes);
      final state = auth.state;
      _lastAccountSnapshot = _accountProfileSnapshot(state);
      _syncingControllers = true;
      try {
        _setControllerText(_avatarCtrl, state.avatar ?? '');
      } finally {
        _syncingControllers = false;
      }
      await userProvider.updateProfile(
        username: _firstNonEmptyProfileText([
          state.displayName,
          state.username,
          _displayNameCtrl.text,
          _usernameCtrl.text,
        ]),
        displayName: state.displayName ?? '',
        email: state.email ?? '',
        emailVerified: state.emailVerified,
        avatarUrl: state.avatar ?? '',
        bio: state.bio ?? '',
      );
      if (!mounted) return;
      setState(() {
        _message = I18n.tr('profile.avatar.uploaded');
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  Future<void> _save() async {
    final username = _usernameCtrl.text.trim();
    if (username.length < 3 || username.length > 64) {
      setState(() => _error = I18n.tr('auth.error.username_length'));
      return;
    }
    if (RegExp(r'\s').hasMatch(username)) {
      setState(() => _error = I18n.tr('auth.error.username_no_space'));
      return;
    }
    final email = _emailCtrl.text.trim();
    if (email.isNotEmpty && !_looksLikeEmail(email)) {
      setState(() => _error = I18n.tr('auth.error.email_invalid'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final auth = context.read<AuthProvider>();
      final userProvider = context.read<UserProvider>();
      await auth.updateProfile(
        username: username,
        email: email,
        emailCode: _emailCodeCtrl.text.trim(),
        displayName: _displayNameCtrl.text.trim(),
        avatar: _avatarCtrl.text.trim(),
        bio: _bioCtrl.text.trim(),
      );
      final state = auth.state;
      _applyAccountState(state, clearEmailCode: true);
      final localName = _firstNonEmptyProfileText([
        state.displayName,
        state.username,
        _displayNameCtrl.text,
        _usernameCtrl.text,
      ]);
      await userProvider.updateProfile(
        username: localName,
        displayName: state.displayName ?? '',
        email: state.email ?? '',
        emailVerified: state.emailVerified,
        avatarUrl: state.avatar ?? '',
        bio: state.bio ?? '',
      );
      if (!mounted) return;
      setState(() => _message = I18n.tr('profile.updated'));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(I18n.tr('profile.updated'))));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AuthProvider>().state;
    final themeProvider = context.watch<ThemeProvider>();
    final avatarFrame = themeProvider.activeAvatarFrame;
    final displayName = _firstNonEmptyProfileText([
      _displayNameCtrl.text,
      _usernameCtrl.text,
      state.displayName,
      state.username,
    ]);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(I18n.tr('profile.title')),
        actions: [
          TextButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(I18n.tr('action.save')),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          AppSurfaceCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 76,
                  height: 76,
                  padding: avatarFrame.id == ThemeProvider.defaultAvatarFrameId
                      ? EdgeInsets.zero
                      : const EdgeInsets.all(3),
                  decoration:
                      avatarFrame.id == ThemeProvider.defaultAvatarFrameId
                      ? null
                      : BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(colors: avatarFrame.colors),
                        ),
                  child: _ProfileAvatarPreview(
                    avatar: _avatarCtrl.text.trim().isEmpty
                        ? state.avatar
                        : _avatarCtrl.text.trim(),
                    displayName: displayName.isEmpty ? '我' : displayName,
                    radius: 36,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName.isEmpty
                            ? I18n.tr('profile.display_name.empty')
                            : displayName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        state.email?.isNotEmpty == true
                            ? '${state.email}${state.emailVerified ? ' · ${I18n.tr('profile.email.verified')}' : ' · ${I18n.tr('profile.email.unverified')}'}'
                            : I18n.tr('profile.email.unbound'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.62),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppSurfaceCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _displayNameCtrl,
                  decoration: InputDecoration(
                    labelText: I18n.tr('profile.nickname'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _usernameCtrl,
                  decoration: InputDecoration(
                    labelText: I18n.tr('auth.username'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: I18n.tr('auth.email'),
                    helperText: state.emailVerified
                        ? I18n.tr('profile.email.verified')
                        : I18n.tr('profile.email.unverified_or_pending'),
                  ),
                ),
                const SizedBox(height: 12),
                _ProfileActionField(
                  field: TextField(
                    controller: _emailCodeCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: I18n.tr('auth.email_code'),
                      helperText: I18n.tr('profile.email_code.helper'),
                    ),
                  ),
                  action: _bindEmailCodeButton(),
                ),
                const SizedBox(height: 12),
                _ProfileActionField(
                  field: TextField(
                    controller: _avatarCtrl,
                    decoration: InputDecoration(
                      labelText: I18n.tr('profile.avatar.url_or_text'),
                    ),
                  ),
                  action: OutlinedButton.icon(
                    onPressed: _avatarBusy ? null : _uploadAvatar,
                    icon: _avatarBusy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_file_outlined),
                    label: Text(I18n.tr('profile.avatar.upload')),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _bioCtrl,
                  minLines: 3,
                  maxLines: 6,
                  decoration: InputDecoration(
                    labelText: I18n.tr('profile.bio'),
                  ),
                ),
              ],
            ),
          ),
          if (_message != null) ...[
            const SizedBox(height: 12),
            AppInfoBanner(
              icon: Icons.check_circle_outline,
              title: I18n.tr('profile.saved'),
              message: _message!,
              color: Colors.green,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            AppInfoBanner(
              icon: Icons.error_outline,
              title: I18n.tr('profile.save_failed'),
              message: _error!,
              color: Colors.red,
            ),
          ],
          const SizedBox(height: 12),
          AppSurfaceCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.password_outlined),
              title: Text(I18n.tr('profile.change_password')),
              subtitle: Text(I18n.tr('profile.change_password.subtitle')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showDialog(
                context: context,
                builder: (_) => const _ChangePasswordDialog(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocalProfileEditor extends StatefulWidget {
  const _LocalProfileEditor();

  @override
  State<_LocalProfileEditor> createState() => _LocalProfileEditorState();
}

class _LocalProfileEditorState extends State<_LocalProfileEditor> {
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _displayNameCtrl;
  late final TextEditingController _avatarCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _bioCtrl;
  bool _busy = false;
  bool _avatarBusy = false;
  String? _error;
  String? _message;

  @override
  void initState() {
    super.initState();
    final profile = context.read<UserProvider>().profile;
    _usernameCtrl = TextEditingController(text: profile.username);
    _displayNameCtrl = TextEditingController(text: profile.displayName);
    _avatarCtrl = TextEditingController(
      text: profile.avatarUrl.isNotEmpty
          ? profile.avatarUrl
          : profile.avatarInitials,
    );
    _emailCtrl = TextEditingController(text: profile.email);
    _bioCtrl = TextEditingController(text: profile.bio);
    _usernameCtrl.addListener(_refreshPreview);
    _displayNameCtrl.addListener(_refreshPreview);
    _avatarCtrl.addListener(_refreshPreview);
    _emailCtrl.addListener(_refreshPreview);
    _bioCtrl.addListener(_refreshPreview);
  }

  @override
  void dispose() {
    _usernameCtrl.removeListener(_refreshPreview);
    _displayNameCtrl.removeListener(_refreshPreview);
    _avatarCtrl.removeListener(_refreshPreview);
    _emailCtrl.removeListener(_refreshPreview);
    _bioCtrl.removeListener(_refreshPreview);
    _usernameCtrl.dispose();
    _displayNameCtrl.dispose();
    _avatarCtrl.dispose();
    _emailCtrl.dispose();
    _bioCtrl.dispose();
    super.dispose();
  }

  void _refreshPreview() {
    if (mounted) setState(() {});
  }

  Future<void> _pickLocalAvatar() async {
    setState(() {
      _avatarBusy = true;
      _error = null;
      _message = null;
    });
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'Image',
            extensions: ['jpg', 'jpeg', 'png', 'webp', 'gif'],
            mimeTypes: ['image/jpeg', 'image/png', 'image/webp', 'image/gif'],
          ),
        ],
      );
      if (file == null) return;
      final storedPath = await _copyLocalAvatarFile(file);
      if (!mounted) return;
      setState(() {
        _avatarCtrl.text = storedPath;
        _message = I18n.tr('profile.avatar.selected');
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  Future<void> _save() async {
    final username = _usernameCtrl.text.trim();
    if (username.isEmpty) {
      setState(() => _error = I18n.tr('profile.error.nickname_required'));
      return;
    }
    final displayName = _displayNameCtrl.text.trim();
    final avatar = _avatarCtrl.text.trim();
    final avatarIsUrl = _isHttpAvatar(avatar);
    final avatarIsLocalFile = _localAvatarPath(avatar) != null;
    final avatarIsImage = avatarIsUrl || avatarIsLocalFile;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await context.read<UserProvider>().updateProfile(
        username: username,
        avatarInitials: avatarIsImage
            ? _firstNonEmptyProfileText([displayName, username])
            : avatar,
        displayName: displayName,
        email: _emailCtrl.text.trim(),
        avatarUrl: avatarIsImage ? avatar : '',
        bio: _bioCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() => _message = I18n.tr('profile.local.updated'));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(I18n.tr('profile.local.updated'))));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _firstNonEmptyProfileText([
      _displayNameCtrl.text,
      _usernameCtrl.text,
      I18n.tr('profile.default_user'),
    ]);
    final subtitle = _firstNonEmptyProfileText([
      _bioCtrl.text,
      _emailCtrl.text,
      I18n.tr('profile.local'),
    ]);

    return Scaffold(
      appBar: AppBar(
        title: Text(I18n.tr('profile.title')),
        actions: [
          TextButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(I18n.tr('action.save')),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          AppSurfaceCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _ProfileAvatarPreview(
                  avatar: _avatarCtrl.text.trim(),
                  displayName: displayName,
                  radius: 36,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  ),
                  child: Text(I18n.tr('profile.login_account')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppSurfaceCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _displayNameCtrl,
                  decoration: InputDecoration(
                    labelText: I18n.tr('profile.display_name'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _usernameCtrl,
                  decoration: InputDecoration(
                    labelText: I18n.tr('profile.local_nickname'),
                  ),
                ),
                const SizedBox(height: 12),
                _ProfileActionField(
                  field: TextField(
                    controller: _avatarCtrl,
                    decoration: InputDecoration(
                      labelText: I18n.tr('profile.avatar.url_file_or_text'),
                      helperText: I18n.tr('profile.avatar.helper'),
                    ),
                  ),
                  action: OutlinedButton.icon(
                    onPressed: _avatarBusy ? null : _pickLocalAvatar,
                    icon: _avatarBusy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.photo_library_outlined),
                    label: Text(I18n.tr('profile.avatar.choose')),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: I18n.tr('profile.email.local_display'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _bioCtrl,
                  minLines: 3,
                  maxLines: 6,
                  decoration: InputDecoration(
                    labelText: I18n.tr('profile.bio'),
                  ),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            AppInfoBanner(
              icon: Icons.error_outline,
              title: I18n.tr('profile.save_failed'),
              message: _error!,
              color: Colors.red,
            ),
          ],
          if (_message != null) ...[
            const SizedBox(height: 12),
            AppInfoBanner(
              icon: Icons.check_circle_outline,
              title: I18n.tr('profile.saved'),
              message: _message!,
              color: Colors.green,
            ),
          ],
        ],
      ),
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final newPassword = _newCtrl.text;
    if (newPassword.length < 6) {
      setState(() => _error = I18n.tr('auth.error.new_password_short'));
      return;
    }
    if (newPassword != _confirmCtrl.text) {
      setState(() => _error = I18n.tr('auth.error.new_password_mismatch'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthProvider>().changePassword(
        currentPassword: _currentCtrl.text,
        newPassword: newPassword,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(I18n.tr('profile.password.updated'))),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(I18n.tr('profile.change_password')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _currentCtrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: I18n.tr('profile.current_password'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _newCtrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: I18n.tr('auth.new_password'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmCtrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: I18n.tr('profile.confirm_new_password'),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(I18n.tr('action.cancel')),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(I18n.tr('action.save')),
        ),
      ],
    );
  }
}

String _firstNonEmptyProfileText(List<String?> values) {
  for (final value in values) {
    final trimmed = value?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
  }
  return '';
}

String _accountProfileSnapshot(AuthState state) {
  return [
    state.username ?? '',
    state.email ?? '',
    state.emailVerified.toString(),
    state.displayName ?? '',
    state.avatar ?? '',
    state.bio ?? '',
  ].join('\n');
}

bool _isHttpAvatar(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
}

bool _looksLikeEmail(String value) {
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim());
}

String? _localAvatarPath(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri != null && uri.scheme == 'file') {
    return uri.toFilePath();
  }
  if (trimmed.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(trimmed)) {
    return trimmed;
  }
  return null;
}

Future<String> _copyLocalAvatarFile(XFile file) async {
  final bytes = await file.readAsBytes();
  if (bytes.isEmpty) {
    throw Exception(I18n.tr('profile.avatar.empty'));
  }
  if (bytes.length > 3 * 1024 * 1024) {
    throw Exception(I18n.tr('profile.avatar.too_large'));
  }
  final root = await getApplicationDocumentsDirectory();
  final dir = Directory('${root.path}/profile_avatars');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  final filename =
      'avatar_${DateTime.now().microsecondsSinceEpoch}${_avatarExtensionFor(file.name)}';
  final target = File('${dir.path}/$filename');
  await target.writeAsBytes(bytes, flush: true);
  return target.path;
}

String _avatarExtensionFor(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.jpeg')) return '.jpg';
  for (final extension in ['.jpg', '.png', '.webp', '.gif']) {
    if (lower.endsWith(extension)) return extension;
  }
  return '.png';
}
