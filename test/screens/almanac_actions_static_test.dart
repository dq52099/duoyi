import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('黄历和万年历右上角只保留有反馈的今天动作', () {
    final source = File('lib/screens/almanac_screen.dart').readAsStringSync();

    expect(source, contains('void _goToday()'));
    expect(source, contains("Text(alreadyToday ? '已经是今天' : '已回到今天')"));
    expect(source, contains('messenger.hideCurrentSnackBar()'));
    expect(source, contains('behavior: SnackBarBehavior.floating'));
    expect(source, contains("tooltip: '回到今天'"));

    expect(source, isNot(contains('void _toggleMode()')));
    expect(source, isNot(contains("tooltip: isAlmanac ? '切换到万年历' : '切换到黄历'")));
    expect(source, isNot(contains('Navigator.pushReplacement(')));
  });
}
