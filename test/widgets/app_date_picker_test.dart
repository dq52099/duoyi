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
}
