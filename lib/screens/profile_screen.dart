import 'dart:async';
import 'dart:io' show Directory, File;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import '../providers/achievement_provider.dart';
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: field),
        const SizedBox(width: 12),
        SizedBox(width: 112, height: 56, child: action),
      ],
    );
  }
}

class _ProfileAvatarPicker extends StatelessWidget {
  final Widget child;
  final bool busy;
  final VoidCallback? onTap;
  final String tooltip;

  const _ProfileAvatarPicker({
    required this.child,
    required this.busy,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: busy ? null : onTap,
          child: Stack(
            alignment: Alignment.center,
            children: [
              child,
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: cs.surface, width: 2),
                  ),
                  child: busy
                      ? Padding(
                          padding: const EdgeInsets.all(5),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: cs.onPrimary,
                          ),
                        )
                      : Icon(
                          Icons.photo_camera_outlined,
                          size: 13,
                          color: cs.onPrimary,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileAvatarSheet extends StatelessWidget {
  final String? avatar;
  final String displayName;
  final bool busy;
  final VoidCallback? onChangeAvatar;
  final VoidCallback? onSave;

  const _ProfileAvatarSheet({
    required this.avatar,
    required this.displayName,
    required this.busy,
    required this.onChangeAvatar,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppModalSheet(
      title: '头像',
      subtitle: '查看当前头像，或更换后保存到资料',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: _ProfileAvatarPreview(
              avatar: avatar,
              displayName: displayName,
              radius: 84,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy || onChangeAvatar == null
                      ? null
                      : onChangeAvatar,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('更换头像'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: busy || onSave == null ? null : onSave,
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(I18n.tr('action.save')),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: Text(I18n.tr('action.close')),
          ),
          Text(
            '用户名和账号标识不会随头像保存而改变',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: cs.onSurface.withValues(alpha: 0.58),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ProfileMetricChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ProfileMetricChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      label: '$label $value',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: cs.primaryContainer.withValues(alpha: 0.52),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '$label $value',
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: cs.onPrimaryContainer),
        ),
      ),
    );
  }
}

class _ProfileSectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _ProfileSectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: cs.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurface.withValues(alpha: 0.62),
                ),
              ),
            ],
          ),
        ),
      ],
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
  late final TextEditingController _displayNameCtrl;
  late final TextEditingController _avatarCtrl;
  late final TextEditingController _bioCtrl;
  AuthProvider? _authProvider;
  String? _lastAccountSnapshot;
  bool _syncingControllers = false;
  bool _hasLocalProfileEdits = false;
  bool _busy = false;
  bool _avatarBusy = false;
  String? _error;
  String? _message;

  @override
  void initState() {
    super.initState();
    final state = context.read<AuthProvider>().state;
    _usernameCtrl = TextEditingController(text: state.username ?? '');
    _displayNameCtrl = TextEditingController(text: state.displayName ?? '');
    _avatarCtrl = TextEditingController(text: state.avatar ?? '');
    _bioCtrl = TextEditingController(text: state.bio ?? '');
    _lastAccountSnapshot = _accountProfileSnapshot(state);
    for (final controller in [
      _usernameCtrl,
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
    _authProvider?.removeListener(_handleAuthStateChanged);
    for (final controller in [
      _usernameCtrl,
      _displayNameCtrl,
      _avatarCtrl,
      _bioCtrl,
    ]) {
      controller.removeListener(_handleProfileFieldChanged);
    }
    _usernameCtrl.dispose();
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
    if (_hasLocalProfileEdits || _busy || _avatarBusy) {
      return;
    }
    _applyAccountState(state);
  }

  void _applyAccountState(AuthState state) {
    _syncingControllers = true;
    try {
      _setControllerText(_usernameCtrl, state.username ?? '');
      _setControllerText(_displayNameCtrl, state.displayName ?? '');
      _setControllerText(_avatarCtrl, state.avatar ?? '');
      _setControllerText(_bioCtrl, state.bio ?? '');
    } finally {
      _syncingControllers = false;
    }
    _lastAccountSnapshot = _accountProfileSnapshot(state);
    _hasLocalProfileEdits = false;
    _refreshPreview();
  }

  void _applyUploadedAvatar(AuthState state) {
    _syncingControllers = true;
    try {
      _setControllerText(_avatarCtrl, state.avatar ?? '');
    } finally {
      _syncingControllers = false;
    }
    _lastAccountSnapshot = _accountProfileSnapshot(state);
    _refreshPreview();
  }

  void _setControllerText(TextEditingController controller, String value) {
    if (controller.text == value) return;
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  Future<void> _uploadAvatar() async {
    if (_busy || _avatarBusy) return;
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
      _applyUploadedAvatar(state);
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
      setState(() => _message = I18n.tr('profile.avatar.saved'));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  Future<void> _showAvatarSheet() async {
    if (_busy) return;
    final displayName = _firstNonEmptyProfileText([
      _displayNameCtrl.text,
      _usernameCtrl.text,
      context.read<AuthProvider>().state.displayName,
      context.read<AuthProvider>().state.username,
      I18n.tr('profile.default_user'),
    ]);
    await showAppModalSheet<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          return _ProfileAvatarSheet(
            avatar: _avatarCtrl.text.trim().isEmpty
                ? context.read<AuthProvider>().state.avatar
                : _avatarCtrl.text.trim(),
            displayName: displayName,
            busy: _avatarBusy || _busy,
            onChangeAvatar: () async {
              await _uploadAvatar();
              setSheetState(() {});
            },
            onSave: () async {
              await _save();
              if (!sheetContext.mounted) return;
              Navigator.pop(sheetContext);
            },
          );
        },
      ),
    );
  }

  Future<void> _save() async {
    if (_busy || _avatarBusy) return;
    final username = _usernameCtrl.text.trim();
    if (username.length < 3 || username.length > 64) {
      setState(() => _error = I18n.tr('auth.error.username_length'));
      return;
    }
    if (RegExp(r'\s').hasMatch(username)) {
      setState(() => _error = I18n.tr('auth.error.username_no_space'));
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
        displayName: _displayNameCtrl.text.trim(),
        bio: _bioCtrl.text.trim(),
      );
      final state = auth.state;
      _applyAccountState(state);
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
    final achievements = context.watch<AchievementProvider?>();
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
            onPressed: _busy || _avatarBusy ? null : _save,
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
                _ProfileAvatarPicker(
                  busy: _avatarBusy,
                  tooltip: '查看或编辑头像',
                  onTap: _showAvatarSheet,
                  child: Container(
                    width: 76,
                    height: 76,
                    padding:
                        avatarFrame.id == ThemeProvider.defaultAvatarFrameId
                        ? EdgeInsets.zero
                        : const EdgeInsets.all(3),
                    decoration:
                        avatarFrame.id == ThemeProvider.defaultAvatarFrameId
                        ? null
                        : BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: avatarFrame.colors,
                            ),
                          ),
                    child: _ProfileAvatarPreview(
                      avatar: _avatarCtrl.text.trim().isEmpty
                          ? state.avatar
                          : _avatarCtrl.text.trim(),
                      displayName: displayName.isEmpty ? '我' : displayName,
                      radius: 36,
                    ),
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
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _ProfileMetricChip(
                            icon: Icons.savings_outlined,
                            label: I18n.tr('profile.coins'),
                            value:
                                '${state.coinBalance != 0 ? state.coinBalance : achievements?.coinBalance ?? 0}',
                          ),
                          if (state.username?.trim().isNotEmpty == true)
                            _ProfileMetricChip(
                              icon: Icons.badge_outlined,
                              label: I18n.tr('profile.account_id'),
                              value: state.username!.trim(),
                            ),
                        ],
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
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: I18n.tr('auth.username'),
                    helperText: I18n.tr('profile.username.locked'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppSurfaceCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ProfileSectionHeader(
                  icon: Icons.alternate_email_outlined,
                  title: I18n.tr('profile.email.binding'),
                  subtitle: state.emailVerified
                      ? I18n.tr('profile.email.verified')
                      : I18n.tr('profile.email.unverified_or_pending'),
                ),
                const SizedBox(height: 12),
                AppListTileCard(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.mail_outline),
                  title: Text(
                    state.email?.isNotEmpty == true
                        ? state.email!
                        : I18n.tr('profile.email.unbound'),
                  ),
                  subtitle: Text(
                    state.emailVerified
                        ? I18n.tr('profile.email.verified')
                        : I18n.tr('profile.email.unverified_or_pending'),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy || _avatarBusy
                      ? null
                      : () => showDialog(
                          context: context,
                          builder: (_) => const _EmailBindingDialog(),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppSurfaceCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ProfileSectionHeader(
                  icon: Icons.security_outlined,
                  title: I18n.tr('profile.account_security'),
                  subtitle: I18n.tr('profile.account_security.subtitle'),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _busy || _avatarBusy
                        ? null
                        : () => showDialog(
                            context: context,
                            builder: (_) => const _ChangePasswordDialog(),
                          ),
                    icon: const Icon(Icons.password_outlined),
                    label: Text(I18n.tr('profile.change_password')),
                  ),
                ),
                const SizedBox(height: 4),
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
    _avatarCtrl = TextEditingController(text: profile.avatarUrl);
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
    if (_busy || _avatarBusy) return;
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
        _avatarBusy = false;
      });
      await _save(showSnackBar: false);
      if (!mounted) return;
      setState(() => _message = I18n.tr('profile.avatar.saved'));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  Future<void> _showAvatarSheet() async {
    if (_busy) return;
    final displayName = _firstNonEmptyProfileText([
      _displayNameCtrl.text,
      _usernameCtrl.text,
      I18n.tr('profile.default_user'),
    ]);
    await showAppModalSheet<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          return _ProfileAvatarSheet(
            avatar: _avatarCtrl.text.trim(),
            displayName: displayName,
            busy: _avatarBusy || _busy,
            onChangeAvatar: () async {
              await _pickLocalAvatar();
              setSheetState(() {});
            },
            onSave: () async {
              await _save();
              if (!sheetContext.mounted) return;
              Navigator.pop(sheetContext);
            },
          );
        },
      ),
    );
  }

  Future<void> _save({bool showSnackBar = true}) async {
    if (_busy || _avatarBusy) return;
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
    final avatarInitials = avatarIsImage
        ? _firstNonEmptyProfileText([displayName, username])
        : avatar;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await context.read<UserProvider>().updateProfile(
        username: username,
        avatarInitials: avatarInitials,
        displayName: displayName,
        email: _emailCtrl.text.trim(),
        avatarUrl: avatarIsImage ? avatar : '',
        bio: _bioCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() => _message = I18n.tr('profile.local.updated'));
      if (showSnackBar) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(I18n.tr('profile.local.updated'))),
        );
      }
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
            onPressed: _busy || _avatarBusy ? null : _save,
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
                _ProfileAvatarPicker(
                  busy: _avatarBusy,
                  tooltip: '查看或编辑头像',
                  onTap: _showAvatarSheet,
                  child: _ProfileAvatarPreview(
                    avatar: _avatarCtrl.text.trim(),
                    displayName: displayName,
                    radius: 36,
                  ),
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

class _EmailBindingDialog extends StatefulWidget {
  const _EmailBindingDialog();

  @override
  State<_EmailBindingDialog> createState() => _EmailBindingDialogState();
}

class _EmailBindingDialogState extends State<_EmailBindingDialog> {
  late final TextEditingController _emailCtrl;
  final _codeCtrl = TextEditingController();
  bool _busy = false;
  bool _sending = false;
  int _cooldownSeconds = 0;
  Timer? _cooldownTimer;
  String? _error;
  String? _message;

  @override
  void initState() {
    super.initState();
    _emailCtrl = TextEditingController(
      text: context.read<AuthProvider>().state.email ?? '',
    )..addListener(_refresh);
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _emailCtrl.removeListener(_refresh);
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  bool get _canSend {
    if (_busy || _sending || _cooldownSeconds > 0) return false;
    return _looksLikeEmail(_emailCtrl.text.trim());
  }

  Future<void> _sendCode() async {
    if (!_canSend) return;
    setState(() {
      _sending = true;
      _error = null;
      _message = null;
    });
    try {
      final result = await context.read<AuthProvider>().sendEmailCode(
        email: _emailCtrl.text.trim(),
        purpose: 'bind',
      );
      final devCode = (result['dev_code'] ?? '').toString();
      final message = (result['message'] ?? I18n.tr('auth.email_code.sent'))
          .toString();
      if (!mounted) return;
      _startCooldown();
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
      if (mounted) setState(() => _sending = false);
    }
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _cooldownSeconds = 60);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_cooldownSeconds <= 1) {
        timer.cancel();
        setState(() => _cooldownSeconds = 0);
      } else {
        setState(() => _cooldownSeconds -= 1);
      }
    });
  }

  Widget _sendButton() {
    return OutlinedButton(
      onPressed: _canSend ? _sendCode : null,
      child: _sending
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(
              _cooldownSeconds > 0
                  ? '${_cooldownSeconds}s 后'
                  : I18n.tr('auth.send'),
              textAlign: TextAlign.center,
            ),
    );
  }

  Future<void> _save() async {
    final email = _emailCtrl.text.trim();
    final code = _codeCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _error = I18n.tr('auth.error.email_required'));
      return;
    }
    if (!_looksLikeEmail(email)) {
      setState(() => _error = I18n.tr('auth.error.email_invalid'));
      return;
    }
    if (code.isEmpty) {
      setState(() => _error = I18n.tr('auth.error.email_code_required'));
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
      await auth.updateProfile(email: email, emailCode: code);
      final state = auth.state;
      await userProvider.updateProfile(
        username: _firstNonEmptyProfileText([
          state.displayName,
          state.username,
        ]),
        displayName: state.displayName ?? '',
        email: state.email ?? '',
        emailVerified: state.emailVerified,
        avatarUrl: state.avatar ?? '',
        bio: state.bio ?? '',
      );
      if (!mounted) return;
      Navigator.pop(context);
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
    return AlertDialog(
      title: Text(I18n.tr('profile.email.binding')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ProfileActionField(
              field: TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(labelText: I18n.tr('auth.email')),
              ),
              action: _sendButton(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _codeCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: I18n.tr('auth.email_code'),
                helperText: I18n.tr('profile.email_code.helper'),
              ),
            ),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(
                _message!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 12,
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy || _sending ? null : () => Navigator.pop(context),
          child: Text(I18n.tr('action.cancel')),
        ),
        FilledButton(
          onPressed: _busy || _sending ? null : _save,
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
