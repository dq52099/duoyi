import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:duoyi/core/admin_ui_copy.dart';
import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/auth_provider.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/screens/admin_screen.dart';
import 'package:duoyi/services/ai_service.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:duoyi/widgets/brand_background.dart' show BrandRouteSurface;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/weekly_review_screenshot_font.dart';

const _compactLayout = (
  name: '320px200percent',
  size: Size(320, 844),
  scale: 2.0,
);
const _ordinaryLayout = (name: 'ordinary390', size: Size(390, 844), scale: 1.0);

const _priorityBrands = ['defaultBrand', 'liquidGlass'];
const _locales = [AppLocale.zh, AppLocale.en];

/// One mail-provider field of the authorized Cloud Backup / email settings tab.
/// [label] must be the real [AdminUiCopy] return value; nothing is hard-coded.
class _FieldSpec {
  const _FieldSpec(this.role, this.label, {this.obscure = false});

  final String role;
  final String Function(AppLocale locale) label;
  final bool obscure;
}

const _fieldSpecs = <_FieldSpec>[
  _FieldSpec('claw163-sender-email', AdminUiCopy.claw163EmailLabelFor),
  _FieldSpec('resend-sender', AdminUiCopy.resendSenderLabelFor),
  _FieldSpec(
    'system-notice-recipient',
    AdminUiCopy.systemNoticeRecipientLabelFor,
  ),
  _FieldSpec('account-smtp-host', AdminUiCopy.accountSmtpHostLabelFor),
  _FieldSpec('account-smtp-user', AdminUiCopy.accountSmtpUserLabelFor),
  _FieldSpec('account-smtp-from', AdminUiCopy.accountSmtpFromLabelFor),
  _FieldSpec(
    'account-smtp-password',
    AdminUiCopy.accountSmtpPasswordLabelFor,
    obscure: true,
  ),
  _FieldSpec('reminder-smtp-host', AdminUiCopy.reminderSmtpHostLabelFor),
  _FieldSpec('reminder-smtp-user', AdminUiCopy.reminderSmtpUserLabelFor),
  _FieldSpec(
    'reminder-smtp-password',
    AdminUiCopy.reminderSmtpPasswordLabelFor,
    obscure: true,
  ),
];

const _syntheticFrom = 'synthetic-sender@mail.example.test';
const _syntheticPassword = 'synthetic-secret-9137-do-not-send';

void main() {
  setUp(() => I18n.setLocale(AppLocale.zh));
  tearDown(() => I18n.setLocale(AppLocale.zh));

  group('Priority admin mail provider labels 320px 200% matrix', () {
    for (final brand in _priorityBrands) {
      for (final locale in _locales) {
        testWidgets(
          'all long mail provider labels complete, reachable, single-semantics and target44 $brand ${locale.name} ${_compactLayout.name}',
          (tester) => _runLabelMatrix(
            tester,
            brand: brand,
            locale: locale,
            layout: _compactLayout,
          ),
        );
      }
    }
  });

  group('Priority admin mail provider labels 390 ordinary positive control', () {
    for (final brand in _priorityBrands) {
      for (final locale in _locales) {
        testWidgets(
          'all long mail provider labels complete, reachable, single-semantics and target44 $brand ${locale.name} ${_ordinaryLayout.name}',
          (tester) => _runLabelMatrix(
            tester,
            brand: brand,
            locale: locale,
            layout: _ordinaryLayout,
          ),
        );
      }
    }
  });

  group('Priority admin mail provider labels mounted transitions', () {
    testWidgets(
      'preserves synthetic value, selection, controller, focus and password obscure across mounted locale transitions zh <-> en',
      (tester) async {
        final semanticsHandle = tester.ensureSemantics();
        try {
          final fixture = await _mountAdminFixture(
            tester,
            brand: 'liquidGlass',
            locale: AppLocale.zh,
            size: _compactLayout.size,
            scale: _compactLayout.scale,
          );
          final seeded = await _seedTransitionFields(
            tester,
            locale: AppLocale.zh,
          );
          await _expectTransitionPreserved(
            tester,
            seeded,
            locale: AppLocale.zh,
            step: 'initial zh',
          );

          I18n.setLocale(AppLocale.en);
          await tester.pumpAndSettle();
          await _expectTransitionPreserved(
            tester,
            seeded,
            locale: AppLocale.en,
            step: 'zh -> en',
          );

          I18n.setLocale(AppLocale.zh);
          await tester.pumpAndSettle();
          await _expectTransitionPreserved(
            tester,
            seeded,
            locale: AppLocale.zh,
            step: 'en -> zh',
          );

          expect(
            _mutations(fixture),
            isEmpty,
            reason:
                'Locale switches must not POST/PUT/PATCH/DELETE or send mail',
          );
          expect(tester.takeException(), isNull);
        } finally {
          semanticsHandle.dispose();
        }
      },
    );

    testWidgets(
      'preserves synthetic value, selection, controller, focus and password obscure across mounted theme transitions defaultBrand <-> liquidGlass',
      (tester) async {
        final semanticsHandle = tester.ensureSemantics();
        try {
          final fixture = await _mountAdminFixture(
            tester,
            brand: 'defaultBrand',
            locale: AppLocale.en,
            size: _compactLayout.size,
            scale: _compactLayout.scale,
          );
          final seeded = await _seedTransitionFields(
            tester,
            locale: AppLocale.en,
          );
          await _expectTransitionPreserved(
            tester,
            seeded,
            locale: AppLocale.en,
            step: 'initial defaultBrand',
          );

          await tester.runAsync(() => fixture.theme.setBrand('liquidGlass'));
          await tester.pumpAndSettle();
          await _expectTransitionPreserved(
            tester,
            seeded,
            locale: AppLocale.en,
            step: 'defaultBrand -> liquidGlass',
          );

          await tester.runAsync(() => fixture.theme.setBrand('defaultBrand'));
          await tester.pumpAndSettle();
          await _expectTransitionPreserved(
            tester,
            seeded,
            locale: AppLocale.en,
            step: 'liquidGlass -> defaultBrand',
          );

          expect(
            _mutations(fixture),
            isEmpty,
            reason:
                'Theme switches must not POST/PUT/PATCH/DELETE or send mail',
          );
          expect(tester.takeException(), isNull);
        } finally {
          semanticsHandle.dispose();
        }
      },
    );
  });
}

// ---------------------------------------------------------------------------
// Scenario runner
// ---------------------------------------------------------------------------

Future<void> _runLabelMatrix(
  WidgetTester tester, {
  required String brand,
  required AppLocale locale,
  required ({String name, Size size, double scale}) layout,
}) async {
  final semanticsHandle = tester.ensureSemantics();
  try {
    final fixture = await _mountAdminFixture(
      tester,
      brand: brand,
      locale: locale,
      size: layout.size,
      scale: layout.scale,
    );
    final scrollable = _moduleVerticalScrollable(
      modulePrefix: 'admin-backup-',
    ).first;
    expect(
      scrollable,
      findsOneWidget,
      reason: 'Backup/email settings tab must expose a vertical scrollable',
    );

    final probe = _Probe();
    final observations = <Map<String, Object?>>[];
    for (final spec in _fieldSpecs) {
      observations.add(
        await _auditField(
          tester,
          probe,
          spec: spec,
          locale: locale,
          brand: brand,
          layoutName: layout.name,
          scrollable: scrollable,
          captureKey: fixture.captureKey,
        ),
      );
    }

    final scenario =
        'admin-mail-provider-labels-$brand-${locale.name}-${layout.name}';
    await _exportJsonIfRequested(tester, scenario, {
      'scenario': scenario,
      'brand': brand,
      'locale': locale.name,
      'layout': layout.name,
      'viewport': {
        'width': layout.size.width,
        'height': layout.size.height,
        'scale': layout.scale,
      },
      'fields': observations,
      'errors': probe.errors,
    });

    expect(
      probe.errors,
      isEmpty,
      reason:
          'Mail provider label problems ($scenario):\n${probe.errors.join('\n')}',
    );
    expect(
      _mutations(fixture),
      isEmpty,
      reason: 'Label audit must not POST/PUT/PATCH/DELETE or send mail',
    );
    expect(tester.takeException(), isNull);
  } finally {
    semanticsHandle.dispose();
  }
}

class _Probe {
  final List<String> errors = <String>[];

  void check(bool ok, String message) {
    if (!ok) errors.add(message);
  }

  void fail(String message) => errors.add(message);
}

/// Audits one field: reachability, >=44 real field, single semantic label,
/// and painted label completeness. Failures are accumulated with a diagnostic
/// role so one bad field does not hide the others.
Future<Map<String, Object?>> _auditField(
  WidgetTester tester,
  _Probe probe, {
  required _FieldSpec spec,
  required AppLocale locale,
  required String brand,
  required String layoutName,
  required Finder scrollable,
  required GlobalKey captureKey,
}) async {
  final label = spec.label(locale);
  final role = '${spec.role} "$label" ($brand, ${locale.name}, $layoutName)';
  final observation = <String, Object?>{'role': spec.role, 'label': label};

  try {
    await _revealFromTop(tester, _hostUnion(label), scrollable);
  } catch (error) {
    probe.fail('$role cannot be reached by vertical scrolling: $error');
    observation['reachable'] = false;
    return observation;
  }
  final field = _resolveField(label);
  if (field.evaluate().length != 1) {
    probe.fail(
      '$role must resolve to exactly one TextField (inner labelText or '
      'externally labelled), found ${field.evaluate().length}',
    );
    observation['reachable'] = false;
    return observation;
  }
  await tester.ensureVisible(field);
  await tester.pumpAndSettle();
  observation['reachable'] = true;

  // Real field size and reachability.
  final fieldRect = tester.getRect(field);
  observation['field'] = {'width': fieldRect.width, 'height': fieldRect.height};
  probe.check(
    fieldRect.width >= 43.99 && fieldRect.height >= 43.99,
    '$role real field ${fieldRect.width}x${fieldRect.height} is below 44x44',
  );
  final viewportRect = tester.getRect(scrollable);
  probe.check(
    fieldRect.top >= viewportRect.top - 0.5 &&
        fieldRect.bottom <= viewportRect.bottom + 0.5 &&
        fieldRect.left >= viewportRect.left - 0.5 &&
        fieldRect.right <= viewportRect.right + 0.5,
    '$role field $fieldRect is not fully inside reachable viewport $viewportRect',
  );
  probe.check(
    field.hitTestable().evaluate().isNotEmpty,
    '$role field is not hit-testable after scrolling into view',
  );

  // Semantics: one text-field node carrying the complete label once.
  for (final problem in _semanticsProblems(
    tester,
    field,
    label,
    obscure: spec.obscure,
  )) {
    probe.fail('$role semantics: $problem');
  }

  // Painted label: real RenderParagraph of the InputDecorator label (or the
  // external label if the product later moves labels outside the decorator).
  final located = _locateLabelParagraph(tester, field, label);
  observation['labelMode'] = located.mode;
  if (located.problem != null || located.paragraph == null) {
    probe.fail('$role label paragraph: ${located.problem}');
    return observation;
  }
  final paragraph = located.paragraph!;
  probe.check(
    !paragraph.didExceedMaxLines,
    '$role label paragraph didExceedMaxLines (${located.mode} label truncated)',
  );
  final plain = paragraph.text.toPlainText();
  probe.check(
    plain == label,
    '$role painted label text "$plain" differs from AdminUiCopy "$label"',
  );
  probe.check(
    !plain.contains('…'),
    '$role painted label contains an ellipsis: "$plain"',
  );
  final lineBoxes = paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: plain.length),
  );
  observation['labelLines'] = lineBoxes
      .map((box) => box.top.round())
      .toSet()
      .length;

  // Bring the label to the middle of the real scroll viewport before
  // measuring glyph boxes so reachability is measured, not assumed.
  final position = tester.state<ScrollableState>(scrollable).position;
  Rect globalRect(Rect local) =>
      MatrixUtils.transformRect(paragraph.getTransformTo(null), local);
  if (!paragraph.attached) {
    probe.fail('$role label paragraph detached before measurement');
    return observation;
  }
  final labelCenterY = globalRect(Offset.zero & paragraph.size).center.dy;
  final delta = labelCenterY - tester.getRect(scrollable).center.dy;
  position.jumpTo(
    (position.pixels + delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble(),
  );
  await tester.pumpAndSettle();
  if (!paragraph.attached) {
    probe.fail('$role label paragraph detached after scrolling to centre');
    return observation;
  }

  final viewport = tester.getRect(scrollable);
  // The label can float above the field and font glyphs can overhang line
  // boxes. Measure actual ancestor paint clips, not decorative field bounds.
  var bound = viewport;
  RenderObject child = paragraph;
  RenderObject? parent = child.parent;
  while (parent != null) {
    final clip = parent.describeApproximatePaintClip(child);
    if (clip != null) {
      bound = bound.intersect(
        MatrixUtils.transformRect(parent.getTransformTo(null), clip),
      );
    }
    child = parent;
    parent = parent.parent;
  }
  final clipsOwnVerticalOverflow =
      paragraph.overflow != TextOverflow.visible &&
      (paragraph.didExceedMaxLines ||
          paragraph.getMaxIntrinsicHeight(paragraph.size.width) >
              paragraph.size.height + 0.5);
  observation['labelBound'] = {
    'left': bound.left,
    'top': bound.top,
    'right': bound.right,
    'bottom': bound.bottom,
  };

  // Words must not be split across lines.
  for (final word in RegExp(
    r"[A-Za-z0-9]+(?:['’-][A-Za-z0-9]+)*",
  ).allMatches(plain)) {
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: word.start, extentOffset: word.end),
    );
    probe.check(
      boxes.isNotEmpty && boxes.map((b) => b.top.round()).toSet().length == 1,
      '$role word "${word.group(0)}" wraps across lines inside the label',
    );
  }

  var glyphBoxes = 0;
  var i = 0;
  while (i < plain.length) {
    final unit = plain.codeUnitAt(i);
    var end = i + 1;
    if (unit >= 0xD800 && unit <= 0xDBFF && end < plain.length) end = i + 2;
    final cluster = plain.substring(i, end);
    i = end;
    if (cluster.trim().isEmpty) continue;
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: i - cluster.length, extentOffset: i),
    );
    if (boxes.isEmpty) {
      probe.fail('$role glyph "$cluster" has no layout box');
      continue;
    }
    for (final box in boxes) {
      glyphBoxes++;
      final local = box.toRect();
      final actual = globalRect(local);
      probe.check(
        local.width > 0 && local.height > 0,
        '$role glyph "$cluster" has empty size $local',
      );
      probe.check(
        local.left >= -0.5 &&
            local.right <= paragraph.size.width + 0.5 &&
            (!clipsOwnVerticalOverflow ||
                (local.top >= -0.5 &&
                    local.bottom <= paragraph.size.height + 0.5)),
        '$role glyph "$cluster" $local lies outside its own paragraph ${paragraph.size} (clipped)',
      );
      probe.check(
        actual.left >= viewport.left - 0.5 &&
            actual.right <= viewport.right + 0.5 &&
            actual.top >= viewport.top - 0.5 &&
            actual.bottom <= viewport.bottom + 0.5,
        '$role glyph "$cluster" $actual outside reachable viewport $viewport',
      );
      probe.check(
        actual.left >= bound.left - 0.5 &&
            actual.right <= bound.right + 0.5 &&
            actual.top >= bound.top - 0.5 &&
            actual.bottom <= bound.bottom + 0.5,
        '$role glyph "$cluster" $actual outside ${located.mode} label bound $bound',
      );
    }
  }
  probe.check(glyphBoxes > 0, '$role label produced no glyph boxes');
  observation['glyphBoxes'] = glyphBoxes;

  await _capturePngIfRequested(
    tester,
    captureKey,
    'admin-mail-provider-labels-$brand-${locale.name}-$layoutName-${spec.role}',
  );
  return observation;
}

// ---------------------------------------------------------------------------
// Finders and measurement helpers
// ---------------------------------------------------------------------------

/// Matches either the TextField whose decoration owns [label], or an external
/// Semantics host that carries the label (future outside-label layout).
Finder _hostUnion(String label) => find.byWidgetPredicate(
  (w) =>
      (w is TextField && w.decoration?.labelText == label) ||
      (w is Semantics && w.properties.label == label),
  description: 'mail field host "$label"',
);

Finder _resolveField(String label) {
  final direct = find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
    description: 'TextField labelText "$label"',
  );
  if (direct.evaluate().isNotEmpty) return direct;
  final host = find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.label == label,
    description: 'Semantics host "$label"',
  );
  if (host.evaluate().isEmpty) return direct;
  return find.descendant(of: host.first, matching: find.byType(TextField));
}

Finder _fieldByController(TextEditingController controller) =>
    find.byWidgetPredicate(
      (w) => w is TextField && identical(w.controller, controller),
      description: 'TextField with captured controller',
    );

Future<void> _revealFromTop(
  WidgetTester tester,
  Finder target,
  Finder scrollable,
) async {
  final position = tester.state<ScrollableState>(scrollable).position;
  position.jumpTo(position.minScrollExtent);
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    target,
    200,
    scrollable: scrollable,
    maxScrolls: 200,
  );
  await tester.pumpAndSettle();
}

class _LabelHit {
  _LabelHit(this.mode, {this.paragraph, this.problem});

  final String mode;
  final RenderParagraph? paragraph;
  final String? problem;
}

_LabelHit _locateLabelParagraph(
  WidgetTester tester,
  Finder field,
  String label,
) {
  final inner = find.descendant(of: field, matching: find.text(label));
  final outer = find.text(label);
  final Finder text;
  final String mode;
  if (inner.evaluate().isNotEmpty) {
    text = inner;
    mode = 'inner';
  } else {
    text = outer;
    mode = 'outer';
  }
  final count = text.evaluate().length;
  if (count != 1) {
    return _LabelHit(
      mode,
      problem: '$mode label "$label" rendered $count times (expected once)',
    );
  }
  final rich = find.descendant(of: text, matching: find.byType(RichText));
  final target = rich.evaluate().isNotEmpty ? rich : text;
  if (target.evaluate().length != 1) {
    return _LabelHit(mode, problem: 'label RichText is not unique');
  }
  final render = tester.renderObject(target);
  if (render is! RenderParagraph) {
    return _LabelHit(
      mode,
      problem: 'label render object is ${render.runtimeType}',
    );
  }
  return _LabelHit(mode, paragraph: render);
}

List<String> _semanticsProblems(
  WidgetTester tester,
  Finder field,
  String label, {
  required bool obscure,
}) {
  final problems = <String>[];
  final editable = find.descendant(
    of: field,
    matching: find.byType(EditableText),
  );
  if (editable.evaluate().length != 1) {
    return ['field has ${editable.evaluate().length} EditableText descendants'];
  }
  final semantics = tester.getSemantics(editable);
  if (!semantics.flagsCollection.isTextField) {
    problems.add('node is not isTextField');
  }
  final occurrences = label.allMatches(semantics.label).length;
  if (occurrences != 1) {
    problems.add(
      'label "$label" appears $occurrences times in field semantics '
      '"${semantics.label}" (expected exactly once)',
    );
  }
  if (semantics.flagsCollection.isObscured != obscure) {
    problems.add(
      'isObscured=${semantics.flagsCollection.isObscured}, expected $obscure',
    );
  }
  if (tester.widget<EditableText>(editable).obscureText != obscure) {
    problems.add('EditableText.obscureText differs from expected $obscure');
  }
  final duplicates = tester.semantics.simulatedAccessibilityTraversal().where(
    (s) => !s.flagsCollection.isTextField && s.label.trim() == label.trim(),
  );
  if (duplicates.isNotEmpty) {
    problems.add(
      'independent static semantics node duplicates the label '
      '(${duplicates.length} nodes)',
    );
  }
  return problems;
}

Finder _moduleVerticalScrollable({String? modulePrefix}) {
  final parent = modulePrefix != null
      ? find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey &&
              '${(w.key! as ValueKey).value}'.startsWith(modulePrefix),
        )
      : find.byType(TabBarView);
  return find.descendant(
    of: parent,
    matching: find.byWidgetPredicate(
      (w) =>
          w is Scrollable &&
          (w.axisDirection == AxisDirection.down ||
              w.axisDirection == AxisDirection.up),
    ),
  );
}

// ---------------------------------------------------------------------------
// Mounted transition helpers
// ---------------------------------------------------------------------------

class _TransitionState {
  _TransitionState({
    required this.screenState,
    required this.fromController,
    required this.passwordController,
    required this.fromFocusNode,
    required this.fromSelection,
  });

  final State screenState;
  final TextEditingController fromController;
  final TextEditingController passwordController;
  final FocusNode fromFocusNode;
  final TextSelection fromSelection;
}

Future<_TransitionState> _seedTransitionFields(
  WidgetTester tester, {
  required AppLocale locale,
}) async {
  final scrollable = _moduleVerticalScrollable(
    modulePrefix: 'admin-backup-',
  ).first;

  // Password first (adjacent field below "From"), then the focused field.
  final passwordLabel = AdminUiCopy.accountSmtpPasswordLabelFor(locale);
  await _revealFromTop(tester, _hostUnion(passwordLabel), scrollable);
  var passwordField = _resolveField(passwordLabel);
  expect(passwordField, findsOneWidget);
  await tester.ensureVisible(passwordField);
  await tester.pumpAndSettle();
  await tester.enterText(passwordField, _syntheticPassword);
  await tester.pumpAndSettle();
  final passwordController = tester
      .widget<TextField>(passwordField)
      .controller!;

  final fromLabel = AdminUiCopy.accountSmtpFromLabelFor(locale);
  await _revealFromTop(tester, _hostUnion(fromLabel), scrollable);
  final fromField = _resolveField(fromLabel);
  expect(fromField, findsOneWidget);
  await tester.ensureVisible(fromField);
  await tester.pumpAndSettle();
  await tester.enterText(fromField, _syntheticFrom);
  await tester.pumpAndSettle();
  final fromController = tester.widget<TextField>(fromField).controller!;

  // Both fields must stay built so the focused field is not disposed.
  if (_fieldByController(passwordController).evaluate().isEmpty) {
    await tester.drag(scrollable, const Offset(0, -240));
    await tester.pumpAndSettle();
  }
  expect(_fieldByController(fromController), findsOneWidget);
  expect(_fieldByController(passwordController), findsOneWidget);
  passwordField = _fieldByController(passwordController);
  expect(
    tester
        .widget<EditableText>(
          find.descendant(
            of: passwordField,
            matching: find.byType(EditableText),
          ),
        )
        .obscureText,
    isTrue,
    reason: 'Account SMTP Password must be obscured before transitions',
  );

  final editable = find.descendant(
    of: _fieldByController(fromController),
    matching: find.byType(EditableText),
  );
  final focusNode = tester.widget<EditableText>(editable).focusNode;
  focusNode.requestFocus();
  await tester.pumpAndSettle();
  const selection = TextSelection(baseOffset: 10, extentOffset: 20);
  fromController.selection = selection;
  await tester.pumpAndSettle();
  expect(focusNode.hasFocus, isTrue);
  expect(fromController.text, _syntheticFrom);
  expect(fromController.selection, selection);
  expect(passwordController.text, _syntheticPassword);

  return _TransitionState(
    screenState: tester.state(find.byType(AdminScreen)),
    fromController: fromController,
    passwordController: passwordController,
    fromFocusNode: focusNode,
    fromSelection: selection,
  );
}

Future<void> _expectTransitionPreserved(
  WidgetTester tester,
  _TransitionState seeded, {
  required AppLocale locale,
  required String step,
}) async {
  expect(
    tester.state(find.byType(AdminScreen)),
    same(seeded.screenState),
    reason: '$step: AdminScreen state must stay mounted',
  );

  final fromField = _fieldByController(seeded.fromController);
  final passwordField = _fieldByController(seeded.passwordController);
  expect(fromField, findsOneWidget, reason: '$step: From field rebuilt');
  expect(
    passwordField,
    findsOneWidget,
    reason: '$step: password field rebuilt',
  );

  expect(seeded.fromController.text, _syntheticFrom, reason: step);
  expect(seeded.fromController.selection, seeded.fromSelection, reason: step);
  expect(seeded.passwordController.text, _syntheticPassword, reason: step);

  final fromEditable = find.descendant(
    of: fromField,
    matching: find.byType(EditableText),
  );
  expect(
    tester.widget<EditableText>(fromEditable).focusNode,
    same(seeded.fromFocusNode),
    reason: '$step: focus node replaced',
  );
  expect(seeded.fromFocusNode.hasFocus, isTrue, reason: '$step: focus lost');

  final fromLabel = AdminUiCopy.accountSmtpFromLabelFor(locale);
  final passwordLabel = AdminUiCopy.accountSmtpPasswordLabelFor(locale);
  expect(
    _semanticsProblems(tester, fromField, fromLabel, obscure: false),
    isEmpty,
    reason: '$step: From semantics',
  );
  expect(
    _semanticsProblems(tester, passwordField, passwordLabel, obscure: true),
    isEmpty,
    reason: '$step: password semantics/obscure',
  );
  final passwordSemantics = tester.getSemantics(
    find.descendant(of: passwordField, matching: find.byType(EditableText)),
  );
  expect(
    passwordSemantics.value.contains(_syntheticPassword),
    isFalse,
    reason: '$step: password plaintext leaked into semantics value',
  );

  for (final entry in {
    fromLabel: fromField,
    passwordLabel: passwordField,
  }.entries) {
    final located = _locateLabelParagraph(tester, entry.value, entry.key);
    expect(located.problem, isNull, reason: '$step: ${entry.key}');
    expect(
      located.paragraph!.didExceedMaxLines,
      isFalse,
      reason: '$step: label "${entry.key}" truncated',
    );
    expect(located.paragraph!.text.toPlainText(), entry.key, reason: step);
  }
}

// ---------------------------------------------------------------------------
// Export helpers (only when the explicit environment directories are set)
// ---------------------------------------------------------------------------

Future<void> _capturePngIfRequested(
  WidgetTester tester,
  GlobalKey boundaryKey,
  String name,
) async {
  final dir = Platform.environment['DUOYI_PRIORITY_THEME_SCREENSHOT_DIR'];
  if (dir == null || dir.trim().isEmpty) return;
  await tester.runAsync(() async {
    final context = boundaryKey.currentContext;
    if (context == null) return;
    final boundary = context.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;
    final image = await boundary.toImage(pixelRatio: 1);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final file = File('${dir.trim()}${Platform.pathSeparator}$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

Future<void> _exportJsonIfRequested(
  WidgetTester tester,
  String name,
  Map<String, Object?> data,
) async {
  final dir = Platform.environment['DUOYI_PRIORITY_THEME_MEASUREMENTS_DIR'];
  if (dir == null || dir.trim().isEmpty) return;
  await tester.runAsync(() async {
    final file = File('${dir.trim()}${Platform.pathSeparator}$name.json');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
  });
}

// ---------------------------------------------------------------------------
// Fixture: mocked API, authorized admin, brand/locale/layout aware app shell
// ---------------------------------------------------------------------------

List<http.Request> _mutations(_AdminFixture fixture) => fixture.requests
    .where(
      (r) =>
          r.method.toUpperCase() != 'GET' && r.method.toUpperCase() != 'HEAD',
    )
    .toList();

class _TestAuthProvider extends AuthProvider {
  _TestAuthProvider({required ApiClient client, this.permissions})
    : _client = client;

  final ApiClient _client;
  final List<String>? permissions;

  @override
  ApiClient get client => _client;

  @override
  AuthState get state => AuthState(
    userId: 'admin-authorized-user',
    username: 'admin',
    token: 'synthetic-admin-token',
    isAdmin: true,
    adminPermissions: permissions,
  );
}

class _AdminFixture {
  _AdminFixture({
    required this.auth,
    required this.theme,
    required this.ai,
    required this.requests,
    required this.captureKey,
  });

  final _TestAuthProvider auth;
  final ThemeProvider theme;
  final AiService ai;
  final List<http.Request> requests;
  final GlobalKey captureKey;
}

Future<void> _setupPreferences(String brand) async {
  final state = jsonEncode({
    'activeBrand': brand,
    'unlockedBrandIds': ['defaultBrand', 'liquidGlass'],
  });
  SharedPreferences.setMockInitialValues(<String, Object>{
    'pref_app_timezone_mode': 'fixed',
    'pref_app_timezone_iana': 'Asia/Shanghai',
    'active_brand': brand,
    'theme_shop_state': state,
    'theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
    'flutter.pref_app_timezone_mode': 'fixed',
    'flutter.pref_app_timezone_iana': 'Asia/Shanghai',
    'flutter.active_brand': brand,
    'flutter.theme_shop_state': state,
    'flutter.theme_unlocked_brands': ['defaultBrand', 'liquidGlass'],
  });
}

http.Response _mockHandler(http.Request request) {
  final path = request.url.path;
  final query = request.url.queryParameters;

  http.Response json(Object data, [int status = 200]) => http.Response(
    jsonEncode(data),
    status,
    headers: const {'content-type': 'application/json'},
  );

  Map<String, Object?> page(List<Object?> items) => {
    'items': items,
    'total': items.length,
    'limit': int.tryParse(query['limit'] ?? '') ?? 20,
    'offset': int.tryParse(query['offset'] ?? '') ?? 0,
    'has_more': false,
  };

  if (path == '/api/admin/stats') {
    return json({
      'users': {
        'total': 12,
        'disabled': 0,
        'new_today': 1,
        'active_7d': 6,
        'online': 3,
      },
      'feedback': {'total': 2, 'open': 1, 'in_progress': 1},
      'announcements': {'total': 1, 'published': 1},
    });
  }
  if (path == '/api/admin/settings') {
    final scope = query['scope'];
    if (scope == 'backup') {
      return json({
        'backup_enabled': true,
        'backup_max_size_kb': 2048,
        'backup_interval_minutes': 30,
        'backup_retain_days': 7,
        'server_backup_enabled': false,
        'server_backup_interval_minutes': 720,
        'server_backup_retain_days': 14,
        'openlist_backup_enabled': false,
        'openlist_webdav_url': '',
        'openlist_public_url': '',
        'openlist_username': '',
        'openlist_password_set': false,
        'openlist_backup_path': '/duoyi-backups',
        'backup_email_enabled': false,
        'backup_email_to': '',
        'backup_email_from': '',
        'backup_email_smtp_host': '',
        'backup_email_smtp_port': 465,
        'backup_email_smtp_username': '',
        'backup_email_smtp_password_set': false,
        'reminder_email_enabled': false,
        'reminder_email_to': '',
        'reminder_email_from': '',
        'reminder_email_smtp_host': '',
        'reminder_email_smtp_port': 465,
        'reminder_email_smtp_username': '',
        'reminder_email_smtp_password_set': false,
        'email_service_enabled': false,
        'account_email_enabled': true,
        'email_auto_switch_enabled': false,
        'email_code_primary_provider': 'claw163',
        'email_code_backup_provider': 'resend',
        'email_code_active_slot': 'primary',
        'email_title': '多仪',
        'email_sender_name': '多仪',
        'openclaw_mail_user': '',
        'openclaw_mail_api_key_set': false,
        'resend_base_url': 'https://api.resend.com',
        'resend_api_key': '',
        'resend_api_key_set': false,
        'resend_from': '多仪 <noreply@mail.6688667.xyz>',
        'system_notice_email_to': '',
        'email_smtp_host': '',
        'email_smtp_port': 465,
        'email_smtp_username': '',
        'email_smtp_password_set': false,
        'email_smtp_use_ssl': true,
      });
    }
    if (scope == 'ai') {
      return json({
        'ai_enabled': true,
        'ai_base_url': '',
        'ai_model': 'gemini-1.5-pro',
        'ai_api_key_set': true,
        'ai_daily_quota': 1000,
      });
    }
    return json({
      'invite_code_required': false,
      'registration_enabled': true,
      'registration_email_required': false,
      'maintenance_mode': false,
      'force_update_required': false,
      'default_registration_coins': 100,
    });
  }
  if (path == '/api/admin/backups' || path == '/api/admin/server-backups') {
    return json(page(const []));
  }
  if (path == '/api/admin/groups') {
    return json(
      page([
        {
          'id': 'group_default',
          'name': '默认用户组',
          'description': '系统默认普通用户组',
          'default_time_coins': 100,
          'is_active': true,
          'user_count': 5,
          'created_at': '2026-10-01 08:00:00',
          'updated_at': '2026-10-01 08:00:00',
        },
      ]),
    );
  }
  if (path == '/api/admin/roles') {
    return json([
      {
        'id': 'role_admin',
        'name': '系统管理员',
        'description': '全局管理权限角色',
        'permissions': [
          'users',
          'settings',
          'ai',
          'backup',
          'groups',
          'announcements',
          'feedback',
          'invites',
          'audit',
        ],
        'is_active': true,
      },
    ]);
  }
  if (path == '/api/admin/users') {
    final offset = int.tryParse(query['offset'] ?? '') ?? 0;
    final limit = int.tryParse(query['limit'] ?? '') ?? 20;
    const total = 45;
    return json({
      'items': [
        {
          'user_id': 'user-$offset',
          'username': 'admin-test-user-$offset',
          'display_name': '测试管理员',
          'email': 'admin@duoyi.test',
          'email_verified': true,
          'is_admin': true,
          'is_disabled': false,
          'online': true,
          'admin_permissions': ['users', 'settings', 'ai', 'backup'],
          'group_id': 'group_default',
          'role_id': 'role_admin',
          'coin_balance': 200,
          'lifetime_coins': 500,
          'created_at': '2026-10-01 08:00:00',
          'last_login_at': '2026-10-24 06:00:00',
          'last_active_at': '2026-10-24 06:50:00',
        },
      ],
      'total': total,
      'limit': limit,
      'offset': offset,
      'has_more': offset + limit < total,
    });
  }
  if (path == '/api/admin/announcements') {
    return json(
      page([
        {
          'id': 'anno-1',
          'title': '测试公告标题',
          'content': '测试公告内容',
          'level': 'info',
          'is_published': true,
          'created_at': '2026-10-01 08:00:00',
        },
      ]),
    );
  }
  if (path == '/api/admin/feedback') {
    return json(
      page([
        {
          'id': 'feedback-1',
          'user_id': 'user-1',
          'username': 'feedback-author',
          'type': 'feature',
          'content': '反馈内容示例',
          'status': 'open',
          'created_at': '2026-10-01 08:00:00',
        },
      ]),
    );
  }
  if (path == '/api/admin/invite-codes') {
    return json(
      page([
        {
          'code': 'INVITE2026TEST',
          'created_by': 'admin',
          'used_by': null,
          'is_used': false,
          'created_at': '2026-10-01 08:00:00',
          'expires_at': null,
        },
      ]),
    );
  }
  if (path == '/api/admin/audit-log') {
    return json(
      page([
        {
          'id': 'audit-1',
          'user_id': 'user-1',
          'action': 'admin.login',
          'details': {'ip': '127.0.0.1'},
          'created_at': '2026-10-24 06:00:00',
        },
      ]),
    );
  }
  return json({'ok': true});
}

Future<_AdminFixture> _mountAdminFixture(
  WidgetTester tester, {
  required String brand,
  required AppLocale locale,
  required Size size,
  required double scale,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await _setupPreferences(brand);
  I18n.setLocale(locale);

  final theme = ThemeProvider();
  await tester.runAsync(() async {
    await theme.loadFromStorage();
    await loadWeeklyReviewScreenshotFonts();
  });

  final requests = <http.Request>[];
  final mockClient = MockClient((request) async {
    requests.add(request);
    return _mockHandler(request);
  });
  final apiClient = ApiClient(
    baseUrl: 'https://duoyi.test',
    token: 'synthetic-admin-token',
    httpClient: mockClient,
  );
  final auth = _TestAuthProvider(
    client: apiClient,
    permissions: const ['backup', 'settings', 'ai'],
  );
  final ai = AiService()..attachClient(apiClient);

  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    ai.dispose();
    auth.dispose();
    theme.dispose();
  });

  final captureKey = GlobalKey();

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ChangeNotifierProvider<AiService>.value(value: ai),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, currentTheme, _) =>
            ValueListenableBuilder<AppLocale>(
              valueListenable: I18n.localeListenable,
              builder: (context, currentLocale, _) => MaterialApp(
                debugShowCheckedModeBanner: false,
                locale: Locale(currentLocale == AppLocale.en ? 'en' : 'zh'),
                supportedLocales: const [Locale('en'), Locale('zh')],
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                theme: currentTheme.brand.theme,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(size: size, textScaler: TextScaler.linear(scale)),
                  child: RepaintBoundary(key: captureKey, child: child!),
                ),
                home: const BrandRouteSurface(
                  remountOnLocaleChange: false,
                  child: AdminScreen(initialTabIndex: 3),
                ),
              ),
            ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  return _AdminFixture(
    auth: auth,
    theme: theme,
    ai: ai,
    requests: requests,
    captureKey: captureKey,
  );
}
