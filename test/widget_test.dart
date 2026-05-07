import 'package:flutter_test/flutter_test.dart';
import 'package:duoyi/main.dart';

void main() {
  testWidgets('App renders 5 tabs', (WidgetTester tester) async {
    await tester.pumpWidget(const DuoyiApp());
    expect(find.text('待办'), findsWidgets);
    expect(find.text('习惯'), findsWidgets);
    expect(find.text('日历'), findsWidgets);
    expect(find.text('专注'), findsWidgets);
    expect(find.text('我的'), findsWidgets);
  });
}
