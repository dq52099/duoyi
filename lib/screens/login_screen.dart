import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:duoyi/desktop_web/desktop_embedded_scope.dart';

import '../core/account_ui_copy.dart';
import '../core/design_tokens.dart';
import '../core/i18n.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../services/api_client.dart';
import '../widgets/brand_background.dart';
import '../widgets/surface_components.dart';

const double _loginContentMaxWidth = 420;

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginActionField extends StatelessWidget {
  final Widget field;
  final Widget action;
  final String? actionLabel;

  const _LoginActionField({
    required this.field,
    required this.action,
    this.actionLabel,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final actionWidth = constraints.maxWidth < 360 ? 68.0 : 76.0;
        final textScaler = MediaQuery.textScalerOf(context);
        final label = actionLabel ?? '';
        final textStyle = appSecondaryMenuItemTextStyle(context);
        final painter = TextPainter(
          text: TextSpan(text: label, style: textStyle),
          textDirection: Directionality.of(context),
          textScaler: textScaler,
        )..layout();
        final neededWidth = label.isEmpty
            ? actionWidth
            : (painter.width + 28.0).ceilToDouble();
        painter.dispose();
        final resolvedActionWidth = math.max(actionWidth, neededWidth);
        final isFinite = constraints.maxWidth.isFinite;
        final shouldWrap =
            isFinite &&
            label.isNotEmpty &&
            (constraints.maxWidth - 8 - resolvedActionWidth < 140.0 ||
                resolvedActionWidth > constraints.maxWidth * 0.45);

        if (shouldWrap) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              field,
              const SizedBox(height: 8),
              SizedBox(width: double.infinity, child: action),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: field),
            const SizedBox(width: 8),
            SizedBox(
              width: resolvedActionWidth,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 40),
                child: action,
              ),
            ),
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
  final _pwdFocus = FocusNode();
  bool _isRegister = false;
  bool _emailLogin = false;
  bool _registerWithEmail = true;
  bool _busy = false;
  bool _sendingEmailCode = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  int _emailCooldownSeconds = 0;
  Timer? _emailCooldownTimer;
  String? _errorKey;
  Object? _errorSource;
  String? _serverMessage;
  String? _messageKey;
  String? _devCode;

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
    _pwdFocus.dispose();
    super.dispose();
  }

  void _refreshControls() {
    if (mounted) setState(() {});
  }

  void _clearFeedback() {
    _errorKey = null;
    _errorSource = null;
    _messageKey = null;
    _serverMessage = null;
    _devCode = null;
  }

  String? _resolveMessage() {
    final devCode = _devCode;
    final codeSuffix = (devCode != null && devCode.isNotEmpty)
        ? ' ${I18n.tr('auth.email_code.code_prefix')}$devCode'
        : '';
    if (_serverMessage != null && _serverMessage!.isNotEmpty) {
      return '$_serverMessage$codeSuffix';
    }
    if (_messageKey != null) {
      return '${I18n.tr(_messageKey!)}$codeSuffix';
    }
    return null;
  }

  String? _resolveError() {
    if (_errorKey != null) {
      return I18n.tr(_errorKey!);
    }
    if (_errorSource != null) {
      return AccountUiCopy.formatError(_errorSource);
    }
    return null;
  }

  Future<void> _submit() async {
    if (_busy || _sendingEmailCode) return;
    final auth = context.read<AuthProvider>();
    final validationError = _validateSubmit(auth);
    if (validationError != null) {
      setState(() {
        _errorKey = validationError;
        _errorSource = null;
      });
      return;
    }
    setState(() {
      _busy = true;
      _clearFeedback();
    });
    final passwordLogin = !_isRegister && !_emailLogin;
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
      if (!mounted) return;
      Navigator.pop(context);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (passwordLogin && _isInvalidCredentialsError(e)) {
        setState(() {
          _errorKey = 'auth.error.invalid_credentials';
          _errorSource = null;
          _pwdCtrl.clear();
        });
        _pwdFocus.requestFocus();
      } else {
        setState(() {
          _errorKey = null;
          _errorSource = e;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorKey = null;
        _errorSource = e;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendEmailCode() async {
    if (!_canSendEmailCode) return;
    final auth = context.read<AuthProvider>();
    final email = _isRegister ? _emailCtrl.text.trim() : _userCtrl.text.trim();
    if (email.isEmpty) {
      setState(() {
        _errorKey = 'auth.error.email_required';
        _errorSource = null;
      });
      return;
    }
    if (!_looksLikeEmail(email)) {
      setState(() {
        _errorKey = 'auth.error.email_invalid';
        _errorSource = null;
      });
      return;
    }
    setState(() {
      _sendingEmailCode = true;
      _clearFeedback();
    });
    try {
      final result = await auth.sendEmailCode(
        email: email,
        purpose: _isRegister ? 'bind' : 'login',
      );
      if (!mounted) return;
      final devCode = (result['dev_code'] ?? '').toString();
      final serverMsg = result['message']?.toString();
      _startEmailCooldown();
      setState(() {
        _devCode = devCode.isNotEmpty ? devCode : null;
        if (serverMsg != null && serverMsg.isNotEmpty) {
          _serverMessage = serverMsg;
          _messageKey = null;
        } else {
          _serverMessage = null;
          _messageKey = 'auth.email_code.sent';
        }
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorKey = null;
        _errorSource = e;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorKey = null;
        _errorSource = e;
      });
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
          ? 'auth.error.username_required'
          : 'auth.error.account_required';
    }
    if (_isRegister) {
      final shouldBindEmail =
          auth.registrationEmailRequired || _registerWithEmail;
      if (account.length < 3 || account.length > 64) {
        return 'auth.error.username_length';
      }
      if (RegExp(r'\s').hasMatch(account)) {
        return 'auth.error.username_no_space';
      }
      final email = _emailCtrl.text.trim();
      if (shouldBindEmail && email.isEmpty) {
        return 'auth.error.email_required';
      }
      if (email.isNotEmpty && !_looksLikeEmail(email)) {
        return 'auth.error.email_invalid';
      }
      if (shouldBindEmail && _emailCodeCtrl.text.trim().isEmpty) {
        return 'auth.error.email_code_required';
      }
      if (_pwdCtrl.text.length < 6) return 'auth.error.password_short';
      if (_confirmPwdCtrl.text != _pwdCtrl.text) {
        return 'auth.error.password_mismatch';
      }
      if (auth.inviteCodeRequired && _inviteCtrl.text.trim().isEmpty) {
        return 'auth.error.invite_required';
      }
    } else if (_emailLogin) {
      if (!_looksLikeEmail(account)) {
        return 'auth.error.verified_email_required';
      }
      if (_emailCodeCtrl.text.trim().isEmpty) {
        return 'auth.error.email_code_input_required';
      }
    } else if (_pwdCtrl.text.isEmpty) {
      return 'auth.error.password_required';
    }
    return null;
  }

  void _startEmailCooldown() {
    if (!mounted) return;
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

  String _emailCodeButtonLabel() {
    if (_sendingEmailCode) return '';
    if (_emailCooldownSeconds > 0) {
      return I18n.current == AppLocale.en
          ? 'Retry in ${_emailCooldownSeconds}s'
          : '${_emailCooldownSeconds}s 后';
    }
    return I18n.tr('auth.send');
  }

  Widget _emailCodeButton() {
    final canSend = _canSendEmailCode;
    return FilledButton(
      onPressed: canSend ? _sendEmailCode : null,
      style: appSecondaryFilledButtonStyle(context),
      child: _sendingEmailCode
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(
              _emailCooldownSeconds > 0
                  ? (I18n.current == AppLocale.en
                        ? 'Retry in ${_emailCooldownSeconds}s'
                        : '${_emailCooldownSeconds}s 后')
                  : I18n.tr('auth.send'),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
    );
  }

  Color _resolveRegistrationFloatingLabelColor(
    BuildContext context,
    Color cardSurface,
  ) {
    final cs = Theme.of(context).colorScheme;
    final surfaceStyle = appSurfaceStyleOf(context);
    final isLiquidGlass =
        surfaceStyle != null && (surfaceStyle.cardFillColor?.a ?? 1.0) < 0.8;
    if (isLiquidGlass) {
      // In liquidGlass, iOS primary blue #0A6CDB has ~4.47:1 contrast on the glass card;
      // #0864CC stays visually true to the iOS blue hue while meeting WCAG 2.1 AA (>= 4.5:1).
      return const Color(0xFF0864CC);
    }

    if (appContrastRatio(cardSurface, cs.primary) >= 4.5) {
      return cs.primary;
    }

    const dark = Color(0xFF111827);
    for (var t = 0.05; t <= 0.60; t += 0.05) {
      final candidate = Color.lerp(cs.primary, dark, t)!;
      if (appContrastRatio(cardSurface, candidate) >= 4.5) {
        return candidate;
      }
    }

    return appReadableForeground(cardSurface, cs.primary);
  }

  Color _resolveAccessibleErrorColor(
    BuildContext context,
    Color background,
    Color errorColor,
  ) {
    final surfaceStyle = appSurfaceStyleOf(context);
    final isLiquidGlass =
        surfaceStyle != null && (surfaceStyle.cardFillColor?.a ?? 1.0) < 0.8;
    // In liquidGlass, the frosted card is layered over the scaffold/backdrop
    // resulting in an effective rendered background of ~#E8EDF2. Color(0xFFA23535)
    // (the brand design token for error) provides > 5.5:1 contrast, whereas 0xFFC64747
    // achieves only ~4.05:1 on the rendered glass background.
    final effectiveError = isLiquidGlass ? const Color(0xFFA23535) : errorColor;
    final effectiveBg = isLiquidGlass
        ? Color.alphaBlend(
            surfaceStyle.cardFillColor ?? background,
            Theme.of(context).scaffoldBackgroundColor,
          )
        : background;

    if (appContrastRatio(effectiveBg, effectiveError) >= 4.5) {
      return effectiveError;
    }
    const dark = Color(0xFF111827);
    for (var t = 0.05; t <= 0.60; t += 0.05) {
      final candidate = Color.lerp(effectiveError, dark, t)!;
      if (appContrastRatio(effectiveBg, candidate) >= 4.5) {
        return candidate;
      }
    }
    return appReadableForeground(effectiveBg, effectiveError);
  }

  static Color _resolveAccessibleMaintenanceColor(
    Color bg,
    Color preferred, {
    required bool isDark,
  }) {
    if (appContrastRatio(bg, preferred) >= 4.5) return preferred;
    final target = isDark ? Colors.white : const Color(0xFF111827);
    for (var t = 0.05; t <= 0.85; t += 0.05) {
      final candidate = Color.lerp(preferred, target, t)!;
      if (appContrastRatio(bg, candidate) >= 4.5) {
        return candidate;
      }
    }
    return appReadableForeground(bg, preferred);
  }

  InputDecoration _registrationInputDecoration({
    required BuildContext context,
    required String labelText,
    String? helperText,
    Widget? suffixIcon,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final surfaceStyle = appSurfaceStyleOf(context);
    final cardSurface = Color.alphaBlend(
      surfaceStyle?.cardFillColor ?? cs.surface,
      cs.surface,
    );
    final labelStyle = appSecondaryControlLabelStyle(context);
    final floatingColor = _resolveRegistrationFloatingLabelColor(
      context,
      cardSurface,
    );
    final textScaler = MediaQuery.textScalerOf(context);
    // When the label wraps to multiple lines and floats, the native OutlineInputBorder
    // vertically centers the scaled floating label on the top border (y = 0).
    // For a multi-line label at high text scale, the floating label extends downwards
    // by (lineCount * lineHeight * 0.75) / 2.0.
    // Providing dynamic vertical padding ensures that the entered text baseline/box
    // is positioned with adequate clearance below any multi-line floating label.
    final verticalPadding = math.max(10.0, textScaler.scale(15.0));

    return InputDecoration(
      isDense: true,
      contentPadding: EdgeInsets.symmetric(
        horizontal: 10,
        vertical: verticalPadding,
      ),
      label: Text(labelText),
      helper: helperText != null
          ? Text(
              helperText,
              style: theme.inputDecorationTheme.helperStyle ??
                  labelStyle.copyWith(color: cs.onSurfaceVariant),
            )
          : null,
      floatingLabelStyle: labelStyle.copyWith(
        color: floatingColor,
        fontWeight: FontWeight.normal,
      ),
      suffixIcon: suffixIcon,
    );
  }

  Widget _emailCodeField({
    required TextEditingController controller,
    required String labelText,
    InputDecoration? decoration,
  }) {
    return AppSecondaryControlTheme(
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: decoration ?? InputDecoration(labelText: labelText),
      ),
    );
  }

  Widget _emailCodeSendField({
    required TextEditingController controller,
    required String labelText,
    InputDecoration? decoration,
  }) {
    return _LoginActionField(
      field: _emailCodeField(
        controller: controller,
        labelText: labelText,
        decoration: decoration,
      ),
      action: _emailCodeButton(),
      actionLabel: _emailCodeButtonLabel(),
    );
  }

  bool _shouldUseVerticalMode(BuildContext context, double availableWidth) {
    if (!availableWidth.isFinite) return false;
    final textScaler = MediaQuery.textScalerOf(context);
    final style = appSecondaryControlTextStyle(context);

    final p1 = TextPainter(
      text: TextSpan(text: I18n.tr('auth.password_login'), style: style),
      textDirection: Directionality.of(context),
      textScaler: textScaler,
    )..layout();
    final w1 = p1.width;
    p1.dispose();

    final p2 = TextPainter(
      text: TextSpan(text: I18n.tr('auth.email_code_login'), style: style),
      textDirection: Directionality.of(context),
      textScaler: textScaler,
    )..layout();
    final w2 = p2.width;
    p2.dispose();

    final maxLabelWidth = math.max(w1, w2);
    final availablePerSegment = (availableWidth / 2) - 32.0;
    return maxLabelWidth > availablePerSegment;
  }

  Widget _buildModeSelector({
    required BuildContext context,
    required double availableWidth,
  }) {
    final useVertical = _shouldUseVerticalMode(context, availableWidth);
    Widget labelFor(String key) {
      final text = Text(I18n.tr(key));
      if (!useVertical) return text;
      return SizedBox(
        width: availableWidth,
        child: Center(child: text),
      );
    }

    return AppSecondaryControlTheme(
      child: SegmentedButton<bool>(
        direction: useVertical ? Axis.vertical : Axis.horizontal,
        showSelectedIcon: false,
        style: useVertical
            ? const ButtonStyle(padding: WidgetStatePropertyAll(EdgeInsets.zero))
            : null,
        segments: [
          ButtonSegment(
            value: false,
            label: labelFor('auth.password_login'),
          ),
          ButtonSegment(
            value: true,
            label: labelFor('auth.email_code_login'),
          ),
        ],
        selected: {_emailLogin},
        onSelectionChanged: _busy
            ? null
            : (values) => setState(() {
                _emailLogin = values.first;
                _clearFeedback();
              }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, locale, _) => _buildLocalized(context),
    );
  }

  Widget _buildLocalized(BuildContext context) {
    final s = context.watch<ThemeProvider>().brand.strings;
    final auth = context.watch<AuthProvider>();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final surfaceStyle = appSurfaceStyleOf(context);
    final isLiquidGlass =
        surfaceStyle != null && (surfaceStyle.cardFillColor?.a ?? 1.0) < 0.8;
    final cardSurface = Color.alphaBlend(
      surfaceStyle?.cardFillColor ?? cs.surface,
      cs.surface,
    );
    final renderedCardSurface = isLiquidGlass
        ? (isDark
            ? Color.alphaBlend(
                surfaceStyle.cardFillColor ?? cs.surface,
                theme.scaffoldBackgroundColor,
              )
            : const Color(0xFFE8EDF2))
        : cardSurface;
    final explanationFg = appReadableForeground(
      cardSurface,
      cs.onSurface.withValues(alpha: 0.75),
    );
    final errorBg = Color.alphaBlend(
      cs.errorContainer.withValues(alpha: 0.45),
      cardSurface,
    );
    final errorFg = appReadableForeground(errorBg, cs.onSurface);
    final messageBg = Color.alphaBlend(
      cs.primaryContainer.withValues(alpha: 0.45),
      cardSurface,
    );
    final messageFg = appReadableForeground(messageBg, cs.onSurface);
    final maintenanceBg = DesignTokens.defaultWarning.withValues(alpha: 0.12);
    final maintenanceEffectiveBg = Color.alphaBlend(
      maintenanceBg,
      renderedCardSurface,
    );
    final maintenanceFg = _resolveAccessibleMaintenanceColor(
      maintenanceEffectiveBg,
      DesignTokens.defaultWarning,
      isDark: isDark,
    );
    final message = _resolveMessage();
    final error = _resolveError();

    final registrationEmailRequired = auth.registrationEmailRequired;
    final shouldBindRegistrationEmail =
        registrationEmailRequired || _registerWithEmail;

    final scaffold = Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(
            _isRegister
                ? I18n.tr('auth.register.title')
                : I18n.tr('auth.login.title'),
          ),
          titleTextStyle: appSecondaryRouteTitleTextStyle(context),
          backgroundColor: Colors.transparent,
        ),
        body: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final horizontalPadding = constraints.maxWidth < 480
                  ? 20.0
                  : 24.0;
              final availableCardWidth =
                  math.min(
                    constraints.maxWidth - horizontalPadding * 2,
                    _loginContentMaxWidth,
                  ) -
                  32.0;
              return ListView(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  8,
                  horizontalPadding,
                  20,
                ),
                children: [
                  Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: _loginContentMaxWidth,
                      ),
                      child: AppSurfaceCard(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                        borderRadius: BorderRadius.circular(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              s.appTitle,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontSize: 16,
                                color: cs.onSurface.withValues(alpha: 0.78),
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _isRegister
                                  ? I18n.tr('auth.register.subtitle')
                                  : (_emailLogin
                                        ? I18n.tr(
                                            'auth.login.subtitle.email_code',
                                          )
                                        : I18n.tr(
                                            'auth.login.subtitle.password',
                                          )),
                              style: TextStyle(
                                color: explanationFg,
                                fontSize: 12,
                                height: 1.3,
                              ),
                            ),
                            if (auth.maintenanceMode) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: DesignTokens.defaultWarning.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.build_circle,
                                      color: maintenanceFg,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        auth.maintenanceMessage.isEmpty
                                            ? I18n.tr('auth.maintenance')
                                            : auth.maintenanceMessage,
                                        style: TextStyle(
                                          color: maintenanceFg,
                                          fontSize: 12,
                                          height: 1.25,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            if (!_isRegister) ...[
                              _buildModeSelector(
                                context: context,
                                availableWidth: availableCardWidth,
                              ),
                              const SizedBox(height: 10),
                            ],
                            if (!_isRegister && _emailLogin)
                              AppSecondaryControlTheme(
                                child: TextField(
                                  controller: _userCtrl,
                                  keyboardType: TextInputType.emailAddress,
                                  decoration: InputDecoration(
                                    labelText: I18n.tr('auth.verified_email'),
                                  ),
                                ),
                              )
                            else
                              AppSecondaryControlTheme(
                                child: TextField(
                                  controller: _userCtrl,
                                  decoration: _isRegister
                                      ? _registrationInputDecoration(
                                          context: context,
                                          labelText: I18n.tr('auth.username'),
                                        )
                                      : InputDecoration(
                                          labelText: I18n.tr('auth.account'),
                                        ),
                                ),
                              ),
                            if (_isRegister) ...[
                              const SizedBox(height: 12),
                              if (!registrationEmailRequired) ...[
                                AppSecondaryControlTheme(
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              I18n.tr('profile.email.binding'),
                                              style: Theme.of(
                                                context,
                                              ).textTheme.bodyMedium,
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              I18n.tr('auth.email.optional'),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: explanationFg,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Transform.scale(
                                        scale: 0.86,
                                        child: Switch.adaptive(
                                          value: _registerWithEmail,
                                          onChanged:
                                              (_busy || _sendingEmailCode)
                                              ? null
                                              : (value) => setState(() {
                                                  _registerWithEmail = value;
                                                  _clearFeedback();
                                                  if (!value) {
                                                    _emailCtrl.clear();
                                                    _emailCodeCtrl.clear();
                                                  }
                                                }),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              if (shouldBindRegistrationEmail) ...[
                                if (!registrationEmailRequired)
                                  const SizedBox(height: 12),
                                AppSecondaryControlTheme(
                                  child: TextField(
                                    controller: _emailCtrl,
                                    keyboardType: TextInputType.emailAddress,
                                    decoration: _registrationInputDecoration(
                                      context: context,
                                      labelText: registrationEmailRequired
                                          ? I18n.tr('auth.email')
                                          : I18n.tr('auth.email.optional'),
                                      helperText: registrationEmailRequired
                                          ? I18n.tr(
                                              'auth.email.required_helper',
                                            )
                                          : null,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                _emailCodeSendField(
                                  controller: _emailCodeCtrl,
                                  labelText: registrationEmailRequired
                                      ? I18n.tr('auth.email_code')
                                      : I18n.tr('auth.email_code.optional'),
                                  decoration: _registrationInputDecoration(
                                    context: context,
                                    labelText: registrationEmailRequired
                                        ? I18n.tr('auth.email_code')
                                        : I18n.tr('auth.email_code.optional'),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              AppSecondaryControlTheme(
                                child: TextField(
                                  controller: _displayNameCtrl,
                                  decoration: _registrationInputDecoration(
                                    context: context,
                                    labelText: I18n.tr(
                                      'auth.display_name.optional',
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            if (!_isRegister && _emailLogin) ...[
                              const SizedBox(height: 12),
                              _emailCodeSendField(
                                controller: _emailCodeCtrl,
                                labelText: I18n.tr('auth.email_code'),
                              ),
                            ],
                            if (_isRegister)
                              const SizedBox(height: 10)
                            else if (!_emailLogin)
                              const SizedBox(height: 10),
                            if (!_emailLogin || _isRegister)
                              AppSecondaryControlTheme(
                                child: TextField(
                                  controller: _pwdCtrl,
                                  focusNode: _pwdFocus,
                                  decoration: _isRegister
                                      ? _registrationInputDecoration(
                                          context: context,
                                          labelText: I18n.tr('auth.password'),
                                          suffixIcon: IconButton(
                                            tooltip: _obscurePassword
                                                ? AccountUiCopy.tooltipShowPassword
                                                : AccountUiCopy.tooltipHidePassword,
                                            icon: Icon(
                                              _obscurePassword
                                                  ? Icons.visibility_off_outlined
                                                  : Icons.visibility_outlined,
                                              size: 18,
                                            ),
                                            onPressed: () => setState(
                                              () => _obscurePassword =
                                                  !_obscurePassword,
                                            ),
                                          ),
                                        )
                                      : InputDecoration(
                                          labelText: I18n.tr('auth.password'),
                                          suffixIcon: IconButton(
                                            tooltip: _obscurePassword
                                                ? AccountUiCopy.tooltipShowPassword
                                                : AccountUiCopy.tooltipHidePassword,
                                            icon: Icon(
                                              _obscurePassword
                                                  ? Icons.visibility_off_outlined
                                                  : Icons.visibility_outlined,
                                              size: 18,
                                            ),
                                            onPressed: () => setState(
                                              () => _obscurePassword =
                                                  !_obscurePassword,
                                            ),
                                          ),
                                        ),
                                  obscureText: _obscurePassword,
                                ),
                              ),
                            if (!_isRegister && !_emailLogin) ...[
                              const SizedBox(height: 4),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  style: TextButton.styleFrom(
                                    minimumSize: const Size(0, 38),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 6,
                                    ),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  onPressed: _busy
                                      ? null
                                      : () => _showPasswordResetDialog(),
                                  child: Text(I18n.tr('auth.forgot_password')),
                                ),
                              ),
                            ],
                            if (_isRegister) ...[
                              const SizedBox(height: 12),
                              AppSecondaryControlTheme(
                                child: TextField(
                                  controller: _confirmPwdCtrl,
                                  decoration: _registrationInputDecoration(
                                    context: context,
                                    labelText: I18n.tr('auth.confirm_password'),
                                    suffixIcon: IconButton(
                                      tooltip: _obscureConfirmPassword
                                          ? AccountUiCopy.tooltipShowPassword
                                          : AccountUiCopy.tooltipHidePassword,
                                      icon: Icon(
                                        _obscureConfirmPassword
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                        size: 18,
                                      ),
                                      onPressed: () => setState(
                                        () => _obscureConfirmPassword =
                                            !_obscureConfirmPassword,
                                      ),
                                    ),
                                  ),
                                  obscureText: _obscureConfirmPassword,
                                ),
                              ),
                            ],
                            if (_isRegister && auth.inviteCodeRequired) ...[
                              const SizedBox(height: 12),
                              AppSecondaryControlTheme(
                                child: TextField(
                                  controller: _inviteCtrl,
                                  decoration: _registrationInputDecoration(
                                    context: context,
                                    labelText: I18n.tr('auth.invite_code'),
                                  ),
                                ),
                              ),
                            ],
                            if (_isRegister && !auth.registrationEnabled) ...[
                              const SizedBox(height: 12),
                              Text(
                                I18n.tr('auth.registration_closed'),
                                style: TextStyle(
                                  color: _resolveAccessibleErrorColor(
                                    context,
                                    cardSurface,
                                    cs.error,
                                  ),
                                  fontSize: 12,
                                  height: 1.25,
                                ),
                              ),
                            ],
                            if (error != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.errorContainer.withValues(
                                    alpha: 0.45,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: cs.error.withValues(alpha: 0.2),
                                    width: 0.5,
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      size: 16,
                                      color: cs.error,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        error,
                                        style: TextStyle(
                                          color: errorFg,
                                          fontSize: 12,
                                          height: 1.3,
                                          fontWeight: FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            if (message != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.primaryContainer.withValues(
                                    alpha: 0.45,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: cs.primary.withValues(alpha: 0.2),
                                    width: 0.5,
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.check_circle_outline,
                                      size: 16,
                                      color: cs.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        message,
                                        style: TextStyle(
                                          color: messageFg,
                                          fontSize: 12,
                                          height: 1.3,
                                          fontWeight: FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 18),
                            FilledButton(
                              style: appSecondaryFilledButtonStyle(context)
                                  .copyWith(
                                    minimumSize: const WidgetStatePropertyAll(
                                      Size(0, 42),
                                    ),
                                    padding: const WidgetStatePropertyAll(
                                      EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 8,
                                      ),
                                    ),
                                  ),
                              onPressed:
                                  _busy ||
                                      _sendingEmailCode ||
                                      (_isRegister && !auth.registrationEnabled)
                                  ? null
                                  : _submit,
                              child: _busy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(
                                      _isRegister
                                          ? I18n.tr('auth.register')
                                          : I18n.tr('auth.login'),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.normal,
                                        fontSize: 14,
                                      ),
                                    ),
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              style: TextButton.styleFrom(
                                minimumSize: const Size(0, 38),
                                padding: EdgeInsets.symmetric(
                                  horizontal:
                                      constraints.maxWidth < 360 ? 8 : 12,
                                  vertical: 8,
                                ),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: _busy || _sendingEmailCode
                                  ? null
                                  : () => setState(() {
                                      _isRegister = !_isRegister;
                                      _emailLogin = false;
                                      _registerWithEmail = true;
                                      _emailCodeCtrl.clear();
                                      _pwdCtrl.clear();
                                      _confirmPwdCtrl.clear();
                                      _clearFeedback();
                                    }),
                              child: Text(
                                _isRegister
                                    ? I18n.tr('auth.switch_to_login')
                                    : I18n.tr('auth.switch_to_register'),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
    return DesktopEmbeddedHostScope.isHosted(context)
        ? scaffold
        : BrandBackground(child: scaffold);
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
  bool _obscureNewPassword = true;
  int _cooldownSeconds = 0;
  Timer? _cooldownTimer;
  String? _errorKey;
  Object? _errorSource;
  String? _serverMessage;
  String? _messageKey;
  String? _devCode;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _accountCtrl.dispose();
    _codeCtrl.dispose();
    _newPwdCtrl.dispose();
    super.dispose();
  }

  String? _resolveMessage() {
    final devCode = _devCode;
    final codeSuffix = (devCode != null && devCode.isNotEmpty)
        ? ' ${I18n.tr('auth.email_code.code_prefix')}$devCode'
        : '';
    if (_serverMessage != null && _serverMessage!.isNotEmpty) {
      return '$_serverMessage$codeSuffix';
    }
    if (_messageKey != null) {
      return '${I18n.tr(_messageKey!)}$codeSuffix';
    }
    return null;
  }

  String? _resolveError() {
    if (_errorKey != null) {
      return I18n.tr(_errorKey!);
    }
    if (_errorSource != null) {
      return AccountUiCopy.formatError(_errorSource);
    }
    return null;
  }

  static Color _resolveAccessibleBannerIconColor(
    Color bg,
    Color preferred, {
    required bool isDark,
  }) {
    if (appContrastRatio(bg, preferred) >= 4.5) return preferred;
    final target = isDark ? Colors.white : const Color(0xFF111827);
    for (var t = 0.05; t <= 0.85; t += 0.05) {
      final candidate = Color.lerp(preferred, target, t)!;
      if (appContrastRatio(bg, candidate) >= 4.5) {
        return candidate;
      }
    }
    return appReadableForeground(bg, preferred);
  }

  Future<void> _request() async {
    final account = _accountCtrl.text.trim();
    if (account.isEmpty) {
      setState(() {
        _errorKey = 'auth.error.reset_account_required';
        _errorSource = null;
      });
      return;
    }
    setState(() {
      _busy = true;
      _errorKey = null;
      _errorSource = null;
      _messageKey = null;
      _serverMessage = null;
      _devCode = null;
    });
    try {
      final result = await context.read<AuthProvider>().requestPasswordReset(
        account: account,
      );
      if (!mounted) return;
      _startCooldown();
      final devCode = (result['dev_code'] ?? '').toString();
      final serverMsg = result['message']?.toString();
      setState(() {
        _requested = true;
        _devCode = devCode.isNotEmpty ? devCode : null;
        if (serverMsg != null && serverMsg.isNotEmpty) {
          _serverMessage = serverMsg;
          _messageKey = null;
        } else {
          _serverMessage = null;
          _messageKey = 'auth.password_reset.email_sent';
        }
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorKey = null;
        _errorSource = e;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorKey = null;
        _errorSource = e;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final account = _accountCtrl.text.trim();
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) {
      setState(() {
        _errorKey = 'auth.error.mail_code_required';
        _errorSource = null;
      });
      return;
    }
    if (_newPwdCtrl.text.length < 6) {
      setState(() {
        _errorKey = 'auth.error.new_password_short';
        _errorSource = null;
      });
      return;
    }
    setState(() {
      _busy = true;
      _errorKey = null;
      _errorSource = null;
      _messageKey = null;
      _serverMessage = null;
      _devCode = null;
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
      if (!mounted) return;
      setState(() {
        _errorKey = null;
        _errorSource = e;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorKey = null;
        _errorSource = e;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startCooldown() {
    if (!mounted) return;
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
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, locale, _) {
        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        final isDark = theme.brightness == Brightness.dark;
        final surfaceStyle = appSurfaceStyleOf(context);
        final dialogSurface = theme.dialogTheme.backgroundColor ??
            (surfaceStyle != null
                ? Color.alphaBlend(
                    surfaceStyle.cardFillColor ?? cs.surface,
                    cs.surface,
                  )
                : cs.surface);

        final textScaler = MediaQuery.textScalerOf(context);
        final topPadding = textScaler.scale(12.0).clamp(10.0, 28.0);
        final inputPadding = EdgeInsets.fromLTRB(10, topPadding, 10, 8);

        final message = _resolveMessage();
        final error = _resolveError();

        final messageBg = cs.primaryContainer.withValues(alpha: 0.45);
        final errorBg = cs.errorContainer.withValues(alpha: 0.45);
        final messageEffectiveBg = Color.alphaBlend(messageBg, dialogSurface);
        final errorEffectiveBg = Color.alphaBlend(errorBg, dialogSurface);

        final messageFg = appReadableForeground(messageEffectiveBg, cs.onSurface);
        final errorFg = appReadableForeground(errorEffectiveBg, cs.onSurface);
        final messageIconColor = _resolveAccessibleBannerIconColor(
          messageEffectiveBg,
          cs.primary,
          isDark: isDark,
        );
        final errorIconColor = _resolveAccessibleBannerIconColor(
          errorEffectiveBg,
          cs.error,
          isDark: isDark,
        );

        return AppDialog(
          title: Text(I18n.tr('auth.password_reset.title')),
          icon: const Icon(Icons.lock_reset_outlined),
          shiftForKeyboard: true,
          content: AppSecondaryControlTheme(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _accountCtrl,
                  enabled: !_requested,
                  keyboardType: TextInputType.text,
                  decoration: InputDecoration(
                    label: Text(
                      I18n.tr('auth.reset_account'),
                      softWrap: true,
                    ),
                    helperText: I18n.tr('auth.reset_account.helper'),
                    helperMaxLines: 5,
                    contentPadding: inputPadding,
                  ),
                ),
                if (_requested) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _codeCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      label: Text(
                        I18n.tr('auth.email_code'),
                        softWrap: true,
                      ),
                      contentPadding: inputPadding,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _newPwdCtrl,
                    obscureText: _obscureNewPassword,
                    decoration: InputDecoration(
                      label: Text(
                        I18n.tr('auth.new_password'),
                        softWrap: true,
                      ),
                      contentPadding: inputPadding,
                      suffixIcon: IconButton(
                        tooltip: _obscureNewPassword
                            ? AccountUiCopy.tooltipShowPassword
                            : AccountUiCopy.tooltipHidePassword,
                        icon: Icon(
                          _obscureNewPassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 18,
                        ),
                        onPressed: () => setState(
                          () => _obscureNewPassword = !_obscureNewPassword,
                        ),
                      ),
                    ),
                  ),
                ],
                if (message != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: messageBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 16,
                          color: messageIconColor,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            message,
                            style: TextStyle(
                              color: messageFg,
                              fontSize: 12,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: errorBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 16,
                          color: errorIconColor,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            error,
                            style: TextStyle(
                              color: errorFg,
                              fontSize: 12,
                              height: 1.25,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 38),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              onPressed: _busy ? null : () => Navigator.pop(context),
              child: Text(I18n.tr('action.cancel')),
            ),
            FilledButton(
              style: appSecondaryFilledButtonStyle(context).copyWith(
                minimumSize: const WidgetStatePropertyAll(Size(0, 38)),
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 14),
                ),
              ),
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
      },
    );
  }
}

bool _looksLikeEmail(String value) {
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim());
}

bool _isInvalidCredentialsError(ApiException error) {
  final message = error.message.toLowerCase();
  return message.contains('invalid credentials') ||
      message.contains('invalid username or password') ||
      message.contains('incorrect username or password') ||
      message.contains('账号或密码') ||
      message.contains('用户名或密码') ||
      (message.startsWith('401:') && message.contains('credentials'));
}
