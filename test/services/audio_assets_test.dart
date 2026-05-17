import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('音频资源', () {
    const tracks = <String>[
      'rain',
      'forest',
      'cafe',
      'waves',
      'brown_noise',
      'night_rain',
      'fan',
      'pink_noise',
      'deep_stream',
    ];

    test('播放服务、番茄钟和目标编辑器暴露同一组音轨', () {
      final focusService = File(
        'lib/services/focus_sound_service.dart',
      ).readAsStringSync();
      final pomodoroScreen = File(
        'lib/screens/pomodoro_screen.dart',
      ).readAsStringSync();
      final goalEditScreen = File(
        'lib/screens/goal_edit_screen.dart',
      ).readAsStringSync();

      for (final id in ['none', ...tracks]) {
        expect(
          focusService,
          contains("'$id'"),
          reason: 'FocusSoundService 缺少 $id',
        );
        expect(pomodoroScreen, contains("'$id'"), reason: '番茄钟选择器缺少 $id');
        expect(goalEditScreen, contains("'$id'"), reason: '目标专注联动缺少 $id');
      }
    });

    test('白噪音音轨齐全且不再是同尺寸占位噪声', () {
      final files = tracks
          .map((id) => File('assets/sounds/white_noise/$id.mp3'))
          .toList();

      for (final file in files) {
        expect(file.existsSync(), isTrue, reason: '${file.path} 不存在');
        expect(file.lengthSync(), greaterThan(256 * 1024));
      }

      final sizes = files.map((file) => file.lengthSync()).toSet();
      expect(sizes.length, greaterThan(4), reason: '所有白噪音音轨尺寸过于一致，容易退回同一批占位噪声');

      final signatures = <String>{};
      for (final file in files) {
        final digest = file.openSync();
        try {
          final bytes = digest.readSync(4096);
          signatures.add(base64Encode(bytes));
        } finally {
          digest.closeSync();
        }
      }
      expect(
        signatures.length,
        files.length,
        reason: '白噪音文件开头完全相同，可能仍是复制出来的占位资源',
      );
    });

    test('Android 通知提示音存在且不是静音占位文件', () {
      final file = File('android/app/src/main/res/raw/duoyi_alarm.wav');

      expect(file.existsSync(), isTrue);
      expect(file.lengthSync(), greaterThan(32 * 1024));
      expect(file.lengthSync(), lessThan(256 * 1024));
    });
  });
}
