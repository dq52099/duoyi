import 'package:duoyi/widgets/surface_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AppSectionHeader handles long action on narrow width', (
    tester,
  ) async {
    await _pumpNarrow(
      tester,
      width: 280,
      child: AppSectionHeader(
        title: '非常长的标题用于验证窄屏标题不会被右侧操作按钮挤压到不可读',
        subtitle: '较长的说明文字也需要在窄屏下安全省略或换行',
        actionLabel: '导出全部长期统计数据',
        actionIcon: Icons.file_download_outlined,
        onAction: () {},
      ),
    );

    expect(find.textContaining('非常长的标题'), findsOneWidget);
    expect(find.textContaining('导出全部'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AppStatusBadge constrains long labels in narrow containers', (
    tester,
  ) async {
    await _pumpNarrow(
      tester,
      width: 120,
      child: const AppStatusBadge(
        label: '超长角色名称和权限标签会被安全截断而不是撑破父容器',
        color: Colors.indigo,
        icon: Icons.verified_user_outlined,
      ),
    );

    expect(find.byType(AppStatusBadge), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AppSettingsTile keeps text readable with complex trailing', (
    tester,
  ) async {
    await _pumpNarrow(
      tester,
      width: 320,
      child: AppSettingsTile(
        icon: Icons.tune_outlined,
        title: '底部导航和通知设置里的超长设置项标题',
        subtitle: '副标题也可能来自动态状态，需要保留可读空间',
        color: Colors.teal,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: '上移',
              icon: const Icon(Icons.keyboard_arrow_up),
              onPressed: () {},
            ),
            IconButton(
              tooltip: '下移',
              icon: const Icon(Icons.keyboard_arrow_down),
              onPressed: () {},
            ),
            Switch(value: true, onChanged: (_) {}),
          ],
        ),
      ),
    );

    expect(find.textContaining('底部导航'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
    final iconRect = tester.getRect(find.byIcon(Icons.tune_outlined));
    final titleRect = tester.getRect(find.text('底部导航和通知设置里的超长设置项标题'));
    final subtitleRect = tester.getRect(find.text('副标题也可能来自动态状态，需要保留可读空间'));
    final actionRect = tester.getRect(find.byType(Switch));
    final textCenterDy = _textBlockCenterDy(titleRect, subtitleRect);
    expect((iconRect.center.dy - textCenterDy).abs(), lessThan(5));
    expect((actionRect.center.dy - textCenterDy).abs(), lessThan(5));
    expect(actionRect.left, greaterThan(titleRect.left));
    expect(subtitleRect.top, greaterThan(titleRect.bottom));
    expect(tester.takeException(), isNull);
  });

  testWidgets('AppSettingsTile centers leading icon in the whole row', (
    tester,
  ) async {
    await _pumpNarrow(
      tester,
      width: 320,
      child: const AppSettingsTile(
        icon: Icons.notifications_none_outlined,
        title: '没有右侧按钮的设置项',
        subtitle: '默认箭头也不能让标题贴着图标上沿',
        color: Colors.orange,
      ),
    );

    final iconRect = tester.getRect(
      find.byIcon(Icons.notifications_none_outlined),
    );
    final titleRect = tester.getRect(find.text('没有右侧按钮的设置项'));
    final subtitleRect = tester.getRect(find.text('默认箭头也不能让标题贴着图标上沿'));
    final textCenterDy = _textBlockCenterDy(titleRect, subtitleRect);
    expect((iconRect.center.dy - textCenterDy).abs(), lessThan(5));
    expect(subtitleRect.top, greaterThan(titleRect.bottom));
    expect(tester.takeException(), isNull);
  });
}

double _textBlockCenterDy(Rect titleRect, Rect subtitleRect) {
  final top = titleRect.top < subtitleRect.top
      ? titleRect.top
      : subtitleRect.top;
  final bottom = titleRect.bottom > subtitleRect.bottom
      ? titleRect.bottom
      : subtitleRect.bottom;
  return (top + bottom) / 2;
}

Future<void> _pumpNarrow(
  WidgetTester tester, {
  required double width,
  required Widget child,
}) async {
  await tester.binding.setSurfaceSize(Size(width, 640));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
