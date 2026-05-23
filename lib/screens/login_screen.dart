import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/i18n.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../services/api_client.dart';
import '../widgets/brand_background.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginActionField extends StatelessWidget {
  final Widget field;
  final Widget action;

  const _LoginActionField({required this.field, required this.action});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final actionWidth = constraints.maxWidth < 360 ? 108.0 : 132.0;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: field),
            const SizedBox(width: 12),
            SizedBox(width: actionWidth, height: 56, child: action),
          ],
        );
      },
    );
  }
}

class _LoginScreenState extends State<LoginScreen> {
  final _userCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _emailCodeCtrl = TextEditingController();
  final _displayNameCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  final _confirmPwdCtrl = TextEditingController();
  final _inviteCtrl = TextEditingController();
  bool _isRegister = false;
  bool _emailLogin = false;
  bool _busy = false;
  bool _sendingEmailCode = false;
  int _emailCooldownSeconds = 0;
  Timer? _emailCooldownTimer;
  String? _error;
  String? _message;

  bool get _registrationEmailVerificationRequired => true;

  @override
  void initState() {
    super.initState();
    _userCtrl.addListener(_refreshControls);
    _emailCtrl.addListener(_refreshControls);
  }

  @override
  void dispose() {
    _emailCooldownTimer?.cancel();
    _userCtrl.removeListener(_refreshControls);
    _emailCtrl.removeListener(_refreshControls);
    _userCtrl.dispose();
    _emailCtrl.dispose();
    _emailCodeCtrl.dispose();
    _displayNameCtrl.dispose();
    _pwdCtrl.dispose();
    _confirmPwdCtrl.dispose();
    _inviteCtrl.dispose();
    super.dispose();
  }

  void _refreshControls() {
    if (mounted) setState(() {});
  }

  Future<void> _submit() async {
    if (_busy || _sendingEmailCode) return;
    final auth = context.read<AuthProvider>();
    final validationError = _validateSubmit(auth);
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      if (_isRegister) {
        await auth.register(
          username: _userCtrl.text.trim(),
          password: _pwdCtrl.text,
          email: _emailCtrl.text.trim(),
          emailCode: _emailCodeCtrl.text.trim(),
          displayName: _displayNameCtrl.text.trim(),
          inviteCode: auth.inviteCodeRequired ? _inviteCtrl.text.trim() : null,
        );
      } else if (_emailLogin) {
        await auth.emailLogin(
          email: _userCtrl.text.trim(),
          code: _emailCodeCtrl.text.trim(),
        );
      } else {
        await auth.login(
          username: _userCtrl.text.trim(),
          password: _pwdCtrl.text,
        );
      }
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendEmailCode() async {
    if (!_canSendEmailCode) return;
    final auth = context.read<AuthProvider>();
    final email = _isRegister ? _emailCtrl.text.trim() : _userCtrl.text.trim();
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
      final result = await auth.sendEmailCode(
        email: email,
        purpose: _isRegister ? 'bind' : 'login',
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
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _sendingEmailCode = false);
    }
  }

  bool get _canSendEmailCode {
    if (_busy || _sendingEmailCode || _emailCooldownSeconds > 0) return false;
    final email = _isRegister ? _emailCtrl.text.trim() : _userCtrl.text.trim();
    return email.isNotEmpty && _looksLikeEmail(email);
  }

  String? _validateSubmit(AuthProvider auth) {
    final account = _userCtrl.text.trim();
    if (account.isEmpty) {
      return _isRegister
          ? I18n.tr('auth.error.username_required')
          : I18n.tr('auth.error.account_required');
    }
    if (_isRegister) {
      if (account.length < 3 || account.length > 64) {
        return I18n.tr('auth.error.username_length');
      }
      if (RegExp(r'\s').hasMatch(account)) {
        return I18n.tr('auth.error.username_no_space');
      }
      final email = _emailCtrl.text.trim();
      if (_registrationEmailVerificationRequired && email.isEmpty) {
        return I18n.tr('auth.error.email_required');
      }
      if (email.isNotEmpty && !_looksLikeEmail(email)) {
        return I18n.tr('auth.error.email_invalid');
      }
      if ((_registrationEmailVerificationRequired || email.isNotEmpty) &&
          _emailCodeCtrl.text.trim().isEmpty) {
        return I18n.tr('auth.error.email_code_required');
      }
      if (_pwdCtrl.text.length < 6) return I18n.tr('auth.error.password_short');
      if (_confirmPwdCtrl.text != _pwdCtrl.text) {
        return I18n.tr('auth.error.password_mismatch');
      }
      if (auth.inviteCodeRequired && _inviteCtrl.text.trim().isEmpty) {
        return I18n.tr('auth.error.invite_required');
      }
    } else if (_emailLogin) {
      if (!_looksLikeEmail(account)) {
        return I18n.tr('auth.error.verified_email_required');
      }
      if (_emailCodeCtrl.text.trim().isEmpty) {
        return I18n.tr('auth.error.email_code_input_required');
      }
    } else if (_pwdCtrl.text.isEmpty) {
      return I18n.tr('auth.error.password_required');
    }
    return null;
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

  Widget _emailCodeButton() {
    final canSend = _canSendEmailCode;
    return OutlinedButton(
      onPressed: canSend ? _sendEmailCode : null,
      child: _sendingEmailCode
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(
              _emailCooldownSeconds > 0
                  ? '${_emailCooldownSeconds}s 后'
                  : I18n.tr('auth.send'),
              textAlign: TextAlign.center,
            ),
    );
  }

  Widget _emailSendField({
    required TextEditingController controller,
    required String labelText,
    String? helperText,
  }) {
    return _LoginActionField(
      field: TextField(
        controller: controller,
        keyboardType: TextInputType.emailAddress,
        decoration: InputDecoration(
          labelText: labelText,
          helperText: helperText,
        ),
      ),
      action: _emailCodeButton(),
    );
  }

  Widget _emailCodeField({
    required TextEditingController controller,
    required String labelText,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: labelText),
    );
  }

  Widget _emailCodeSendField({
    required TextEditingController controller,
    required String labelText,
  }) {
    return _LoginActionField(
      field: _emailCodeField(controller: controller, labelText: labelText),
      action: _emailCodeButton(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<ThemeProvider>().brand.strings;
    final auth = context.watch<AuthProvider>();
    final cs = Theme.of(context).colorScheme;
    final registrationEmailRequired = _registrationEmailVerificationRequired;

    return BrandBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(
            _isRegister
                ? I18n.tr('auth.register.title')
                : I18n.tr('auth.login.title'),
          ),
          backgroundColor: Colors.transparent,
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          children: [
            const SizedBox(height: 12),
            Text(
              s.appTitle,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w400,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isRegister
                  ? I18n.tr('auth.register.subtitle')
                  : (_emailLogin
                        ? I18n.tr('auth.login.subtitle.email_code')
                        : I18n.tr('auth.login.subtitle.password')),
              style: TextStyle(color: cs.onSurface.withValues(alpha: 0.7)),
            ),
            if (auth.maintenanceMode) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.build_circle,
                      color: Colors.orange,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        auth.maintenanceMessage.isEmpty
                            ? I18n.tr('auth.maintenance')
                            : auth.maintenanceMessage,
                        style: const TextStyle(
                          color: Colors.orange,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            if (!_isRegister) ...[
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: false,
                    label: Text(I18n.tr('auth.password_login')),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text(I18n.tr('auth.email_code_login')),
                  ),
                ],
                selected: {_emailLogin},
                onSelectionChanged: _busy
                    ? null
                    : (values) => setState(() {
                        _emailLogin = values.first;
                        _error = null;
                        _message = null;
                      }),
              ),
              const SizedBox(height: 12),
            ],
            if (!_isRegister && _emailLogin)
              _emailSendField(
                controller: _userCtrl,
                labelText: I18n.tr('auth.verified_email'),
              )
            else
              TextField(
                controller: _userCtrl,
                decoration: InputDecoration(
                  labelText: _isRegister
                      ? I18n.tr('auth.username')
                      : I18n.tr('auth.account'),
                ),
              ),
            if (_isRegister) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: registrationEmailRequired
                      ? I18n.tr('auth.email')
                      : I18n.tr('auth.email.optional'),
                  helperText: registrationEmailRequired
                      ? I18n.tr('auth.email.required_helper')
                      : null,
                ),
              ),
              const SizedBox(height: 12),
              _emailCodeSendField(
                controller: _emailCodeCtrl,
                labelText: registrationEmailRequired
                    ? I18n.tr('auth.email_code')
                    : I18n.tr('auth.email_code.optional'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _displayNameCtrl,
                decoration: InputDecoration(
                  labelText: I18n.tr('auth.display_name.optional'),
                ),
              ),
            ],
            if (!_isRegister && _emailLogin) ...[
              const SizedBox(height: 12),
              _emailCodeField(
                controller: _emailCodeCtrl,
                labelText: I18n.tr('auth.email_code'),
              ),
            ],
            if (!_isRegister) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _busy ? null : () => _showPasswordResetDialog(),
                  child: Text(I18n.tr('auth.forgot_password')),
                ),
              ),
            ],
            if (_isRegister)
              const SizedBox(height: 12)
            else
              const SizedBox(height: 4),
            if (!_emailLogin || _isRegister)
              TextField(
                controller: _pwdCtrl,
                decoration: InputDecoration(
                  labelText: I18n.tr('auth.password'),
                ),
                obscureText: true,
              ),
            if (_isRegister) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _confirmPwdCtrl,
                decoration: InputDecoration(
                  labelText: I18n.tr('auth.confirm_password'),
                ),
                obscureText: true,
              ),
            ],
            if (_isRegister && auth.inviteCodeRequired) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _inviteCtrl,
                decoration: InputDecoration(
                  labelText: I18n.tr('auth.invite_code'),
                ),
              ),
            ],
            if (_isRegister && !auth.registrationEnabled) ...[
              const SizedBox(height: 12),
              Text(
                I18n.tr('auth.registration_closed'),
                style: TextStyle(color: Colors.red, fontSize: 12),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            if (_message != null) ...[
              const SizedBox(height: 12),
              Text(
                _message!,
                style: TextStyle(color: cs.primary, fontSize: 12),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed:
                  _busy ||
                      _sendingEmailCode ||
                      (_isRegister && !auth.registrationEnabled)
                  ? null
                  : _submit,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        _isRegister
                            ? I18n.tr('auth.register')
                            : I18n.tr('auth.login'),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy || _sendingEmailCode
                  ? null
                  : () => setState(() {
                      _isRegister = !_isRegister;
                      _emailLogin = false;
                      _emailCodeCtrl.clear();
                      _pwdCtrl.clear();
                      _confirmPwdCtrl.clear();
                      _error = null;
                      _message = null;
                    }),
              child: Text(
                _isRegister
                    ? I18n.tr('auth.switch_to_login')
                    : I18n.tr('auth.switch_to_register'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPasswordResetDialog() async {
    await showDialog(
      context: context,
      builder: (_) => const _PasswordResetDialog(),
    );
  }
}

class _PasswordResetDialog extends StatefulWidget {
  const _PasswordResetDialog();

  @override
  State<_PasswordResetDialog> createState() => _PasswordResetDialogState();
}

class _PasswordResetDialogState extends State<_PasswordResetDialog> {
  final _accountCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _newPwdCtrl = TextEditingController();
  bool _requested = false;
  bool _busy = false;
  int _cooldownSeconds = 0;
  Timer? _cooldownTimer;
  String? _error;
  String? _message;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _accountCtrl.dispose();
    _codeCtrl.dispose();
    _newPwdCtrl.dispose();
    super.dispose();
  }

  Future<void> _request() async {
    final account = _accountCtrl.text.trim();
    if (account.isEmpty) {
      setState(() => _error = I18n.tr('auth.error.reset_account_required'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final result = await context.read<AuthProvider>().requestPasswordReset(
        account: account,
      );
      _startCooldown();
      final devCode = (result['dev_code'] ?? '').toString();
      final message =
          (result['message'] ?? I18n.tr('auth.password_reset.email_sent'))
              .toString();
      setState(() {
        _requested = true;
        _message = devCode.isEmpty
            ? message
            : '$message ${I18n.tr('auth.email_code.code_prefix')}$devCode';
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final account = _accountCtrl.text.trim();
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) {
      setState(() => _error = I18n.tr('auth.error.mail_code_required'));
      return;
    }
    if (_newPwdCtrl.text.length < 6) {
      setState(() => _error = I18n.tr('auth.error.new_password_short'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final accountLooksEmail = _looksLikeEmail(account);
      await context.read<AuthProvider>().confirmPasswordReset(
        account: account,
        email: accountLooksEmail ? account : null,
        code: code,
        newPassword: _newPwdCtrl.text,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(I18n.tr('auth.password_reset.done'))),
      );
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(I18n.tr('auth.password_reset.title')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _accountCtrl,
              enabled: !_requested,
              keyboardType: TextInputType.text,
              decoration: InputDecoration(
                labelText: I18n.tr('auth.reset_account'),
                helperText: I18n.tr('auth.reset_account.helper'),
              ),
            ),
            if (_requested) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _codeCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: I18n.tr('auth.email_code'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _newPwdCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: I18n.tr('auth.new_password'),
                ),
              ),
            ],
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
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(I18n.tr('action.cancel')),
        ),
        FilledButton(
          onPressed: _busy || (!_requested && _cooldownSeconds > 0)
              ? null
              : (_requested ? _confirm : _request),
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  _requested
                      ? I18n.tr('auth.password_reset.confirm')
                      : (_cooldownSeconds > 0
                            ? '${_cooldownSeconds}s'
                            : I18n.tr('auth.password_reset.send_email')),
                ),
        ),
      ],
    );
  }
}

bool _looksLikeEmail(String value) {
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim());
}
