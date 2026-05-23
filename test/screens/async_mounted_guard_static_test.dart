import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('万年历和日期选择器返回后先检查 mounted 再 setState', () {
    final guardedFiles = <String>[
      'lib/screens/almanac_screen.dart',
      'lib/screens/calendar_screen.dart',
      'lib/screens/countdown_screen.dart',
      'lib/screens/course_schedule_screen.dart',
      'lib/screens/anniversary_screen.dart',
      'lib/screens/todo_detail_screen.dart',
      'lib/screens/todo_screen.dart',
    ];

    for (final path in guardedFiles) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        contains('if (!mounted) return;'),
        reason:
            '$path should guard async picker/sheet returns before setState.',
      );
    }
  });

  test('万年历日期始终限制在农历算法支持范围内', () {
    final source = File('lib/screens/almanac_screen.dart').readAsStringSync();

    expect(source, contains('static final DateTime _firstSupportedDate'));
    expect(source, contains('static final DateTime _lastSupportedDate'));
    expect(source, contains('DateTime _clampDate(DateTime value)'));
    expect(source, contains('_date = _clampDate(widget.initialDate'));
    expect(source, contains('_clampDate(_date.add(Duration(days: days)))'));
    expect(source, contains('firstDate: _firstSupportedDate'));
    expect(source, contains('lastDate: _lastSupportedDate'));
    expect(source, contains('onPressed: _date == _firstSupportedDate'));
    expect(source, contains('onPressed: _date == _lastSupportedDate'));
    expect(source, contains('void _goToday()'));
    expect(source, contains('messenger.hideCurrentSnackBar();'));
    expect(source, contains('messenger.showSnackBar('));
    expect(source, contains("tooltip: '回到今天'"));
    expect(source, isNot(contains('void _toggleMode()')));
    expect(source, isNot(contains('Navigator.pushReplacement')));
  });

  test('无状态日期字段使用 context.mounted 防止返回后回调继续写状态', () {
    final source = File('lib/screens/goal_edit_screen.dart').readAsStringSync();
    final dateFieldBody = source.substring(
      source.indexOf('class _DateField extends StatelessWidget'),
      source.indexOf('String _formatDate(DateTime d)'),
    );

    expect(dateFieldBody, contains('await AppDatePicker.pickSolar('));
    expect(dateFieldBody, contains('if (!context.mounted) return;'));
    expect(dateFieldBody, contains('if (picked != null) onPick(picked);'));
  });

  test('管理员后台异步返回后不写已销毁 controller 或 setState', () {
    final source = File('lib/screens/admin_screen.dart').readAsStringSync();

    expect(
      source,
      contains(
        'final data = await widget.api.getSettings();\n      if (!mounted) return;',
      ),
    );
    expect(
      source,
      contains(
        'final res = await widget.api.testAi();\n      if (!mounted) return;',
      ),
    );
    expect(
      source,
      contains('final backupPage = await widget.api.listBackupsPage('),
    );
    expect(
      source,
      contains(
        'final serverBackupPage = await widget.api.listServerBackupsPage(',
      ),
    );
    expect(
      source,
      contains('if (!mounted) return;\n      _backupPage = backupPage;'),
    );
  });

  test('评论发送成功后清空输入框前确认页面仍挂载', () {
    final share = File('lib/screens/share_screen.dart').readAsStringSync();
    final todoDetail = File(
      'lib/screens/todo_detail_screen.dart',
    ).readAsStringSync();

    expect(
      share,
      contains('await context.read<ShareProvider>().createComment'),
    );
    expect(
      share,
      contains('if (!context.mounted) return;\n      _commentCtrl.clear();'),
    );
    expect(
      todoDetail,
      contains('await context.read<ShareProvider>().createComment'),
    );
    expect(todoDetail, contains('if (!mounted) return;\n      _ctrl.clear();'));
  });

  test('重复规则月日输入 controller 不在 build 中临时创建', () {
    final source = File(
      'lib/widgets/recurrence_picker.dart',
    ).readAsStringSync();

    expect(
      source,
      contains('late final TextEditingController _byMonthDayCtrl;'),
    );
    expect(source, contains('_byMonthDayCtrl = TextEditingController('));
    expect(source, contains('_byMonthDayCtrl.dispose();'));
    expect(source, contains('controller: _byMonthDayCtrl'));
    expect(source, isNot(contains('controller: TextEditingController(')));
  });
}
