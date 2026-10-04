import 'package:duoyi/models/diary_entry.dart';
import 'package:duoyi/providers/diary_provider.dart';
import 'package:duoyi/screens/diary_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 日记列表底部 padding 守卫：
/// “写日记”FAB（extended 高约 56 + 边距）在滚动到底时会盖住最后一张日记卡，
/// ListView 底部 padding 需要计入手势条 inset（MediaQuery.paddingOf.bottom）
/// 加 FAB 余量（88），与 habit_screen 的同款写法保持一致。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<void> pumpDiaryScreen(
    WidgetTester tester, {
    required double bottomInset,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(400, 800);
    tester.view.padding = FakeViewPadding(bottom: bottomInset);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final provider = DiaryProvider();
    await provider.addOrUpdate(
      DiaryEntry(date: DateTime(2026, 10, 3), content: '底部 padding 测试日记'),
    );

    await tester.pumpWidget(
      ChangeNotifierProvider<DiaryProvider>.value(
        value: provider,
        child: const MaterialApp(home: DiaryScreen()),
      ),
    );
    await tester.pump();
  }

  double listBottomPadding(WidgetTester tester) =>
      (tester.widget<ListView>(find.byType(ListView)).padding! as EdgeInsets)
          .bottom;

  testWidgets('底部 padding 计入手势条 inset（24）+ 88 的 FAB 余量', (tester) async {
    await pumpDiaryScreen(tester, bottomInset: 24);

    expect(find.byType(ListView), findsOneWidget);
    expect(listBottomPadding(tester), 24 + 88);
  });

  testWidgets('无手势条 inset 时仍保留 88 的 FAB 余量，不再回到旧的 16', (tester) async {
    await pumpDiaryScreen(tester, bottomInset: 0);

    expect(find.byType(ListView), findsOneWidget);
    expect(listBottomPadding(tester), 88);
    expect(listBottomPadding(tester), isNot(16));
  });
}
