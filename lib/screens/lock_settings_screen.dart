import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import '../core/settings_ui_copy.dart';
import '../providers/app_lock_provider.dart';
import '../widgets/settings_picker_tile.dart';
import '../widgets/surface_components.dart';

class LockSettingsScreen extends StatefulWidget {
  const LockSettingsScreen({super.key});

  @override
  State<LockSettingsScreen> createState() => _LockSettingsScreenState();
}

class _LockSettingsScreenState extends State<LockSettingsScreen> {
  bool _isPinFlowInFlight = false;

  @override
  void initState() {
    super.initState();
    I18n.localeListenable.addListener(_onLocaleChanged);
  }

  @override
  void dispose() {
    I18n.localeListenable.removeListener(_onLocaleChanged);
    super.dispose();
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _setPinFlow() async {
    if (_isPinFlowInFlight) return;
    _isPinFlowInFlight = true;
    try {
      final messenger = ScaffoldMessenger.of(context);
      final lock = context.read<AppLockProvider>();
      final pin = await _askPin('app_lock.dialog.set_pin');
      if (pin == null || !mounted) return;
      final confirm = await _askPin('app_lock.dialog.confirm_pin');
      if (confirm == null || !mounted) return;
      if (pin != confirm) {
        messenger.showSnackBar(
          SnackBar(content: Text(I18n.tr('app_lock.pin_mismatch'))),
        );
        return;
      }
      final ok = await lock.setPin(pin);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? I18n.tr('app_lock.enabled_message')
                : I18n.tr('app_lock.pin_invalid'),
          ),
        ),
      );
    } finally {
      _isPinFlowInFlight = false;
    }
  }

  Future<void> _disableFlow() async {
    if (_isPinFlowInFlight) return;
    _isPinFlowInFlight = true;
    try {
      final messenger = ScaffoldMessenger.of(context);
      final lock = context.read<AppLockProvider>();
      final pin = await _askPin('app_lock.dialog.disable_pin');
      if (pin == null || !mounted) return;
      final ok = await lock.verify(pin);
      if (!mounted) return;
      if (!ok) {
        messenger.showSnackBar(
          SnackBar(content: Text(I18n.tr('app_lock.pin_wrong'))),
        );
        return;
      }
      await lock.disable(pin);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(I18n.tr('app_lock.disabled_message'))),
      );
    } finally {
      _isPinFlowInFlight = false;
    }
  }

  Future<String?> _askPin(String titleKey) async {
    if (!mounted) return null;
    final v = await showDialog<String>(
      context: context,
      builder: (_) => _PinInputDialog(titleKey: titleKey),
    );
    if (v == null) return null;
    if (!RegExp(r'^\d{4,8}$').hasMatch(v)) {
      if (!mounted) return null;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(I18n.tr('app_lock.pin_invalid'))));
      return null;
    }
    return v;
  }

  @override
  Widget build(BuildContext context) {
    final lock = context.watch<AppLockProvider>();
    final cs = Theme.of(context).colorScheme;
    final routeBackground = Theme.of(context).brightness == Brightness.dark
        ? cs.surface
        : cs.surfaceContainerLowest;

    return Scaffold(
      backgroundColor: routeBackground,
      appBar: AppBar(
        title: Text(I18n.tr('app_lock.title')),
        titleTextStyle: appSecondaryRouteTitleTextStyle(context),
        backgroundColor: routeBackground.withValues(alpha: 0.96),
        surfaceTintColor: Colors.transparent,
      ),
      body: AppSecondaryControlTheme(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
          children: [
            AppSurfaceCard(
              padding: const EdgeInsets.all(16),
              gradient: LinearGradient(
                colors: [cs.primary.withValues(alpha: 0.12), cs.surface],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.lock_outline,
                      color: cs.primary,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          I18n.tr('app_lock.hero.title'),
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.normal,
                                color: cs.onSurface,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          I18n.tr('app_lock.hero.subtitle'),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: cs.onSurface.withValues(alpha: 0.66),
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            AppSettingsSection(
              title: I18n.tr('app_lock.section.status'),
              subtitle: I18n.tr('app_lock.section.status.subtitle'),
              children: [
                AppSwitchTile(
                  icon: lock.enabled ? Icons.lock : Icons.lock_open,
                  color: lock.enabled ? Colors.green : Colors.orange,
                  title: I18n.tr('app_lock.enable'),
                  subtitle: lock.enabled
                      ? I18n.tr('app_lock.enabled')
                      : I18n.tr('app_lock.disabled.subtitle'),
                  value: lock.enabled,
                  onChanged: (enabled) =>
                      enabled ? _setPinFlow() : _disableFlow(),
                ),
                if (lock.enabled) ...[
                  AppSettingsTile(
                    icon: Icons.password,
                    color: cs.primary,
                    title: I18n.tr('app_lock.change_pin'),
                    subtitle: I18n.tr('app_lock.change_pin.subtitle'),
                    onTap: _setPinFlow,
                  ),
                  SettingsPickerTile<int>(
                    icon: Icons.timer_outlined,
                    color: Colors.orange,
                    titleBuilder: () => I18n.tr('app_lock.auto_lock'),
                    subtitleBuilder: () =>
                        SettingsUiCopy.autoLockSubtitle(lock.autoLockMinutes),
                    pickerTitleBuilder: () => SettingsUiCopy.selectAutoLock,
                    currentValue: lock.autoLockMinutes,
                    displayLabelBuilder: () =>
                        SettingsUiCopy.autoLockOptionLabel(
                          lock.autoLockMinutes,
                        ),
                    optionsBuilder: () => [
                      for (final m in SettingsUiCopy.autoLockMinuteOptions)
                        SettingsPickerOption<int>(
                          value: m,
                          title: SettingsUiCopy.autoLockOptionLabel(m),
                          subtitle: m == 0
                              ? I18n.tr('app_lock.auto_lock.every_foreground')
                              : '${I18n.tr('app_lock.auto_lock.after_prefix')}$m${I18n.tr('app_lock.auto_lock.after_suffix')}',
                        ),
                    ],
                    onSelected: (v) {
                      context.read<AppLockProvider>().setAutoLockMinutes(v);
                    },
                  ),
                  AppSettingsTile(
                    icon: Icons.lock_clock_outlined,
                    color: Colors.red,
                    title: I18n.tr('app_lock.lock_now'),
                    subtitle: I18n.tr('app_lock.lock_now.subtitle'),
                    onTap: () {
                      context.read<AppLockProvider>().lock();
                      Navigator.pop(context);
                    },
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            AppSurfaceCard(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: cs.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      I18n.tr('app_lock.tip'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.68),
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dedicated dialog widget that manages its own TextEditingController lifetime.
///
/// Disposes the controller only when unmounted (after route transition finishes),
/// and dynamically rebuilds when [I18n.localeListenable] changes without losing input.
class _PinInputDialog extends StatefulWidget {
  final String titleKey;

  const _PinInputDialog({required this.titleKey});

  @override
  State<_PinInputDialog> createState() => _PinInputDialogState();
}

class _PinInputDialogState extends State<_PinInputDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    I18n.localeListenable.addListener(_onLocaleChanged);
  }

  @override
  void dispose() {
    I18n.localeListenable.removeListener(_onLocaleChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: Text(I18n.tr(widget.titleKey)),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        obscureText: true,
        maxLength: 8,
        decoration: InputDecoration(
          hintText: I18n.tr('app_lock.pin_hint'),
          counterText: '',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(I18n.tr('action.cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(I18n.tr('action.confirm')),
        ),
      ],
    );
  }
}
