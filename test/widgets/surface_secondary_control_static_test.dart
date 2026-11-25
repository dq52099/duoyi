import 'dart:io';

import 'package:flutter/material.dart';
import 'package:test/test.dart';

void main() {
  test('共享二级控件样式和主菜单字号字重一致', () {
    final source = _readSource('lib/widgets/surface_components.dart');

    final controlStyle = source.substring(
      source.indexOf('TextStyle appSecondaryControlTextStyle'),
      source.indexOf('TextStyle appSecondaryControlLabelStyle'),
    );
    final labelStyle = source.substring(
      source.indexOf('TextStyle appSecondaryControlLabelStyle'),
      source.indexOf('TextStyle appSecondaryMenuItemTextStyle'),
    );
    expect(controlStyle, contains('fontSize: 12'));
    expect(controlStyle, isNot(contains('fontSize: 11,')));
    expect(labelStyle, contains('fontSize: 11'));
    expect(labelStyle, isNot(contains('fontSize: 10')));
    expect(source, contains('TextStyle appSecondaryMenuItemTextStyle'));
    final menuStyle = source.substring(
      source.indexOf('TextStyle appSecondaryMenuItemTextStyle'),
      source.indexOf('Color _appSecondaryActionBackground'),
    );
    expect(menuStyle, contains('fontSize: 12'));
    expect(menuStyle, isNot(contains('fontSize: 11,')));
    expect(source, isNot(contains('fontSize: 13.5')));
    expect(source, contains('fontWeight: FontWeight.normal'));
    expect(source, contains('class AppSecondaryControlTheme'));
    expect(source, contains('class AppSecondaryMenuText'));
    expect(source, contains('class AppPickerSheet'));
    expect(source, contains('child: Builder('));
    expect(source, contains('Widget _optionTile('));
    expect(source, contains('contentPadding: const EdgeInsets.symmetric('));
    expect(source, contains('appSecondaryControlTextStyle('));
    expect(source, contains('appSecondaryControlLabelStyle(context)'));
    expect(source, contains('cs.outlineVariant.withValues(alpha: 0.12)'));
    expect(source, contains('Navigator.pop<T>(context, option.value)'));
    expect(
      source,
      contains('child: AppSecondaryControlTheme(child: content!)'),
    );
    expect(source, contains('AppSecondaryControlTheme(child: child)'));
    expect(source, contains('inputDecorationTheme'));
    expect(source, contains('OutlineInputBorder inputBorder'));
    expect(
      source,
      contains('prefixIconConstraints: const BoxConstraints.tightFor('),
    );
    expect(
      source,
      contains('suffixIconConstraints: const BoxConstraints.tightFor('),
    );
    expect(source, contains('enabledBorder: inputBorder(subtleBorder)'));
    expect(source, contains('focusedBorder: inputBorder('));
    expect(source, contains('width: 0.45'));
    expect(source, contains('width: 0.45'));
    expect(source, contains('listTileTheme'));
    expect(source, contains('dropdownMenuTheme'));
    expect(source, contains('popupMenuTheme'));
    expect(source, contains('textButtonTheme'));
    expect(source, contains('elevatedButtonTheme'));
    expect(source, contains('outlinedButtonTheme'));
    expect(source, contains('OutlinedButtonThemeData'));
    expect(source, contains('filledButtonTheme'));
    expect(source, contains('ButtonStyle appSecondaryFilledButtonStyle'));
    expect(
      source,
      contains('style: appSecondaryFilledButtonStyle(\n            context,'),
    );
    expect(
      source,
      contains('copyWith(textStyle: WidgetStatePropertyAll(controlText))'),
    );
    expect(source, contains('minimumSize: const Size(0, 34)'));
    expect(source, contains('OutlinedButton.styleFrom('));
    expect(source, isNot(contains('minimumSize: const Size(0, 40)')));
    expect(source, contains('segmentedButtonTheme'));
    expect(source, contains('SegmentedButtonThemeData'));
    expect(source, contains('WidgetState.selected'));
    expect(source, contains('Color _appReadableForeground'));
    expect(
      source,
      contains('return _appReadableForeground(background, Colors.white);'),
    );
    expect(source, contains('double _appContrastRatio'));
    expect(source, contains('final selectedControlBackground'));
    expect(
      source,
      contains('cs.primary.withValues(alpha: isDark ? 0.14 : 0.09)'),
    );
    expect(source, contains('final selectedControlRenderedBackground'));
    expect(source, contains('Color.alphaBlend('));
    expect(source, contains('final selectedControlForeground'));
    expect(source, contains('final selectedControlIcon'));
    expect(source, contains('_appReadableForeground('));
    expect(
      source,
      contains('if (appContrastRatio(background, effectivePreferred) >= 4.5)'),
    );
    expect(source, contains('return selectedControlForeground;'));
    expect(
      source,
      contains('cs.primary.withValues(alpha: isDark ? 0.34 : 0.30)'),
    );
    expect(source, contains('titleSmall: controlText.copyWith'));
    expect(source, contains('bodySmall: labelText.copyWith'));
    expect(source, contains('chipTheme'));
    expect(source, contains('secondaryLabelStyle: labelText.copyWith('));
    expect(source, contains('color: selectedControlForeground'));
    expect(source, contains('selectedColor: selectedControlBackground'));
    expect(source, contains('checkmarkColor: selectedControlIcon'));
    expect(
      source,
      contains('IconThemeData(size: 16, color: selectedControlIcon)'),
    );
    expect(source, contains('style: appSecondaryControlTextStyle('));
    expect(source, contains('final labelText = appSecondaryControlLabelStyle'));
    expect(source, contains('labelStyle: labelText.copyWith'));
    expect(source, contains('style: appSecondaryMenuItemTextStyle('));
    expect(source, contains(').copyWith(color: cs.onSurface'));
    expect(source, contains('final ValueChanged<T?>? onChanged'));
    expect(source, contains('isDense: true'));
    expect(source, contains('FormField<T>('));
    expect(source, contains("import 'package:flutter/services.dart';"));
    expect(source, contains('SystemChannels.textInput.invokeMethod<void>'));
    expect(source, contains("'TextInput.hide'"));
    expect(source, contains('Future<void> _hideKeyboardBeforePicker'));
    expect(source, contains('Future<T?> _showAnchoredDropdownMenu<T>'));
    expect(source, contains('context.findRenderObject() as RenderBox?'));
    expect(source, contains('Navigator.of(context).overlay'));
    expect(source, contains('RelativeRect.fromLTRB('));
    expect(source, contains('final unclampedTop = openAbove'));
    expect(source, contains('final maxTop = (safeBottom - availableHeight)'));
    expect(
      source,
      contains(
        'final menuBottom = (activeOverlay.size.height - menuTop - availableHeight)',
      ),
    );
    expect(source, contains('final menuLeft = fieldTopLeft.dx.clamp'));
    expect(
      source,
      contains(
        'final menuRight = (activeOverlay.size.width - fieldBottomRight.dx).clamp',
      ),
    );
    expect(source, contains('final picked = await showMenu<T>('));
    expect(
      source,
      contains(
        'positionBuilder: (_, constraints) => positionForCurrentLayout()',
      ),
    );
    expect(source, contains('constraints: BoxConstraints('));
    expect(source, contains('minWidth: menuWidth'));
    expect(source, contains('_AnchoredDropdownMenuItem<T>('));
    expect(source, contains('await selectedMenuRoute?.completed'));
    expect(
      source,
      contains('FocusScope.of(context, createDependency: false).unfocus()'),
    );
    expect(source, contains('await Future<void>.delayed('));
    expect(source, contains('const Duration(milliseconds: 32)'));
    expect(source, contains('Future<void> _waitForDropdownInsetsToSettle'));
    expect(source, contains('for (var i = 0; i < 18; i += 1)'));
    expect(source, contains('closedStableFrames >= 3'));
    expect(source, contains('unchangedFrames >= 4'));
    expect(source, contains('await WidgetsBinding.instance.endOfFrame'));
    expect(source, contains('await _waitForDropdownInsetsToSettle(context)'));
    expect(source, contains('await Scrollable.ensureVisible('));
    expect(
      source,
      contains('bool _dropdownAnchorIsVisible(BuildContext context)'),
    );
    expect(source, contains('if (!_dropdownAnchorIsVisible(context))'));
    expect(
      source,
      contains(
        'alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart',
      ),
    );
    expect(source, contains('MediaQuery.maybeOf(context)?.viewInsets.bottom'));
    expect(source, contains('View.maybeOf(context)'));
    expect(source, contains('view.viewInsets.bottom / view.devicePixelRatio'));
    expect(source, contains('double _effectiveDropdownBottomInset'));
    expect(
      source,
      contains('Future<void> _waitForDropdownAnchorLayoutToSettle'),
    );
    expect(source, contains('final hadKeyboard'));
    expect(source, contains('if (hadKeyboard)'));
    expect(
      source,
      contains(
        'final safeBottom = (activeOverlay.size.height - bottomInset - 8)',
      ),
    );
    expect(
      source,
      contains(
        'final bottomInset = shiftForKeyboard\n        ? _effectiveDropdownBottomInset(context)\n        : 0.0;',
      ),
    );
    expect(
      source,
      contains('final openAbove = belowSpace < 160 && aboveSpace > belowSpace'),
    );
    expect(source, contains('maxHeight: availableHeight'));
    expect(source, contains('maxHeight: initialPosition.height'));
    expect(source, contains('class _DropdownMenuPosition'));
    expect(source, contains('height: availableHeight'));
    expect(source, contains('const Duration(milliseconds: 180)'));
    expect(source, contains('for (var i = 0; i < 14; i += 1)'));
    expect(source, contains('requestFocus: false'));
    expect(
      source,
      isNot(contains('activeOverlay.size.height - menuTop,\n    );')),
    );
    expect(source, isNot(contains('const Duration(milliseconds: 120)')));
    expect(source, contains('requestFocus: false'));
    final dropdownMenu = source.substring(
      source.indexOf('Future<T?> _showAnchoredDropdownMenu<T>'),
      source.indexOf('class AppCompactDropdown<T>'),
    );
    expect(
      dropdownMenu,
      isNot(contains('requestFocus: shiftForKeyboard ? null : false')),
    );
    expect(source, contains('_showAnchoredDropdownMenu<T>('));
    expect(source, contains('field.didChange(picked)'));
    expect(source, contains('class AppCompactDropdown<T>'));
    expect(source, contains('builder: (anchorContext)'));
    expect(
      source,
      contains('onTap: enabled ? () => _openPicker(anchorContext) : null'),
    );
    expect(source, contains('onTapDown: enabled'));
    expect(
      source,
      contains(
        'onTap: canOpen\n                    ? () => _openPicker(anchorContext, field, inputDecoration)',
      ),
    );
    expect(source, contains('onTapDown: canOpen'));
    expect(source, contains('_beginDropdownKeyboardDismiss(anchorContext)'));
    expect(
      source,
      contains('final picked = await _showAnchoredDropdownMenu<T>('),
    );
    expect(source, contains('FocusManager.instance.primaryFocus?.unfocus()'));
    expect(source, isNot(contains('DropdownButtonHideUnderline')));
    expect(source, isNot(contains('DropdownButton(')));
    expect(source, isNot(contains('DropdownButton<')));
    expect(source, isNot(contains('DropdownButton<T>')));
    expect(source, isNot(contains('DropdownButtonFormField(')));
    expect(source, isNot(contains('DropdownButtonFormField<')));
    expect(source, isNot(contains('FontWeight.bold')));
    expect(source, isNot(contains('FontWeight.w700')));
  });

  test('危险按钮和状态徽标显式使用高对比前景色', () {
    final surface = _readSource('lib/widgets/surface_components.dart');
    final notification = File(
      'lib/screens/notification_history_screen.dart',
    ).readAsStringSync();
    final admin = File('lib/screens/admin_screen.dart').readAsStringSync();
    final backup = File('lib/screens/backup_screen.dart').readAsStringSync();

    expect(surface, contains('final fg = _appReadableForeground('));
    for (final source in [notification, admin, backup]) {
      expect(source, isNot(contains('backgroundColor: Colors.red')));
      expect(source, contains('colorScheme.error'));
      expect(source, contains('colorScheme.onError'));
    }
  });

  test('共享卡片、弹框和底部面板有样式回归护栏', () {
    final source = _readSource('lib/widgets/surface_components.dart');
    final dialogStart = source.indexOf('class AppDialog extends StatelessWidget {');
    expect(dialogStart, isNonNegative);
    final sheetStart = source.indexOf('class AppModalSheet extends StatelessWidget {');
    expect(sheetStart, greaterThan(dialogStart));
    final pickerStart = source.indexOf('class AppPickerOption<T>', sheetStart);
    expect(pickerStart, greaterThan(sheetStart));
    final dialogSource = source.substring(dialogStart, sheetStart);
    final dialogTokens = dialogSource.replaceAll(RegExp(r'\s+'), '');
    final sheetSource = source.substring(sheetStart, pickerStart);

    expect(source, contains('class AppSurfaceCard'));
    expect(source, contains('border ??'));
    expect(source, contains('Border.all('));
    expect(source, contains('width: 0.45'));
    expect(dialogSource, contains('class AppDialog'));
    expect(dialogSource, contains('final bool shiftForKeyboard'));
    expect(dialogSource, contains('MediaQuery.viewInsetsOf(context)'));
    expect(dialogTokens, contains('finalmediaHeight=media.size.height;'));
    expect(dialogTokens, contains('finalviewInsets=MediaQuery.viewInsetsOf(context);'));
    expect(dialogTokens, contains(
      'finalrawBottomInset=viewInsets.bottom.isFinite&&viewInsets.bottom>0'
      '?viewInsets.bottom:0.0;',
    ));
    expect(dialogTokens, contains(
      'finalbottomInset=mediaHeight.isFinite?rawBottomInset'
      '.clamp(0.0,mediaHeight>0?mediaHeight:0.0).toDouble():rawBottomInset;',
    ));
    expect(dialogTokens, contains(
      'finalavailableHeight=mediaHeight.isFinite?(mediaHeight>0'
      '?(mediaHeight-bottomInset).clamp(0.0,mediaHeight).toDouble():0.0)'
      ':double.infinity;',
    ));
    expect(dialogSource, contains('maxHeight: availableHeight * 0.86'));
    expect(dialogSource, contains('final horizontalInset = media.size.width < 360'));
    expect(dialogSource, contains('final effectiveMaxWidth'));
    expect(dialogSource, contains('final effectiveMinWidth'));
    expect(dialogSource, contains('minWidth: effectiveMinWidth'));
    expect(dialogSource, contains('maxWidth: effectiveMaxWidth'));
    expect(dialogSource, isNot(contains('minWidth: 320,')));
    expect(dialogSource, isNot(contains('maxWidth: maxWidth,\n        maxHeight')));
    expect(dialogSource, contains('scrollable: true'));
    expect(dialogSource, contains('fontSize: 16'));
    expect(dialogSource, isNot(contains('fontSize: 22')));
    expect(dialogSource, isNot(contains('theme.textTheme.titleLarge')));
    expect(dialogTokens, contains('maxHeight:availableHeight*0.86'));
    expect(dialogTokens, contains('finalkeyboardLift=bottomInset;'));
    expect(dialogTokens, contains('padding:EdgeInsets.only(bottom:keyboardLift)'));
    expect(dialogTokens, contains(
      'insetPadding:EdgeInsets.symmetric(horizontal:horizontalInset,vertical:24,)',
    ));
    expect(dialogTokens, contains('child:dialog,'));
    expect(dialogTokens, contains('if(!shiftForKeyboard)returnscopedDialog;'));
    expect(dialogTokens, contains('child:scopedDialog,'));
    expect(dialogSource, contains('MediaQuery.removeViewInsets('));
    expect(dialogSource, contains('removeBottom: true'));
    expect(dialogSource, contains('AnimatedPadding('));
    expect(dialogTokens, contains(
      'alignment:bottomInset>0?constAlignment(0,-0.18):Alignment.center,',
    ));
    expect(dialogSource, contains('AppSecondaryControlTheme(child: content!)'));
    expect(dialogSource, contains('actions: actions.isEmpty'));
    expect(dialogSource, contains('children: actions'));
    expect(sheetSource, contains('class AppModalSheet'));
    expect(
      sheetSource,
      contains('final viewInsets = shiftForKeyboard ? media.viewInsets'),
    );
    expect(
      sheetSource,
      contains('padding: EdgeInsets.only(bottom: viewInsets.bottom)'),
    );
    expect(
      sheetSource,
      contains(
        'final availableHeight = (media.size.height - viewInsets.bottom)',
      ),
    );
    expect(sheetSource, contains('maxHeight: availableHeight * 0.88'));
    expect(sheetSource, contains('AppSecondaryControlTheme(child: child)'));
    expect(sheetSource, contains('...leadingActions'));
    expect(sheetSource, contains('...actions'));
    expect(source, contains('backgroundColor: Colors.transparent'));
    expect(
      source,
      contains('child: AppSecondaryControlTheme(child: content!)'),
    );
  });

  test('习惯、日历和小组件二级表单显式使用共享小号样式', () {
    final habit = File('lib/screens/habit_screen.dart').readAsStringSync();
    final calendar = File(
      'lib/screens/calendar_screen.dart',
    ).readAsStringSync();
    final eventSheet = File(
      'lib/widgets/calendar_event_sheet.dart',
    ).readAsStringSync();
    final feedback = File(
      'lib/screens/feedback_screen.dart',
    ).readAsStringSync();
    final todo = File('lib/screens/todo_screen.dart').readAsStringSync();
    final note = File('lib/screens/note_screen.dart').readAsStringSync();
    final quickCapture = File(
      'lib/widgets/quick_capture_fab.dart',
    ).readAsStringSync();
    final goalEdit = File(
      'lib/screens/goal_edit_screen.dart',
    ).readAsStringSync();
    final integrations = File(
      'lib/screens/integrations_screen.dart',
    ).readAsStringSync();
    final widgetScreen = File(
      'lib/screens/widget_screen.dart',
    ).readAsStringSync();
    final admin = File('lib/screens/admin_screen.dart').readAsStringSync();

    expect(habit, contains('AppSecondaryControlTheme('));
    expect(habit, contains('final routeBackground'));
    expect(habit, contains('backgroundColor: routeBackground'));
    expect(calendar, contains('AppSecondaryControlTheme('));
    expect(calendar, contains('final routeBackground'));
    expect(calendar, contains('paintBackground: !widget.useShellBackground'));
    expect(calendar, contains('backgroundColor: widget.useShellBackground'));
    expect(calendar, contains(': routeBackground.withValues(alpha: 0.96)'));
    expect(calendar, isNot(contains('backgroundColor: Colors.transparent')));
    expect(calendar, contains('appSecondaryControlLabelStyle(context)'));
    expect(calendar, contains('AppSecondaryMenuText('));
    expect(
      feedback,
      matches(
        RegExp(
          r'AppSecondaryMenuText\(\s*labelFor\(category, currentLocale\),?\s*\)',
        ),
      ),
    );
    expect(feedback, contains('valueListenable: I18n.localeListenable'));
    expect(todo, contains('AppSecondaryMenuText(_quadrantLabel(quadrant))'));
    expect(todo, contains('AppSecondaryMenuText(priority.label)'));
    expect(
      todo,
      matches(
        RegExp(
          r'AppSecondaryMenuText\(\s*TodoBoardUiCopy.columnTitle\(column\),?\s*\)',
        ),
      ),
    );
    expect(todo, isNot(contains('AppSecondaryMenuText(column.title)')));
    expect(todo, isNot(contains('child: Text(_quadrantLabel(quadrant))')));
    expect(todo, isNot(contains('child: Text(priority.label)')));
    expect(todo, isNot(contains('child: Text(column.title)')));
    expect(habit, isNot(contains("AppSecondaryMenuText('删除习惯'")));
    expect(habit, contains("key: const ValueKey('habit_swipe_delete_button')"));
    expect(habit, isNot(contains('Colors.red')));
    expect(note, contains('title: AppSecondaryMenuText('));
    expect(note, contains("color: cs.error"));
    expect(eventSheet, contains('AppSecondaryControlTheme('));
    expect(quickCapture, contains('AppSecondaryControlTheme('));
    expect(goalEdit, contains('AppSecondaryControlTheme('));
    expect(integrations, contains('AppSecondaryControlTheme('));
    final diary = File('lib/screens/diary_screen.dart').readAsStringSync();
    expect(diary, contains('AppSecondaryControlTheme('));
    expect(diary, contains('final routeBackground'));
    expect(diary, contains('backgroundColor: routeBackground'));
    expect(
      diary,
      contains('titleTextStyle: appSecondaryRouteTitleTextStyle(context)'),
    );
    expect(diary, contains('surfaceTintColor: Colors.transparent'));
    expect(widgetScreen, contains('AppSecondaryControlTheme('));
    expect(widgetScreen, contains('appSecondaryFilledButtonStyle(context)'));
    expect(widgetScreen, contains('appSecondaryFilledButtonStyle(ctx)'));
    expect(widgetScreen, isNot(contains('fontSize: 20')));
    expect(admin, contains('AppSecondaryControlTheme('));
    expect(admin, contains('AppSecondaryMenuText('));
    expect(admin, contains('color: cs.error'));
    expect(admin, isNot(contains('Colors.red')));
    final adminUserActionMenu = admin.substring(
      admin.indexOf('PopupMenuButton<String> _userActionMenu'),
      admin.indexOf('Widget _buildUserListItem'),
    );
    expect(adminUserActionMenu, contains('AppSecondaryMenuText('));
    expect(
      adminUserActionMenu,
      contains('AppSecondaryMenuText(_userText(zh, en, locale), color: color)'),
    );
    expect(adminUserActionMenu, contains("'删除账号与数据'"));
    expect(adminUserActionMenu, contains("'Delete account and data'"));
    expect(
      adminUserActionMenu,
      contains('color: Theme.of(ctx).colorScheme.error'),
    );
    expect(adminUserActionMenu, isNot(contains('child: Text(')));
    expect(adminUserActionMenu, isNot(contains('Colors.red')));

    final preferences = File(
      'lib/screens/preferences_screen.dart',
    ).readAsStringSync();
    expect(preferences, contains('appSecondaryMenuItemTextStyle('));
    expect(preferences, isNot(contains('textTheme.titleMedium')));
    expect(preferences, contains('final routeBackground'));
    expect(preferences, contains('backgroundColor: routeBackground'));
    expect(
      preferences,
      contains('backgroundColor: routeBackground.withValues(alpha: 0.96)'),
    );
    expect(preferences, contains('surfaceTintColor: Colors.transparent'));

    for (final path in [
      'lib/screens/ai_schedule_screen.dart',
      'lib/screens/feedback_screen.dart',
      'lib/screens/share_screen.dart',
      'lib/screens/notification_history_screen.dart',
      'lib/screens/search_screen.dart',
      'lib/screens/diary_screen.dart',
      'lib/screens/widget_screen.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains('AppSecondaryControlTheme('), reason: path);
      expect(source, contains('final routeBackground'), reason: path);
      expect(
        source,
        contains('backgroundColor: routeBackground'),
        reason: path,
      );
      expect(
        source,
        contains('backgroundColor: routeBackground.withValues(alpha: 0.96)'),
        reason: path,
      );
      expect(
        source,
        contains('surfaceTintColor: Colors.transparent'),
        reason: path,
      );
      expect(
        source,
        isNot(contains('backgroundColor: Colors.transparent')),
        reason: path,
      );
    }

    final adminTabContent = admin.substring(
      admin.indexOf('class _AdminTabContent'),
      admin.indexOf('class _AdminTabLabel'),
    );
    expect(adminTabContent, contains('maxWidth: 1440'));
    expect(adminTabContent, contains('child: AppSecondaryControlTheme('));
    expect(
      adminTabContent,
      contains('child: _AdminGlassControlTheme(child: child)'),
    );
    expect(admin, contains('final routeBackground'));
    expect(admin, contains('backgroundColor: routeBackground'));
    expect(
      admin,
      contains('backgroundColor: routeBackground.withValues(alpha: 0.96)'),
    );
    expect(admin, contains('surfaceTintColor: Colors.transparent'));
  });

  test('二级控件选中态浅深主题下保持可读且克制', () {
    final source = _readSource('lib/widgets/surface_components.dart');
    final controls = source.substring(
      source.indexOf('final selectedControlBackground'),
      source.indexOf('return Theme('),
    );

    expect(controls, contains('Color.alphaBlend('));
    expect(
      controls,
      contains('cs.primary.withValues(alpha: isDark ? 0.14 : 0.09)'),
    );
    expect(controls, contains('final selectedControlRenderedBackground'));
    expect(controls, contains('final selectedControlForeground'));
    expect(
      controls,
      contains(
        '_appReadableForeground(\n      selectedControlRenderedBackground,\n      cs.onSurface,\n    )',
      ),
    );
    expect(controls, isNot(contains('cs.onPrimary')));
    expect(controls, isNot(contains('Colors.white')));

    for (final brightness in Brightness.values) {
      final cs = ColorScheme.fromSeed(
        seedColor: const Color(0xFF6750A4),
        brightness: brightness,
      );
      final isDark = brightness == Brightness.dark;
      final selectedBackground = Color.alphaBlend(
        cs.primary.withValues(alpha: isDark ? 0.14 : 0.09),
        cs.surface,
      );
      final renderedBackground = Color.alphaBlend(
        selectedBackground,
        cs.surface,
      );
      final foreground = _readableForeground(renderedBackground, cs.onSurface);

      expect(
        _contrastRatio(renderedBackground, foreground),
        greaterThanOrEqualTo(4.5),
        reason: '$brightness selected control foreground must be readable.',
      );
      expect(
        _contrastRatio(selectedBackground, cs.surface),
        lessThanOrEqualTo(isDark ? 1.35 : 1.20),
        reason: '$brightness selected control background should stay subtle.',
      );
    }
  });
}

String _readSource(String path) {
  return File(path).readAsStringSync().replaceAll('\r\n', '\n');
}

Color _readableForeground(Color background, Color preferred) {
  if (_contrastRatio(background, preferred) >= 4.5) return preferred;
  const dark = Color(0xFF111827);
  final darkContrast = _contrastRatio(background, dark);
  final whiteContrast = _contrastRatio(background, Colors.white);
  return darkContrast >= whiteContrast ? dark : Colors.white;
}

double _contrastRatio(Color a, Color b) {
  final aLum = a.computeLuminance();
  final bLum = b.computeLuminance();
  final lighter = aLum > bLum ? aLum : bLum;
  final darker = aLum > bLum ? bLum : aLum;
  return (lighter + 0.05) / (darker + 0.05);
}
