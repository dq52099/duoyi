import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/widgets/app_date_picker.dart';

void main() {
  testWidgets('公历日期选择器显示可点击日期网格', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                AppDatePicker.show(
                  context,
                  initialDate: DateTime(2026, 5, 17),
                  firstDate: DateTime(2026, 1, 1),
                  lastDate: DateTime(2026, 12, 31),
                );
              },
              child: const Text('打开日期'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开日期'));
    await tester.pumpAndSettle();

    expect(find.text('公历'), findsOneWidget);
    expect(find.text('2026年5月'), findsOneWidget);
    expect(find.text('17'), findsOneWidget);
    expect(find.text('一'), findsOneWidget);
    expect(find.text('日'), findsOneWidget);
  });

  testWidgets('公历当前月日期不是禁用灰色态', (tester) async {
    const scheme = ColorScheme.light(
      primary: Color(0xFF2563EB),
      primaryContainer: Color(0xFFDCE8FF),
      onPrimary: Colors.white,
      onSurface: Color(0xFF111827),
      onSurfaceVariant: Color(0xFF6B7280),
      surface: Colors.white,
      outlineVariant: Color(0xFFE5E7EB),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: scheme),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                AppDatePicker.show(
                  context,
                  initialDate: DateTime(2026, 5, 17),
                  firstDate: DateTime(2026, 1, 1),
                  lastDate: DateTime(2026, 12, 31),
                );
              },
              child: const Text('打开日期'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开日期'));
    await tester.pumpAndSettle();

    final dayFinder = find.byKey(const ValueKey('solar-day-2026-05-19'));
    final material = tester.widget<Material>(dayFinder);
    expect(material.color, isNot(Colors.transparent));

    final text = tester.widget<Text>(
      find.descendant(of: dayFinder, matching: find.text('19')),
    );
    expect(text.style?.color, scheme.onSurface);

    final outsideMonthFinder = find.byKey(
      const ValueKey('solar-day-2026-04-27'),
    );
    final outsideText = tester.widget<Text>(
      find.descendant(of: outsideMonthFinder, matching: find.text('27')),
    );
    expect(outsideText.style?.color, isNot(scheme.onSurface));
  });
}
