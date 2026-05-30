import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('扩展功能无效输入不会静默失败', () {
    final source = File(
      'lib/screens/integrations_screen.dart',
    ).readAsStringSync();

    expect(source, contains('String? nameError'));
    expect(source, contains('String? urlError'));
    expect(source, contains('请填写订阅名称'));
    expect(source, contains('请输入有效的 http/https 地址'));
    expect(source, contains('String? titleError'));
    expect(source, contains('String? latError'));
    expect(source, contains('String? lngError'));
    expect(source, contains('String? radiusError'));
    expect(source, contains('请填写提醒标题'));
    expect(source, contains('请输入有效纬度'));
    expect(source, contains('请输入有效经度'));
    expect(source, contains('请输入有效半径'));
  });

  test('账号资料保存不被只读用户名阻断', () {
    final source = File('lib/screens/profile_screen.dart').readAsStringSync();
    final saveStart = source.indexOf('Future<void> _save() async');
    final saveEnd = source.indexOf('@override', saveStart);
    expect(saveStart, greaterThanOrEqualTo(0));
    expect(saveEnd, greaterThan(saveStart));
    final saveBody = source.substring(saveStart, saveEnd);

    expect(saveBody, isNot(contains('auth.error.username_length')));
    expect(saveBody, isNot(contains('auth.error.username_no_space')));
    expect(saveBody, contains('await auth.updateProfile('));
  });

  test('隐藏的习惯撤销按钮不可交互', () {
    final source = File('lib/screens/habit_screen.dart').readAsStringSync();
    final hiddenStart = source.indexOf(
      "key: const ValueKey('habit-undo-hidden')",
    );
    expect(hiddenStart, greaterThanOrEqualTo(0));
    final hiddenSource = source.substring(hiddenStart, hiddenStart + 260);

    expect(hiddenSource, contains('onPressed: null'));
    expect(hiddenSource, isNot(contains('onPressed: () {}')));
  });

  test('习惯列表直接提供结束和删除入口且按钮文字保持对比', () {
    final source = File('lib/screens/habit_screen.dart').readAsStringSync();

    expect(source, contains("tooltip: '习惯操作'"));
    expect(
      source,
      contains(
        "const PopupMenuItem(value: 'end', child: AppSecondaryMenuText('结束习惯'))",
      ),
    );
    expect(source, contains("value: 'delete'"));
    expect(source, contains('await provider.endHabit(habit.id)'));
    expect(source, contains('await provider.deleteHabit(habit.id)'));
    expect(source, contains('Color _habitButtonForeground(Color background)'));
    expect(source, contains('_habitContrastRatio(background, Colors.white)'));
    expect(
      source,
      contains('foregroundColor: _habitButtonForeground(habitColor)'),
    );
  });

  test('更新入口按平台能力显示安装动作', () {
    final mine = File('lib/screens/mine_screen.dart').readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();

    expect(mine, contains("import '../services/app_update_installer.dart';"));
    expect(mine, contains('AppUpdateInstaller.supportsInstall'));
    expect(main, contains("import 'services/app_update_installer.dart';"));
    expect(main, contains('AppUpdateInstaller.supportsInstall'));
    expect(main, contains('当前平台不支持应用内安装'));
  });
}
