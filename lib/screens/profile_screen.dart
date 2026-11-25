import 'dart:async';
import 'dart:io' show Directory, File;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../core/account_ui_copy.dart';
import '../core/design_tokens.dart' show AppSurfaceStyle, DesignTokens;
import '../core/i18n.dart';
import '../core/image_decode_cache.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/user_provider.dart';
import '../services/api_client.dart';
import '../services/account_local_data_cleaner.dart';
import '../widgets/account_status_chip.dart';
import '../widgets/brand_background.dart'
    show BrandBackground, BrandRouteSurface;
import '../widgets/cached_avatar_image.dart';
import '../widgets/controller_dialog.dart' show createControllerDialogRoute;
import '../widgets/surface_components.dart';
import 'login_screen.dart';

const double _profileActionButtonHeight = 36;
const double _profileActionButtonWidth = 68;
const double _profileLongActionButtonWidth = 96;

double _profileInlineActionWidth(BuildContext context) {
  return MediaQuery.sizeOf(context).width < 360
      ? _profileActionButtonWidth
      : _profileLongActionButtonWidth;
}

ThemeProvider? _readThemeProvider(BuildContext context) {
  try {
    final optional = Provider.of<ThemeProvider?>(context, listen: false);
    if (optional != null) return optional;
  } on ProviderNotFoundException {
    // Optional in test fixtures and standalone routes.
  } catch (_) {}
  try {
    return Provider.of<ThemeProvider>(context, listen: false);
  } on ProviderNotFoundException {
    return null;
  } catch (_) {
    return null;
  }
}

class ProfileScreen extends StatelessWidget {
  final bool openAvatarSheetOnStart;

  const ProfileScreen({super.key, this.openAvatarSheetOnStart = false});

  @override
  Widget build(BuildContext context) {
    final child = ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, locale, _) {
        final isLoggedIn = context.select<AuthProvider, bool>(
          (auth) => auth.state.isLoggedIn,
        );
        return isLoggedIn
            ? _AccountProfileEditor(
                openAvatarSheetOnStart: openAvatarSheetOnStart,
              )
            : _LocalProfileEditor(
                openAvatarSheetOnStart: openAvatarSheetOnStart,
              );
      },
    );

    final surfaceStyle = appSurfaceStyleOf(context);
    final isLiquidGlass = surfaceStyle == AppSurfaceStyle.liquidGlass;
    if (!isLiquidGlass) {
      return child;
    }

    final hasBrandSurface =
        context.findAncestorWidgetOfExactType<BrandBackground>() != null ||
        context.findAncestorWidgetOfExactType<BrandRouteSurface>() != null;
    if (hasBrandSurface) {
      return child;
    }

    if (_readThemeProvider(context) == null) {
      return child;
    }

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final routeBackground = theme.brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;
    return Material(
      color: routeBackground,
      child: BrandBackground(child: child),
    );
  }
}

class _ProfileAvatarPreview extends StatelessWidget {
  final String? avatar;
  final String displayName;
  final double radius;
  final Object? cacheKey;

  const _ProfileAvatarPreview({
    required this.avatar,
    required this.displayName,
    required this.radius,
    this.cacheKey,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final value = avatar?.trim() ?? '';
    final networkUrl = _networkAvatarUrl(value);
    final localPath = _localAvatarPath(value);
    final fallback = (networkUrl != null || localPath != null)
        ? displayName
        : (value.isNotEmpty ? value : displayName);
    final hasUserText = fallback.trim().isNotEmpty;
    final letter = hasUserText ? fallback.trim().characters.first : '';

    return CircleAvatar(
      radius: radius,
      backgroundColor: cs.primary,
      child: networkUrl != null
          ? ClipOval(
              child: CachedAvatarImage(
                url: networkUrl,
                cacheKey: cacheKey ?? _avatarCacheKey(networkUrl, null),
                width: radius * 2,
                height: radius * 2,
                fallbackBuilder: (_) => _ProfileAvatarLetter(
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
                cacheWidth: ImageDecodeCache.boundedCachePixels(
                  radius * 2,
                  MediaQuery.devicePixelRatioOf(context),
                ),
                cacheHeight: ImageDecodeCache.boundedCachePixels(
                  radius * 2,
                  MediaQuery.devicePixelRatioOf(context),
                ),
                gaplessPlayback: true,
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
    if (letter.trim().isEmpty) {
      return Icon(Icons.person, size: radius * 1.15, color: color);
    }
    return Text(
      letter,
      style: TextStyle(
        fontSize: radius * 0.62,
        color: color,
        fontWeight: FontWeight.normal,
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
    final stacked = MediaQuery.sizeOf(context).width < 360;
    final actionBox = SizedBox(
      width: stacked ? double.infinity : _profileInlineActionWidth(context),
      height: _profileActionButtonHeight,
      child: action,
    );
    if (stacked) {
      return Column(
        key: const ValueKey('profile_action_field_stacked'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [field, const SizedBox(height: 8), actionBox],
      );
    }
    return Row(
      key: const ValueKey('profile_action_field_inline'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: field),
        const SizedBox(width: 8),
        actionBox,
      ],
    );
  }
}

class _ProfileAvatarEditBadge extends StatelessWidget {
  final bool busy;

  const _ProfileAvatarEditBadge({required this.busy});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: cs.primary,
        shape: BoxShape.circle,
        border: Border.all(
          color: cs.surface.withValues(alpha: 0.90),
          width: 0.45,
        ),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.08),
            blurRadius: 5,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: busy
          ? const Padding(
              padding: EdgeInsets.all(6),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(Icons.edit_outlined, color: cs.onPrimary, size: 14),
    );
  }
}

class _ProfileAvatarWithEdit extends StatelessWidget {
  final Widget child;
  final double size;
  final bool busy;
  final VoidCallback? onPreview;
  final VoidCallback? onEdit;

  const _ProfileAvatarWithEdit({
    required this.child,
    required this.size,
    required this.busy,
    required this.onPreview,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Tooltip(
              message: I18n.tr('profile.avatar.preview'),
              child: Semantics(
                button: true,
                label: I18n.tr('profile.avatar.preview'),
                child: InkWell(
                  key: const ValueKey('profile_avatar_preview_button'),
                  customBorder: const CircleBorder(),
                  onTap: busy ? null : onPreview,
                  child: Center(child: child),
                ),
              ),
            ),
          ),
          Positioned(
            right: -1,
            bottom: -1,
            child: Tooltip(
              message: I18n.tr('profile.avatar.edit'),
              child: Semantics(
                button: true,
                label: I18n.tr('profile.avatar.edit'),
                child: SizedBox.square(
                  key: const ValueKey('profile_avatar_edit_button'),
                  dimension: 44,
                  child: Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: busy ? null : onEdit,
                      child: Center(child: _ProfileAvatarEditBadge(busy: busy)),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (busy)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: cs.surface.withValues(alpha: 0.54),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.primary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProfileAvatarFullScreen extends StatelessWidget {
  final String? avatar;
  final String displayName;
  final Object? cacheKey;
  final VoidCallback? onEdit;

  const _ProfileAvatarFullScreen({
    required this.avatar,
    required this.displayName,
    this.cacheKey,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, locale, child) {
        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            titleTextStyle: appSecondaryRouteTitleTextStyle(
              context,
            ).copyWith(color: Colors.white),
            title: Text(I18n.tr('profile.avatar.title')),
            actions: [
              if (onEdit != null)
                IconButton(
                  tooltip: I18n.tr('profile.avatar.edit'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => onEdit!(),
                    );
                  },
                  icon: const Icon(Icons.edit_outlined),
                ),
            ],
          ),
          body: child!,
        );
      },
      child: Center(
        child: Hero(
          tag: 'profile-avatar-preview',
          child: _ProfileAvatarFullImage(
            avatar: avatar,
            displayName: displayName,
            cacheKey: cacheKey,
          ),
        ),
      ),
    );
  }
}

class _ProfileAvatarFullImage extends StatelessWidget {
  final String? avatar;
  final String displayName;
  final Object? cacheKey;

  const _ProfileAvatarFullImage({
    required this.avatar,
    required this.displayName,
    this.cacheKey,
  });

  @override
  Widget build(BuildContext context) {
    final value = avatar?.trim() ?? '';
    final networkUrl = _networkAvatarUrl(value);
    final localPath = _localAvatarPath(value);
    final image = networkUrl != null
        ? CachedAvatarImage(
            url: networkUrl,
            cacheKey: cacheKey ?? _avatarCacheKey(networkUrl, null),
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.contain,
            fallbackBuilder: _fallbackAvatar,
          )
        : localPath != null
        ? Image.file(
            File(localPath),
            fit: BoxFit.contain,
            cacheWidth: ImageDecodeCache.boundedCachePixels(
              MediaQuery.sizeOf(context).width,
              MediaQuery.devicePixelRatioOf(context),
            ),
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => _fallbackAvatar(context),
          )
        : null;

    return SizedBox.expand(
      child: InteractiveViewer(
        minScale: 0.8,
        maxScale: 4,
        child: Center(child: image ?? _fallbackAvatar(context)),
      ),
    );
  }

  Widget _fallbackAvatar(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final radius = (size.shortestSide * 0.28).clamp(84.0, 150.0);
    final value = avatar?.trim() ?? '';
    final networkUrl = _networkAvatarUrl(value);
    final localPath = _localAvatarPath(value);
    final fallback = (networkUrl != null || localPath != null)
        ? displayName
        : (value.isNotEmpty ? value : displayName);
    final hasUserText = fallback.trim().isNotEmpty;
    final letter = hasUserText ? fallback.trim().characters.first : '';
    return CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.primary,
      child: _ProfileAvatarLetter(
        letter: letter,
        radius: radius,
        color: Theme.of(context).colorScheme.onPrimary,
      ),
    );
  }
}

sealed class _ProfileStateText {
  const _ProfileStateText();

  String resolve();

  const factory _ProfileStateText.key(String key) = _ProfileKeyText;
  const factory _ProfileStateText.error(Object? error) = _ProfileErrorText;
  const factory _ProfileStateText.copy(String Function() resolver) =
      _ProfileCopyText;
  const factory _ProfileStateText.emailCodeSent({
    required String devCode,
    String? rawMessage,
  }) = _ProfileEmailCodeSentText;
}

class _ProfileKeyText extends _ProfileStateText {
  final String key;
  const _ProfileKeyText(this.key);

  @override
  String resolve() => I18n.tr(key);
}

class _ProfileErrorText extends _ProfileStateText {
  final Object? error;
  const _ProfileErrorText(this.error);

  @override
  String resolve() => AccountUiCopy.formatError(error);
}

class _ProfileCopyText extends _ProfileStateText {
  final String Function() resolver;
  const _ProfileCopyText(this.resolver);

  @override
  String resolve() => resolver();
}

enum _ProfileMirrorReason { profile, email }

class _PendingProfileMirror {
  final _ProfileMirrorReason reason;

  _PendingProfileMirror(this.reason);
}

class _ProfileMirrorFailureText extends _ProfileStateText {
  final _ProfileMirrorReason reason;

  const _ProfileMirrorFailureText(this.reason);

  @override
  String resolve() => reason == _ProfileMirrorReason.email
      ? AccountUiCopy.emailBoundLocalSyncFailed
      : AccountUiCopy.profileSavedLocalSyncFailed;
}

class _ProfileEmailCodeSentText extends _ProfileStateText {
  final String devCode;
  final String? rawMessage;
  const _ProfileEmailCodeSentText({required this.devCode, this.rawMessage});

  @override
  String resolve() {
    final trimmed = rawMessage?.trim();
    final String msg;
    if (trimmed == null || trimmed.isEmpty) {
      msg = I18n.tr('auth.email_code.sent');
    } else if (trimmed == '验证码已发送，请查看邮箱。' || trimmed == '验证码已发送，请查看邮箱') {
      msg = I18n.tr('auth.email_code.sent_check_email');
    } else if (trimmed == '验证码已发送，请查收邮箱' ||
        trimmed == '验证码已发送，请查收邮箱。' ||
        trimmed == 'Verification code sent. Check your email.' ||
        trimmed == 'Verification code sent. Check your email') {
      msg = I18n.tr('auth.email_code.sent');
    } else if (trimmed == '验证码已发送' ||
        trimmed == '验证码已发送。' ||
        trimmed == 'Code sent' ||
        trimmed == 'Code sent.') {
      msg = AccountUiCopy.feedbackCodeSent;
    } else {
      msg = rawMessage!;
    }

    if (devCode.trim().isEmpty) return msg;
    return '$msg ${I18n.tr('auth.email_code.code_prefix')}$devCode';
  }
}

class _ProfileLocaleText extends StatelessWidget {
  final String keyName;

  const _ProfileLocaleText(this.keyName);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLocale>(
      valueListenable: I18n.localeListenable,
      builder: (context, locale, _) {
        return Text(I18n.tr(keyName));
      },
    );
  }
}

String _feedbackAvatarSaved() => AccountUiCopy.feedbackAvatarSaved;
String _feedbackLocalSynced() => AccountUiCopy.feedbackLocalSynced;

class _ChangePasswordDialog extends StatefulWidget {
  final AuthProvider? auth;
  final AuthSessionLease? sessionLease;
  final int? originGeneration;
  final String? originUserId;

  const _ChangePasswordDialog({
    this.auth,
    this.sessionLease,
    this.originGeneration,
    this.originUserId,
  });

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  late final AuthProvider _auth;
  late final AuthSessionLease? _sessionLease;
  late final int _originGeneration;
  late final String? _originUserId;
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _saving = false;
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  _ProfileStateText? _error;
  bool _hasDependencySnapshot = false;
  ThemeData? _lastTheme;
  Locale? _lastLocalizationsLocale;
  AppLocale? _lastI18nLocale;
  Size? _lastMediaSize;
  EdgeInsets? _lastViewInsets;
  EdgeInsets? _lastPadding;
  EdgeInsets? _lastViewPadding;
  TextScaler? _lastTextScaler;
  bool _revealScheduled = false;
  bool _insetTransitionPending = false;
  Duration? _insetTransitionStart;
  int _insetSettleProbes = 0;
  double? _lastNotifiedViewportDimension;
  double? _lastNotifiedMinScrollExtent;
  double? _lastNotifiedMaxScrollExtent;
  double? _lastRevealedViewportDimension;
  double? _lastRevealedMinScrollExtent;
  double? _lastRevealedMaxScrollExtent;

  @override
  void initState() {
    super.initState();
    I18n.localeListenable.addListener(_handleLocaleChanged);
    _auth = widget.auth ?? context.read<AuthProvider>();
    _sessionLease =
        widget.sessionLease ??
        (_auth.state.isLoggedIn ? _auth.captureSessionLease() : null);
    _originGeneration =
        widget.originGeneration ??
        AccountLocalDataCleaner.accountDataGeneration;
    _originUserId = widget.originUserId ?? _auth.state.userId;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final theme = Theme.of(context);
    final localizationsLocale = Localizations.maybeLocaleOf(context);
    final i18nLocale = I18n.localeListenable.value;
    final mediaSize = MediaQuery.maybeSizeOf(context);
    final viewInsets = MediaQuery.maybeViewInsetsOf(context);
    final padding = MediaQuery.maybePaddingOf(context);
    final viewPadding = MediaQuery.maybeViewPaddingOf(context);
    final textScaler = MediaQuery.maybeTextScalerOf(context);

    if (!_hasDependencySnapshot) {
      _hasDependencySnapshot = true;
      _lastTheme = theme;
      _lastLocalizationsLocale = localizationsLocale;
      _lastI18nLocale = i18nLocale;
      _lastMediaSize = mediaSize;
      _lastViewInsets = viewInsets;
      _lastPadding = padding;
      _lastViewPadding = viewPadding;
      _lastTextScaler = textScaler;
      return;
    }

    final viewInsetsChanged = _lastViewInsets?.bottom != viewInsets?.bottom;
    final layoutChanged =
        _lastTheme != theme ||
        _lastLocalizationsLocale != localizationsLocale ||
        _lastI18nLocale != i18nLocale ||
        _lastMediaSize != mediaSize ||
        _lastViewInsets != viewInsets ||
        _lastPadding != padding ||
        _lastViewPadding != viewPadding ||
        _lastTextScaler != textScaler;

    _lastTheme = theme;
    _lastLocalizationsLocale = localizationsLocale;
    _lastI18nLocale = i18nLocale;
    _lastMediaSize = mediaSize;
    _lastViewInsets = viewInsets;
    _lastPadding = padding;
    _lastViewPadding = viewPadding;
    _lastTextScaler = textScaler;

    if (viewInsetsChanged && TickerMode.valuesOf(context).enabled) {
      _insetTransitionPending = true;
      _insetTransitionStart = null;
      _insetSettleProbes = 0;
    }

    if (layoutChanged) {
      _scheduleFocusedSelectionReveal();
    }
  }

  @override
  void dispose() {
    _revealScheduled = false;
    _insetTransitionPending = false;
    _insetTransitionStart = null;
    _insetSettleProbes = 0;
    I18n.localeListenable.removeListener(_handleLocaleChanged);
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _handleLocaleChanged() {
    if (!mounted) return;
    _lastI18nLocale = I18n.localeListenable.value;
    _scheduleFocusedSelectionReveal();
    setState(() {});
  }

  bool _handleScrollMetricsNotification(ScrollMetricsNotification notification) {
    if (!mounted) return false;
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    final metrics = notification.metrics;
    if (!metrics.hasViewportDimension || !metrics.hasContentDimensions) {
      return false;
    }
    final sameAsNotified =
        _lastNotifiedViewportDimension != null &&
        (metrics.viewportDimension - _lastNotifiedViewportDimension!).abs() <
            0.01 &&
        (metrics.minScrollExtent - _lastNotifiedMinScrollExtent!).abs() <
            0.01 &&
        (metrics.maxScrollExtent - _lastNotifiedMaxScrollExtent!).abs() < 0.01;
    if (sameAsNotified) {
      return false;
    }
    _lastNotifiedViewportDimension = metrics.viewportDimension;
    _lastNotifiedMinScrollExtent = metrics.minScrollExtent;
    _lastNotifiedMaxScrollExtent = metrics.maxScrollExtent;

    final sameAsRevealed =
        _lastRevealedViewportDimension != null &&
        (metrics.viewportDimension - _lastRevealedViewportDimension!).abs() <
            0.01 &&
        (metrics.minScrollExtent - _lastRevealedMinScrollExtent!).abs() <
            0.01 &&
        (metrics.maxScrollExtent - _lastRevealedMaxScrollExtent!).abs() < 0.01;
    if (!sameAsRevealed &&
        metrics.viewportDimension > 0 &&
        FocusManager.instance.primaryFocus?.hasFocus == true) {
      _scheduleFocusedSelectionReveal(
        requestFrame:
            !_insetTransitionPending ||
            WidgetsBinding.instance.transientCallbackCount == 0,
      );
    }
    return false;
  }

  void _scheduleFocusedSelectionReveal({bool requestFrame = false}) {
    if (!mounted) return;
    if (requestFrame) {
      WidgetsBinding.instance.scheduleFrame();
    }
    if (_revealScheduled) return;
    _revealScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback(_onRevealPostFrame);
  }

  void _onRevealPostFrame(Duration timeStamp) {
    _revealScheduled = false;
    if (!mounted) {
      _insetTransitionPending = false;
      return;
    }
    final ownerRoute = ModalRoute.of(context);
    if (ownerRoute != null && !ownerRoute.isCurrent) {
      _insetTransitionPending = false;
      return;
    }
    if (_insetTransitionPending) {
      _insetTransitionStart ??= timeStamp;
      final elapsed = timeStamp - _insetTransitionStart!;
      final hasActiveTickers =
          WidgetsBinding.instance.transientCallbackCount > 0;
      final transitionSettled =
          (!hasActiveTickers &&
              elapsed >= const Duration(milliseconds: 180)) ||
          elapsed >= const Duration(milliseconds: 250) ||
          _insetSettleProbes >= 60;
      if (!transitionSettled) {
        _insetSettleProbes++;
        _scheduleFocusedSelectionReveal(requestFrame: !hasActiveTickers);
        return;
      }
      _insetTransitionPending = false;
      _insetTransitionStart = null;
      _insetSettleProbes = 0;
    }
    _revealFocusedSelectionIfNeeded();
  }

  void _revealFocusedSelectionIfNeeded() {
    if (!mounted) return;
    final ownerRoute = ModalRoute.of(context);
    if (ownerRoute != null && !ownerRoute.isCurrent) return;

    final primaryFocus = FocusManager.instance.primaryFocus;
    final focusContext = primaryFocus?.context;
    if (primaryFocus == null ||
        !primaryFocus.hasFocus ||
        focusContext == null ||
        !focusContext.mounted) {
      return;
    }

    final editableState =
        focusContext.findAncestorStateOfType<EditableTextState>();
    if (editableState == null || !editableState.mounted) return;

    final controller = editableState.widget.controller;
    final isOwnedController =
        identical(controller, _currentCtrl) ||
        identical(controller, _newCtrl) ||
        identical(controller, _confirmCtrl);
    if (!isOwnedController) return;
    if (!identical(
      editableState.context.findAncestorStateOfType<_ChangePasswordDialogState>(),
      this,
    )) {
      return;
    }

    final selection = editableState.textEditingValue.selection;
    final textLength = editableState.textEditingValue.text.length;
    if (!selection.isValid || selection.extentOffset > textLength) return;

    final editableRender = editableState.context.findRenderObject();
    if (editableRender == null || !editableRender.attached) return;
    final renderEditable = editableState.renderEditable;
    if (!renderEditable.attached || !renderEditable.hasSize) return;

    final scrollable = Scrollable.maybeOf(editableState.context);
    if (scrollable != null) {
      final position = scrollable.position;
      if (!position.hasPixels || position.viewportDimension <= 0) {
        return;
      }
      _lastRevealedViewportDimension = position.viewportDimension;
      _lastRevealedMinScrollExtent = position.minScrollExtent;
      _lastRevealedMaxScrollExtent = position.maxScrollExtent;
    }

    editableState.bringIntoView(selection.extent);
  }

  bool _isCurrentSession() {
    if (!mounted) return false;
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
      _originGeneration,
    )) {
      return false;
    }
    if (_auth.state.userId != _originUserId) return false;
    if (!_auth.state.isLoggedIn) return false;
    if (_sessionLease != null && !_auth.isSessionLeaseCurrent(_sessionLease)) {
      return false;
    }
    return true;
  }

  Future<void> _submit() async {
    if (!mounted || _saving) return;
    final ownerRoute = ModalRoute.of(context);
    if (ownerRoute != null && !ownerRoute.isCurrent) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final current = _currentCtrl.text;
    final next = _newCtrl.text;
    final confirm = _confirmCtrl.text;
    if (current.isEmpty) {
      setState(
        () => _error = const _ProfileStateText.key('profile.current_password'),
      );
      return;
    }
    if (next.length < 6) {
      setState(
        () => _error = const _ProfileStateText.key(
          'auth.error.new_password_short',
        ),
      );
      return;
    }
    if (next != confirm) {
      setState(
        () => _error = const _ProfileStateText.key(
          'auth.error.new_password_mismatch',
        ),
      );
      return;
    }
    if (!_isCurrentSession()) {
      setState(
        () => _error = _ProfileStateText.error(AccountUiCopy.accountChanged),
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _auth.changePassword(
        currentPassword: current,
        newPassword: next,
        sessionLease: _sessionLease,
      );
      if (!mounted || (ownerRoute != null && !ownerRoute.isCurrent)) return;
      if (_auth.state.isLoggedIn && !_isCurrentSession()) return;
      final isExpectedGuest = !_auth.state.isLoggedIn;
      final isOriginRetained = _isCurrentSession();
      if (!isExpectedGuest && !isOriginRetained) return;
      if (navigator.canPop()) navigator.pop(true);
      messenger?.showSnackBar(
        SnackBar(
          content: ValueListenableBuilder<AppLocale>(
            valueListenable: I18n.localeListenable,
            builder: (context, _, _) =>
                Text(AccountUiCopy.feedbackPasswordChangedRelogin),
          ),
        ),
      );
    } on ApiException catch (e) {
      if (_isCurrentSession() && (ownerRoute == null || ownerRoute.isCurrent)) {
        setState(() => _error = _ProfileStateText.error(e));
      }
    } catch (e) {
      if (_isCurrentSession() && (ownerRoute == null || ownerRoute.isCurrent)) {
        setState(() => _error = _ProfileStateText.error(e));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: _handleScrollMetricsNotification,
      child: AppDialog(
        title: Text(I18n.tr('profile.change_password')),
        icon: const Icon(Icons.lock_reset_outlined),
        shiftForKeyboard: true,
        content: AppSecondaryControlTheme(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _currentCtrl,
                obscureText: _obscureCurrent,
                decoration: InputDecoration(
                  labelText: I18n.tr('profile.current_password'),
                  hintText: I18n.tr('profile.current_password'),
                  hintMaxLines: 3,
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  suffixIcon: IconButton(
                    tooltip: _obscureCurrent
                        ? AccountUiCopy.tooltipShowPassword
                        : AccountUiCopy.tooltipHidePassword,
                    icon: Icon(
                      _obscureCurrent
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                    ),
                    onPressed: () =>
                        setState(() => _obscureCurrent = !_obscureCurrent),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _newCtrl,
                obscureText: _obscureNew,
                decoration: InputDecoration(
                  labelText: I18n.tr('auth.new_password'),
                  hintText: I18n.tr('auth.new_password'),
                  hintMaxLines: 3,
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  suffixIcon: IconButton(
                    tooltip: _obscureNew
                        ? AccountUiCopy.tooltipShowPassword
                        : AccountUiCopy.tooltipHidePassword,
                    icon: Icon(
                      _obscureNew
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                    ),
                    onPressed: () => setState(() => _obscureNew = !_obscureNew),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _confirmCtrl,
                obscureText: _obscureConfirm,
                decoration: InputDecoration(
                  labelText: I18n.tr('profile.confirm_new_password'),
                  hintText: I18n.tr('profile.confirm_new_password'),
                  hintMaxLines: 3,
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  suffixIcon: IconButton(
                    tooltip: _obscureConfirm
                        ? AccountUiCopy.tooltipShowPassword
                        : AccountUiCopy.tooltipHidePassword,
                    icon: Icon(
                      _obscureConfirm
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                    ),
                    onPressed: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                AppInfoBanner(
                  icon: Icons.error_outline,
                  title: I18n.tr('profile.save_failed'),
                  message: _error!.resolve(),
                  color: Theme.of(context).colorScheme.error,
                  margin: EdgeInsets.zero,
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            child: Text(I18n.tr('action.cancel')),
          ),
          SizedBox(
            width: _profileActionButtonWidth,
            height: _profileActionButtonHeight,
            child: FilledButton(
              onPressed: _saving ? null : _submit,
              style: appSecondaryFilledButtonStyle(context),
              child: _saving
                  ? const SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(I18n.tr('action.save'), maxLines: 1),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmailBindingDialog extends StatefulWidget {
  final String initialEmail;
  final AuthProvider? auth;
  final AuthSessionLease? sessionLease;
  final int? originGeneration;
  final String? originUserId;

  const _EmailBindingDialog({
    required this.initialEmail,
    this.auth,
    this.sessionLease,
    this.originGeneration,
    this.originUserId,
  });

  @override
  State<_EmailBindingDialog> createState() => _EmailBindingDialogState();
}

class _EmailBindingDialogState extends State<_EmailBindingDialog> {
  late final AuthProvider _auth;
  late final AuthSessionLease? _sessionLease;
  late final int _originGeneration;
  late final String? _originUserId;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _emailCodeCtrl;
  bool _sending = false;
  bool _binding = false;
  int _cooldownSeconds = 0;
  Timer? _cooldownTimer;
  _ProfileStateText? _message;
  _ProfileStateText? _error;

  @override
  void initState() {
    super.initState();
    I18n.localeListenable.addListener(_handleLocaleChanged);
    _auth = widget.auth ?? context.read<AuthProvider>();
    _sessionLease =
        widget.sessionLease ??
        (_auth.state.isLoggedIn ? _auth.captureSessionLease() : null);
    _originGeneration =
        widget.originGeneration ??
        AccountLocalDataCleaner.accountDataGeneration;
    _originUserId = widget.originUserId ?? _auth.state.userId;
    _emailCtrl = TextEditingController(text: widget.initialEmail);
    _emailCodeCtrl = TextEditingController();
    _emailCtrl.addListener(_refresh);
  }

  @override
  void dispose() {
    I18n.localeListenable.removeListener(_handleLocaleChanged);
    _cooldownTimer?.cancel();
    _emailCtrl.removeListener(_refresh);
    _emailCtrl.dispose();
    _emailCodeCtrl.dispose();
    super.dispose();
  }

  void _handleLocaleChanged() {
    if (mounted) setState(() {});
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  bool _isCurrentSession() {
    if (!mounted) return false;
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
      _originGeneration,
    )) {
      return false;
    }
    if (_auth.state.userId != _originUserId) return false;
    if (!_auth.state.isLoggedIn) return false;
    if (_sessionLease != null && !_auth.isSessionLeaseCurrent(_sessionLease)) {
      return false;
    }
    return true;
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

  Future<void> _sendEmailCode() async {
    if (!mounted || _sending || _binding || _cooldownSeconds > 0) return;
    final ownerRoute = ModalRoute.of(context);
    if (ownerRoute != null && !ownerRoute.isCurrent) return;
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(
        () => _error = const _ProfileStateText.key('auth.error.email_required'),
      );
      return;
    }
    if (!_looksLikeEmail(email)) {
      setState(
        () => _error = const _ProfileStateText.key('auth.error.email_invalid'),
      );
      return;
    }
    if (!_isCurrentSession()) {
      setState(
        () => _error = _ProfileStateText.error(AccountUiCopy.accountChanged),
      );
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
      _message = null;
    });
    try {
      final result = await _auth.sendBindEmailCode(
        email: email,
        sessionLease: _sessionLease,
      );
      final devCode = (result['dev_code'] ?? '').toString();
      final rawMessage = result['message']?.toString();
      if (!mounted ||
          !_isCurrentSession() ||
          (ownerRoute != null && !ownerRoute.isCurrent)) {
        return;
      }
      _startCooldown();
      setState(() {
        _message = _ProfileStateText.emailCodeSent(
          devCode: devCode,
          rawMessage: rawMessage,
        );
      });
    } on ApiException catch (e) {
      if (_isCurrentSession() && (ownerRoute == null || ownerRoute.isCurrent)) {
        setState(() => _error = _ProfileStateText.error(e));
      }
    } catch (e) {
      if (_isCurrentSession() && (ownerRoute == null || ownerRoute.isCurrent)) {
        setState(() => _error = _ProfileStateText.error(e));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _bindEmail() async {
    if (!mounted || _sending || _binding) return;
    final ownerRoute = ModalRoute.of(context);
    if (ownerRoute != null && !ownerRoute.isCurrent) return;
    final email = _emailCtrl.text.trim();
    final code = _emailCodeCtrl.text.trim();
    if (email.isEmpty) {
      setState(
        () => _error = const _ProfileStateText.key('auth.error.email_required'),
      );
      return;
    }
    if (!_looksLikeEmail(email)) {
      setState(
        () => _error = const _ProfileStateText.key('auth.error.email_invalid'),
      );
      return;
    }
    if (code.isEmpty) {
      setState(
        () => _error = const _ProfileStateText.key(
          'auth.error.email_code_required',
        ),
      );
      return;
    }
    if (!_isCurrentSession()) {
      setState(
        () => _error = _ProfileStateText.error(AccountUiCopy.accountChanged),
      );
      return;
    }
    setState(() {
      _binding = true;
      _error = null;
      _message = null;
    });
    try {
      await _auth.bindEmail(
        email: email,
        code: code,
        sessionLease: _sessionLease,
      );
      if (!mounted ||
          !_isCurrentSession() ||
          (ownerRoute != null && !ownerRoute.isCurrent)) {
        return;
      }
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (_isCurrentSession() && (ownerRoute == null || ownerRoute.isCurrent)) {
        setState(() => _error = _ProfileStateText.error(e));
      }
    } catch (e) {
      if (_isCurrentSession() && (ownerRoute == null || ownerRoute.isCurrent)) {
        setState(() => _error = _ProfileStateText.error(e));
      }
    } finally {
      if (mounted) setState(() => _binding = false);
    }
  }

  Widget _sendButton(BuildContext context) {
    final email = _emailCtrl.text.trim();
    final canSend = email.isNotEmpty && _looksLikeEmail(email);
    return SizedBox(
      height: _profileActionButtonHeight,
      child: FilledButton(
        onPressed: (_sending || _binding || _cooldownSeconds > 0 || !canSend)
            ? null
            : _sendEmailCode,
        style: appSecondaryFilledButtonStyle(context),
        child: _sending
            ? const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _cooldownSeconds > 0
                      ? '${_cooldownSeconds}s'
                      : I18n.tr('auth.send'),
                  maxLines: 1,
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: Text(I18n.tr('profile.email.binding')),
      icon: const Icon(Icons.alternate_email_outlined),
      shiftForKeyboard: true,
      content: AppSecondaryControlTheme(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: I18n.tr('auth.email'),
                prefixIcon: const Icon(Icons.mail_outline),
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
              action: _sendButton(context),
            ),
            if (_message != null) ...[
              const SizedBox(height: 10),
              AppInfoBanner(
                icon: Icons.check_circle_outline,
                title: I18n.tr('profile.saved'),
                message: _message!.resolve(),
                color: DesignTokens.defaultSuccess,
                margin: EdgeInsets.zero,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              AppInfoBanner(
                icon: Icons.error_outline,
                title: I18n.tr('profile.save_failed'),
                message: _error!.resolve(),
                color: Theme.of(context).colorScheme.error,
                margin: EdgeInsets.zero,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: (_sending || _binding)
              ? null
              : () => Navigator.pop(context, false),
          child: Text(I18n.tr('action.cancel')),
        ),
        SizedBox(
          width: _profileLongActionButtonWidth,
          height: _profileActionButtonHeight,
          child: FilledButton(
            onPressed: (_sending || _binding) ? null : _bindEmail,
            style: appSecondaryFilledButtonStyle(context),
            child: _binding
                ? const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(I18n.tr('profile.email.binding')),
                  ),
          ),
        ),
      ],
    );
  }
}

class _ProfileMetricChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool tabularFigures;

  const _ProfileMetricChip({
    required this.icon,
    required this.label,
    required this.value,
    this.tabularFigures = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final surfaceStyle = appSurfaceStyleOf(context);
    final chipBackground = cs.primaryContainer.withValues(alpha: 0.52);
    final Color foreground;
    if (surfaceStyle != null) {
      final cardFill = surfaceStyle.cardFillColor ?? cs.surface;
      final cardBackground = Color.alphaBlend(
        cardFill,
        Color.alphaBlend(theme.scaffoldBackgroundColor, cs.surface),
      );
      final compositedBackground = Color.alphaBlend(
        chipBackground,
        cardBackground,
      );
      foreground = appReadableForeground(
        compositedBackground,
        cs.onPrimaryContainer,
      );
    } else {
      foreground = cs.onPrimaryContainer;
    }
    return Semantics(
      label: '$label $value',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: chipBackground,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, size: 13, color: foreground),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                '$label $value',
                softWrap: true,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: foreground,
                  fontFeatures: tabularFigures
                      ? const [FontFeature.tabularFigures()]
                      : null,
                ),
              ),
            ),
          ],
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
  final bool openAvatarSheetOnStart;

  const _AccountProfileEditor({this.openAvatarSheetOnStart = false});

  @override
  State<_AccountProfileEditor> createState() => _AccountProfileEditorState();
}

class _AccountProfileEditorState extends State<_AccountProfileEditor> {
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _displayNameCtrl;
  late final TextEditingController _avatarCtrl;
  late final TextEditingController _bioCtrl;
  late final int _originGeneration;
  late final String? _originUserId;
  late final bool _originIsLoggedIn;
  AuthProvider? _originAuth;
  late final UserProvider _originUserProvider;
  AuthSessionLease? _originSessionLease;
  AuthProvider? _authProvider;
  String? _lastAccountSnapshot;
  bool _syncingControllers = false;
  bool _hasLocalProfileEdits = false;
  bool _busy = false;
  bool _avatarBusy = false;
  _ProfileStateText? _error;
  _ProfileStateText? _message;
  _PendingProfileMirror? _pendingProfileMirror;

  bool get _canRetryLocalMirror => _pendingProfileMirror != null;

  @override
  void initState() {
    super.initState();
    I18n.localeListenable.addListener(_handleLocaleChanged);
    final auth = context.read<AuthProvider>();
    final state = auth.state;
    _originGeneration = AccountLocalDataCleaner.accountDataGeneration;
    _originUserId = state.userId;
    _originIsLoggedIn = state.isLoggedIn;
    _originAuth = auth;
    _originUserProvider = context.read<UserProvider>();
    try {
      _originSessionLease = state.isLoggedIn
          ? auth.captureSessionLease()
          : null;
    } catch (_) {
      _originSessionLease = null;
    }
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
    if (widget.openAvatarSheetOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _uploadAvatar();
      });
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
    I18n.localeListenable.removeListener(_handleLocaleChanged);
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

  void _handleLocaleChanged() {
    if (mounted) setState(() {});
  }

  bool _isCurrentEditorFlow() {
    if (!mounted) return false;
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
      _originGeneration,
    )) {
      return false;
    }
    final auth = _originAuth ?? context.read<AuthProvider>();
    if (!identical(context.read<AuthProvider>(), auth) ||
        !identical(context.read<UserProvider>(), _originUserProvider)) {
      return false;
    }
    if (auth.state.userId != _originUserId) return false;
    if (auth.state.isLoggedIn != _originIsLoggedIn) return false;
    if (_originSessionLease != null &&
        !auth.isSessionLeaseCurrent(_originSessionLease!)) {
      return false;
    }
    if (_originIsLoggedIn && _originSessionLease == null) return false;
    return true;
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
    final ownerRoute = ModalRoute.of(context);
    if (!_isCurrentEditorFlow()) {
      setState(
        () => _error = _ProfileStateText.error(AccountUiCopy.accountChanged),
      );
      return;
    }
    final auth = _originAuth ?? context.read<AuthProvider>();
    final userProvider = context.read<UserProvider>();

    setState(() {
      _avatarBusy = true;
      _error = null;
      _message = null;
    });
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          XTypeGroup(
            label: AccountUiCopy.imageFileTypeLabel,
            extensions: const ['jpg', 'jpeg', 'png', 'webp', 'gif'],
            mimeTypes: const [
              'image/jpeg',
              'image/png',
              'image/webp',
              'image/gif',
            ],
          ),
        ],
      );
      if (file == null || !_isCurrentEditorFlow()) return;
      final bytes = await file.readAsBytes();
      if (!_isCurrentEditorFlow()) return;
      if (bytes.isEmpty) {
        if (mounted) {
          setState(
            () => _error = const _ProfileStateText.key('profile.avatar.empty'),
          );
        }
        return;
      }
      if (bytes.length > 3 * 1024 * 1024) {
        if (mounted) {
          setState(
            () => _error = const _ProfileStateText.key(
              'profile.avatar.too_large',
            ),
          );
        }
        return;
      }
      await auth.uploadAvatarBytes(
        filename: file.name,
        bytes: bytes,
        sessionLease: _originSessionLease,
      );
      if (!_isCurrentEditorFlow()) return;
      final state = auth.state;
      _applyUploadedAvatar(state);
      await userProvider.updateProfile(
        username: _firstNonEmptyProfileText([
          state.username,
          _usernameCtrl.text,
          userProvider.profile.username,
        ]),
        displayName: state.displayName ?? '',
        email: state.email ?? '',
        emailVerified: state.emailVerified,
        avatarUrl: state.avatar ?? '',
        bio: state.bio ?? '',
      );
      if (!_isCurrentEditorFlow()) return;
      if (ownerRoute != null && !ownerRoute.isCurrent) return;
      setState(
        () => _message = const _ProfileStateText.copy(_feedbackAvatarSaved),
      );
    } on ApiException catch (e) {
      if (_isCurrentEditorFlow()) {
        setState(() => _error = _ProfileStateText.error(e));
      }
    } catch (e) {
      if (_isCurrentEditorFlow()) {
        setState(() => _error = _ProfileStateText.error(e));
      }
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  void _showAvatarPreview() {
    if (_busy || _avatarBusy) return;
    if (!_isCurrentEditorFlow()) {
      setState(
        () => _error = _ProfileStateText.error(AccountUiCopy.accountChanged),
      );
      return;
    }
    final authState = (_originAuth ?? context.read<AuthProvider>()).state;
    final displayName = _firstNonEmptyProfileText([
      _displayNameCtrl.text,
      _usernameCtrl.text,
      authState.displayName,
      authState.username,
    ]);
    final avatar = _avatarCtrl.text.trim().isEmpty
        ? authState.avatar
        : _avatarCtrl.text.trim();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ProfileAvatarFullScreen(
          avatar: avatar,
          displayName: displayName,
          cacheKey: _avatarCacheKey(avatar, authState.userId),
          onEdit: () {
            if (!_isCurrentEditorFlow()) return;
            _uploadAvatar();
          },
        ),
      ),
    );
  }

  Future<void> _showChangePasswordDialog() async {
    if (_busy || _avatarBusy) return;
    final ownerRoute = ModalRoute.of(context);
    if (!_isCurrentEditorFlow()) {
      setState(
        () => _error = _ProfileStateText.error(AccountUiCopy.accountChanged),
      );
      return;
    }
    final auth = _originAuth ?? context.read<AuthProvider>();
    final route = createControllerDialogRoute<bool>(
      context: context,
      builder: (_) => _ChangePasswordDialog(
        auth: auth,
        sessionLease: _originSessionLease,
        originGeneration: _originGeneration,
        originUserId: _originUserId,
      ),
    );
    final changed = await Navigator.of(
      context,
      rootNavigator: true,
    ).push<bool>(route);
    if (!mounted ||
        !_isCurrentEditorFlow() ||
        (ownerRoute != null && !ownerRoute.isCurrent) ||
        changed != true) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: _ProfileLocaleText('profile.password.updated')),
    );
  }

  Future<void> _showEmailBindingDialog() async {
    if (_busy || _avatarBusy) return;
    final ownerRoute = ModalRoute.of(context);
    if (!_isCurrentEditorFlow()) {
      setState(
        () => _error = _ProfileStateText.error(AccountUiCopy.accountChanged),
      );
      return;
    }
    final auth = _originAuth ?? context.read<AuthProvider>();
    final route = createControllerDialogRoute<bool>(
      context: context,
      builder: (_) => _EmailBindingDialog(
        initialEmail: auth.state.email ?? '',
        auth: auth,
        sessionLease: _originSessionLease,
        originGeneration: _originGeneration,
        originUserId: _originUserId,
      ),
    );
    final updated = await Navigator.of(
      context,
      rootNavigator: true,
    ).push<bool>(route);
    if (!mounted ||
        !_isCurrentEditorFlow() ||
        (ownerRoute != null && !ownerRoute.isCurrent) ||
        updated != true) {
      return;
    }
    final pending = _PendingProfileMirror(_ProfileMirrorReason.email);
    setState(() {
      _busy = true;
      _pendingProfileMirror = pending;
      _error = null;
      _message = null;
    });
    try {
      final state = auth.state;
      if (_hasLocalProfileEdits) {
        _lastAccountSnapshot = _accountProfileSnapshot(state);
        _refreshPreview();
      } else {
        _applyAccountState(state);
      }
      await _syncProfileMirror(pending, ownerRoute: ownerRoute);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _canPublishProfileFeedback(ModalRoute<dynamic>? ownerRoute) {
    return _isCurrentEditorFlow() &&
        (ownerRoute == null || ownerRoute.isCurrent);
  }

  void _showProfileMirrorFailure(_PendingProfileMirror pending) {
    final feedback = _ProfileMirrorFailureText(pending.reason);
    setState(() {
      _message = null;
      _error = feedback;
    });
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: ValueListenableBuilder<AppLocale>(
          valueListenable: I18n.localeListenable,
          builder: (context, _, _) {
            final theme = Theme.of(context);
            final cs = theme.colorScheme;
            final surfaceStyle = appSurfaceStyleOf(context);
            final snackBarBackground =
                theme.snackBarTheme.backgroundColor ??
                cs.surfaceContainerHighest;
            final foreground = surfaceStyle != null
                ? appReadableForeground(snackBarBackground, cs.primary)
                : cs.inversePrimary;
            return Row(
              children: [
                Expanded(child: Text(feedback.resolve())),
                TextButton(
                  onPressed: () {
                    if (!mounted ||
                        !identical(_pendingProfileMirror, pending) ||
                        !_canPublishProfileFeedback(
                          ModalRoute.of(this.context),
                        )) {
                      return;
                    }
                    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
                    _retryProfileMirrorSync();
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: foreground,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: surfaceStyle != null
                        ? const Size(48, 44)
                        : const Size(48, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: surfaceStyle != null
                        ? VisualDensity.standard
                        : null,
                  ),
                  child: Text(AccountUiCopy.actionRetry),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _syncProfileMirror(
    _PendingProfileMirror pending, {
    required ModalRoute<dynamic>? ownerRoute,
    bool recovery = false,
  }) async {
    if (!_canPublishProfileFeedback(ownerRoute) ||
        !identical(_pendingProfileMirror, pending)) {
      return;
    }
    final auth = _originAuth!;
    // Read confirmed account data immediately before enqueueing the local write.
    // A later avatar/email change must not be replaced with an old retry snapshot.
    final state = auth.state;
    try {
      await _originUserProvider.updateProfile(
        username: _firstNonEmptyProfileText([
          state.username,
          _originUserProvider.profile.username,
        ]),
        displayName: state.displayName ?? '',
        email: state.email ?? '',
        emailVerified: state.emailVerified,
        avatarUrl: state.avatar ?? '',
        bio: state.bio ?? '',
      );
      if (!mounted ||
          !_canPublishProfileFeedback(ownerRoute) ||
          !identical(_pendingProfileMirror, pending)) {
        return;
      }
      if (_accountProfileSnapshot(auth.state) !=
          _accountProfileSnapshot(state)) {
        _showProfileMirrorFailure(pending);
        return;
      }
      // Auth may have changed while a prior local retry kept the editor busy.
      // Bring a clean form up to date before a later Save can submit it again.
      if (!_hasLocalProfileEdits) _applyAccountState(state);
      setState(() {
        _pendingProfileMirror = null;
        _error = null;
        _message = recovery
            ? const _ProfileStateText.copy(_feedbackLocalSynced)
            : const _ProfileStateText.key('profile.updated');
      });
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: recovery
              ? ValueListenableBuilder<AppLocale>(
                  valueListenable: I18n.localeListenable,
                  builder: (context, _, _) =>
                      Text(AccountUiCopy.feedbackLocalSynced),
                )
              : const _ProfileLocaleText('profile.updated'),
        ),
      );
    } catch (_) {
      if (_canPublishProfileFeedback(ownerRoute) &&
          identical(_pendingProfileMirror, pending)) {
        _showProfileMirrorFailure(pending);
      }
    }
  }

  Future<void> _retryProfileMirrorSync() async {
    if (!mounted || _busy || _avatarBusy) return;
    final ownerRoute = ModalRoute.of(context);
    if (!_canPublishProfileFeedback(ownerRoute)) return;
    final pending = _pendingProfileMirror;
    if (pending == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      // Recovery only writes the original local provider, never the API or draft.
      await _syncProfileMirror(pending, ownerRoute: ownerRoute, recovery: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!mounted || _busy || _avatarBusy) return;
    final ownerRoute = ModalRoute.of(context);
    if (ownerRoute != null && !ownerRoute.isCurrent) return;
    if (!_isCurrentEditorFlow()) {
      setState(
        () => _error = _ProfileStateText.error(AccountUiCopy.accountChanged),
      );
      return;
    }
    if (_canRetryLocalMirror && !_hasLocalProfileEdits) {
      await _retryProfileMirrorSync();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final auth = _originAuth!;
      await auth.updateProfile(
        displayName: _displayNameCtrl.text.trim(),
        bio: _bioCtrl.text.trim(),
        sessionLease: _originSessionLease,
      );
      if (!_canPublishProfileFeedback(ownerRoute)) return;
      // Only normal completion confirms this operation, including Auth storage.
      final pending = _PendingProfileMirror(_ProfileMirrorReason.profile);
      _pendingProfileMirror = pending;
      _applyAccountState(auth.state);
      await _syncProfileMirror(pending, ownerRoute: ownerRoute);
    } catch (e) {
      if (_canPublishProfileFeedback(ownerRoute)) {
        setState(() => _error = _ProfileStateText.error(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _saveButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: SizedBox(
        width: _profileActionButtonWidth,
        height: _profileActionButtonHeight,
        child: FilledButton(
          onPressed: (_busy || _avatarBusy) ? null : _save,
          style: appSecondaryFilledButtonStyle(context),
          child: _busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(I18n.tr('action.save'), maxLines: 1),
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final account = context
        .select<
          AuthProvider,
          ({
            String? userId,
            String? username,
            String? email,
            bool emailVerified,
            String? displayName,
            String? avatar,
            int coinBalance,
          })
        >((auth) {
          final state = auth.state;
          return (
            userId: state.userId,
            username: state.username,
            email: state.email,
            emailVerified: state.emailVerified,
            displayName: state.displayName,
            avatar: state.avatar,
            coinBalance: state.coinBalance,
          );
        });
    final avatarFrame = context.select<ThemeProvider, AvatarFrameReward>(
      (provider) => provider.activeAvatarFrame,
    );
    final displayName = _firstNonEmptyProfileText([
      _displayNameCtrl.text,
      _usernameCtrl.text,
      account.displayName,
      account.username,
    ]);
    final previewAvatar = _avatarCtrl.text.trim().isEmpty
        ? account.avatar
        : _avatarCtrl.text.trim();
    final avatarCacheKey = _avatarCacheKey(previewAvatar, account.userId);
    final cs = Theme.of(context).colorScheme;
    final routeBackground = Colors.transparent;

    return Scaffold(
      backgroundColor: routeBackground,
      appBar: AppBar(
        title: Text(I18n.tr('profile.title')),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        actions: [_saveButton(context)],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          AppSurfaceCard(
            padding: const EdgeInsets.all(14),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final textScale = MediaQuery.textScalerOf(context).scale(1);
                final reflow = constraints.maxWidth < 320 && textScale > 1.25;
                final compact = constraints.maxWidth < 340;
                final avatarSize = compact ? 66.0 : 76.0;
                final avatar = _ProfileAvatarWithEdit(
                  size: avatarSize,
                  busy: _avatarBusy,
                  onPreview: _showAvatarPreview,
                  onEdit: _uploadAvatar,
                  child: Container(
                    width: avatarSize,
                    height: avatarSize,
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
                    child: Hero(
                      tag: 'profile-avatar-preview',
                      child: _ProfileAvatarPreview(
                        avatar: previewAvatar,
                        displayName: displayName,
                        radius: (avatarSize / 2) - 2,
                        cacheKey: avatarCacheKey,
                      ),
                    ),
                  ),
                );
                final infoColumn = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName.isEmpty
                          ? I18n.tr('profile.display_name.empty')
                          : displayName,
                      softWrap: true,
                      style: appSecondaryRouteTitleTextStyle(context),
                    ),
                    const SizedBox(height: 4),
                    Tooltip(
                      message: account.email?.trim().isNotEmpty == true
                          ? account.email!.trim()
                          : I18n.tr('profile.email.unbound'),
                      child: Text(
                        account.email?.isNotEmpty == true
                            ? '${account.email}${account.emailVerified ? ' · ${I18n.tr('profile.email.verified')}' : ' · ${I18n.tr('profile.email.unverified')}'}'
                            : I18n.tr('profile.email.unbound'),
                        softWrap: true,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.62),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        const AccountStatusChip(
                          status: AccountDisplayStatus.loggedIn,
                        ),
                        _ProfileMetricChip(
                          icon: Icons.savings_outlined,
                          label: I18n.tr('profile.coins'),
                          value: '${account.coinBalance}',
                          tabularFigures: true,
                        ),
                        if (account.username?.trim().isNotEmpty == true)
                          _ProfileMetricChip(
                            icon: Icons.badge_outlined,
                            label: I18n.tr('profile.account_id'),
                            value: account.username!.trim(),
                          ),
                      ],
                    ),
                  ],
                );
                if (reflow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [avatar, const SizedBox(height: 12), infoColumn],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    avatar,
                    SizedBox(width: compact ? 10 : 14),
                    Expanded(child: infoColumn),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          AppSecondaryControlTheme(
            child: AppSurfaceCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  TextField(
                    controller: _displayNameCtrl,
                    enabled: !_busy && !_avatarBusy,
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
                      helperMaxLines: 4,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          AppSecondaryControlTheme(
            child: AppSurfaceCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ProfileSectionHeader(
                    icon: Icons.alternate_email_outlined,
                    title: I18n.tr('profile.email.binding'),
                    subtitle: account.emailVerified
                        ? I18n.tr('profile.email.verified')
                        : I18n.tr('profile.email.unverified_or_pending'),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    account.email?.trim().isEmpty != false
                        ? I18n.tr('profile.email.unbound')
                        : account.email!.trim(),
                    softWrap: true,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: cs.onSurface),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        SizedBox(
                          height: _profileActionButtonHeight,
                          child: TextButton.icon(
                            onPressed: (_busy || _avatarBusy)
                                ? null
                                : _showEmailBindingDialog,
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              textStyle: appSecondaryControlTextStyle(context),
                            ),
                            icon: const Icon(Icons.edit_outlined, size: 16),
                            label: Text(I18n.tr('profile.email.binding')),
                          ),
                        ),
                        if (_pendingProfileMirror?.reason ==
                            _ProfileMirrorReason.email)
                          SizedBox(
                            height: _profileActionButtonHeight,
                            child: TextButton.icon(
                              onPressed: (_busy || _avatarBusy)
                                  ? null
                                  : _retryProfileMirrorSync,
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                textStyle: appSecondaryControlTextStyle(
                                  context,
                                ),
                              ),
                              icon: _busy
                                  ? const SizedBox.square(
                                      dimension: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.refresh, size: 16),
                              label: const _ProfileLocaleText('action.retry'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          AppSurfaceCard(
            padding: const EdgeInsets.all(14),
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
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: _profileActionButtonHeight,
                    ),
                    child: TextButton.icon(
                      onPressed: (_busy || _avatarBusy)
                          ? null
                          : _showChangePasswordDialog,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        textStyle: appSecondaryControlTextStyle(context),
                      ),
                      icon: const Icon(Icons.lock_reset_outlined, size: 16),
                      label: Text(
                        I18n.tr('profile.change_password'),
                        softWrap: true,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                AppSecondaryControlTheme(
                  child: TextField(
                    controller: _bioCtrl,
                    enabled: !_busy && !_avatarBusy,
                    minLines: 3,
                    maxLines: 6,
                    decoration: InputDecoration(
                      labelText: I18n.tr('profile.bio'),
                    ),
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
              message: _message!.resolve(),
              color: DesignTokens.defaultSuccess,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            AppInfoBanner(
              icon: Icons.error_outline,
              title: _error is _ProfileMirrorFailureText
                  ? AccountUiCopy.localProfileSyncPendingTitle
                  : I18n.tr('profile.save_failed'),
              message: _error!.resolve(),
              color: _error is _ProfileMirrorFailureText
                  ? cs.tertiary
                  : cs.error,
            ),
            if (_canRetryLocalMirror) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  height: _profileActionButtonHeight,
                  child: OutlinedButton.icon(
                    onPressed: (_busy || _avatarBusy)
                        ? null
                        : _retryProfileMirrorSync,
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 2,
                      ),
                      textStyle: appSecondaryControlTextStyle(context),
                    ),
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, size: 16),
                    label: const _ProfileLocaleText('action.retry'),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _LocalProfileEditor extends StatefulWidget {
  final bool openAvatarSheetOnStart;

  const _LocalProfileEditor({this.openAvatarSheetOnStart = false});

  @override
  State<_LocalProfileEditor> createState() => _LocalProfileEditorState();
}

class _LocalProfileEditorState extends State<_LocalProfileEditor> {
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _displayNameCtrl;
  late final TextEditingController _avatarCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _bioCtrl;
  late final int _originGeneration;
  late final bool _originIsLoggedIn;
  late final String? _originUserId;
  bool _busy = false;
  bool _avatarBusy = false;
  _ProfileStateText? _error;
  _ProfileStateText? _message;

  @override
  void initState() {
    super.initState();
    I18n.localeListenable.addListener(_handleLocaleChanged);
    final auth = context.read<AuthProvider>();
    _originGeneration = AccountLocalDataCleaner.accountDataGeneration;
    _originIsLoggedIn = auth.state.isLoggedIn;
    _originUserId = auth.state.userId;
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
    if (widget.openAvatarSheetOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pickLocalAvatar();
      });
    }
  }

  @override
  void dispose() {
    I18n.localeListenable.removeListener(_handleLocaleChanged);
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

  void _handleLocaleChanged() {
    if (mounted) setState(() {});
  }

  bool _isCurrentLocalFlow() {
    if (!mounted) return false;
    if (!AccountLocalDataCleaner.isCurrentAccountDataGeneration(
      _originGeneration,
    )) {
      return false;
    }
    final auth = context.read<AuthProvider>();
    if (auth.state.isLoggedIn != _originIsLoggedIn) return false;
    if (auth.state.userId != _originUserId) return false;
    return true;
  }

  void _refreshPreview() {
    if (mounted) setState(() {});
  }

  Future<void> _pickLocalAvatar() async {
    if (_busy || _avatarBusy) return;
    final ownerRoute = ModalRoute.of(context);
    if (!_isCurrentLocalFlow()) {
      setState(
        () => _error = _ProfileStateText.error(AccountUiCopy.accountChanged),
      );
      return;
    }
    setState(() {
      _avatarBusy = true;
      _error = null;
      _message = null;
    });
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          XTypeGroup(
            label: AccountUiCopy.imageFileTypeLabel,
            extensions: const ['jpg', 'jpeg', 'png', 'webp', 'gif'],
            mimeTypes: const [
              'image/jpeg',
              'image/png',
              'image/webp',
              'image/gif',
            ],
          ),
        ],
      );
      if (file == null || !_isCurrentLocalFlow()) return;
      final storedPath = await _copyLocalAvatarFile(file);
      if (!_isCurrentLocalFlow()) return;
      setState(() {
        _avatarCtrl.text = storedPath;
      });
      final saved = await _save(showSnackBar: false, fromAvatarPicker: true);
      if (!saved ||
          !_isCurrentLocalFlow() ||
          (ownerRoute != null && !ownerRoute.isCurrent)) {
        return;
      }
      setState(
        () => _message = const _ProfileStateText.key('profile.avatar.saved'),
      );
    } catch (e) {
      if (_isCurrentLocalFlow()) {
        setState(() => _error = _ProfileStateText.error(e));
      }
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  void _showAvatarPreview() {
    if (_busy || _avatarBusy) return;
    if (!_isCurrentLocalFlow()) {
      setState(
        () => _error = _ProfileStateText.error(AccountUiCopy.accountChanged),
      );
      return;
    }
    final displayName = _firstNonEmptyProfileText([
      _displayNameCtrl.text,
      _usernameCtrl.text,
    ]);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ProfileAvatarFullScreen(
          avatar: _avatarCtrl.text.trim(),
          displayName: displayName,
          cacheKey: _avatarCacheKey(_avatarCtrl.text.trim(), null),
          onEdit: () {
            if (!_isCurrentLocalFlow()) return;
            _pickLocalAvatar();
          },
        ),
      ),
    );
  }

  Future<bool> _save({
    bool showSnackBar = true,
    bool fromAvatarPicker = false,
  }) async {
    if (_busy || (!fromAvatarPicker && _avatarBusy)) return false;
    final ownerRoute = ModalRoute.of(context);
    if (!mounted || (ownerRoute != null && !ownerRoute.isCurrent)) return false;
    if (!_isCurrentLocalFlow()) {
      setState(
        () => _error = _ProfileStateText.error(AccountUiCopy.accountChanged),
      );
      return false;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    final currentProfile = context.read<UserProvider>().profile;
    final username = currentProfile.username.trim().isNotEmpty
        ? currentProfile.username.trim()
        : _usernameCtrl.text.trim();
    if (username.isEmpty) {
      setState(
        () => _error = const _ProfileStateText.key(
          'profile.error.nickname_required',
        ),
      );
      return false;
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
      if (!mounted ||
          !_isCurrentLocalFlow() ||
          (ownerRoute != null && !ownerRoute.isCurrent)) {
        return false;
      }
      setState(
        () => _message = const _ProfileStateText.key('profile.local.updated'),
      );
      if (showSnackBar) {
        messenger?.showSnackBar(
          const SnackBar(content: _ProfileLocaleText('profile.local.updated')),
        );
      }
      return true;
    } catch (e) {
      if (_isCurrentLocalFlow()) {
        setState(() => _error = _ProfileStateText.error(e));
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _saveButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: SizedBox(
        width: _profileActionButtonWidth,
        height: _profileActionButtonHeight,
        child: FilledButton(
          onPressed: _busy || _avatarBusy ? null : _save,
          style: appSecondaryFilledButtonStyle(context),
          child: _busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(I18n.tr('action.save'), maxLines: 1),
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final realDisplayName = _firstNonEmptyProfileText([
      _displayNameCtrl.text,
      _usernameCtrl.text,
    ]);
    final displayName = _firstNonEmptyProfileText([
      _displayNameCtrl.text,
      _usernameCtrl.text,
      I18n.tr('profile.default_user'),
    ]);
    final previewAvatar = _avatarCtrl.text.trim();
    final avatarCacheKey = _avatarCacheKey(previewAvatar, null);
    final emailText = _emailCtrl.text.trim();
    final bioText = _bioCtrl.text.trim();
    final localHint = AccountUiCopy.profileLocalHint;
    final bioOrHint = bioText.isNotEmpty
        ? bioText
        : (emailText.isEmpty ? localHint : '');
    final cs = Theme.of(context).colorScheme;
    final routeBackground = Colors.transparent;

    return Scaffold(
      backgroundColor: routeBackground,
      appBar: AppBar(
        title: Text(I18n.tr('profile.title')),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        actions: [_saveButton(context)],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          AppSurfaceCard(
            padding: const EdgeInsets.all(14),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final textScale = MediaQuery.textScalerOf(context).scale(1);
                final reflow = constraints.maxWidth < 320 && textScale > 1.25;
                final compact = constraints.maxWidth < 330;
                final avatarSize = compact ? 68.0 : 76.0;
                final avatar = _ProfileAvatarWithEdit(
                  size: avatarSize,
                  busy: _avatarBusy,
                  onPreview: _showAvatarPreview,
                  onEdit: _pickLocalAvatar,
                  child: Hero(
                    tag: 'profile-avatar-preview',
                    child: _ProfileAvatarPreview(
                      avatar: previewAvatar,
                      displayName: realDisplayName,
                      radius: avatarSize / 2 - 2,
                      cacheKey: avatarCacheKey,
                    ),
                  ),
                );
                final loginButton = SizedBox(
                  width: compact ? 82 : _profileInlineActionWidth(context),
                  height: _profileActionButtonHeight,
                  child: TextButton(
                    key: const ValueKey('profile_local_login_button'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      textStyle: appSecondaryControlTextStyle(context),
                    ),
                    onPressed: () => Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginScreen()),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        I18n.tr('profile.login_account'),
                        maxLines: 1,
                      ),
                    ),
                  ),
                );
                final textColumn = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (reflow || compact) ...[
                      Text(
                        displayName,
                        softWrap: true,
                        style: appSecondaryRouteTitleTextStyle(context),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: loginButton,
                      ),
                    ] else
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              displayName,
                              softWrap: true,
                              style: appSecondaryRouteTitleTextStyle(context),
                            ),
                          ),
                          const SizedBox(width: 8),
                          loginButton,
                        ],
                      ),
                    if (emailText.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        emailText,
                        softWrap: true,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.62),
                          height: 1.25,
                        ),
                      ),
                    ],
                    if (bioOrHint.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        bioOrHint,
                        softWrap: true,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.62),
                          height: 1.25,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    const AccountStatusChip(
                      status: AccountDisplayStatus.localOnly,
                      wrapLabel: true,
                    ),
                  ],
                );
                if (reflow) {
                  return Column(
                    key: const ValueKey('profile_local_header_row'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      avatar,
                      const SizedBox(height: 12),
                      textColumn,
                    ],
                  );
                }
                return Row(
                  key: const ValueKey('profile_local_header_row'),
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    avatar,
                    SizedBox(width: compact ? 10 : 14),
                    Expanded(child: textColumn),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          AppSecondaryControlTheme(
            child: AppSurfaceCard(
              padding: const EdgeInsets.all(14),
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
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: I18n.tr('profile.local_nickname'),
                      helperText: I18n.tr('profile.username.locked'),
                      helperMaxLines: 4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ExcludeSemantics(
                        child: Text(
                          I18n.tr('profile.email.local_display'),
                          softWrap: true,
                          style: appSecondaryControlLabelStyle(context).copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Semantics(
                        label: I18n.tr('profile.email.local_display'),
                        child: TextField(
                          key: const ValueKey('profile_local_email_field'),
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(),
                        ),
                      ),
                    ],
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
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            AppInfoBanner(
              icon: Icons.error_outline,
              title: I18n.tr('profile.save_failed'),
              message: _error!.resolve(),
              color: Theme.of(context).colorScheme.error,
            ),
          ],
          if (_message != null) ...[
            const SizedBox(height: 12),
            AppInfoBanner(
              icon: Icons.check_circle_outline,
              title: I18n.tr('profile.saved'),
              message: _message!.resolve(),
              color: DesignTokens.defaultSuccess,
            ),
          ],
        ],
      ),
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
  return _networkAvatarUrl(value) != null;
}

bool _looksLikeEmail(String value) {
  return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim());
}

String? _localAvatarPath(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  if (_networkAvatarUrl(trimmed) != null) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri != null && uri.scheme == 'file') {
    return uri.toFilePath();
  }
  if (trimmed.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(trimmed)) {
    return trimmed;
  }
  return null;
}

String? _networkAvatarUrl(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
    return trimmed;
  }
  final pathSegments = Uri.tryParse(trimmed)?.pathSegments ?? const <String>[];
  if (pathSegments.isNotEmpty &&
      (pathSegments.first == 'api' || pathSegments.first == 'uploads')) {
    final base = Uri.base;
    if (base.scheme == 'http' || base.scheme == 'https') {
      return base.resolve(trimmed).toString();
    }
    return trimmed;
  }
  return null;
}

String _avatarCacheKey(String? avatarUrl, String? userId) {
  return '${userId ?? ''}|${avatarUrl?.trim() ?? ''}';
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
