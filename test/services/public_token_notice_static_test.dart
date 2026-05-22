import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('startup public token notice is wired into launch and Mine entry', () {
    final main = File('lib/main.dart').readAsStringSync();
    final mine = File('lib/screens/mine_screen.dart').readAsStringSync();
    final notice = File(
      'lib/widgets/public_token_notice.dart',
    ).readAsStringSync();

    expect(main, contains('PublicTokenNotice.showStartupDialog(context)'));
    expect(main, contains('static bool _startupNoticeShown = false'));
    expect(mine, contains('const PublicTokenNotice('));
    expect(notice, contains('1104138863'));
    expect(notice, contains('公益 token2 通知'));
    expect(notice, contains('希望人人 token 自由'));
    expect(notice, contains('我们永远不会落后'));
  });
}
