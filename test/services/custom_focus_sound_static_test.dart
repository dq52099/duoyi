import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('专注白噪音支持用户导入自定义音频并进入选择列表', () {
    final provider = File(
      'lib/providers/custom_focus_sound_provider.dart',
    ).readAsStringSync();
    final service = File(
      'lib/services/focus_sound_service.dart',
    ).readAsStringSync();
    final pomodoroScreen = File(
      'lib/screens/pomodoro_screen.dart',
    ).readAsStringSync();
    final goalEditScreen = File(
      'lib/screens/goal_edit_screen.dart',
    ).readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();
    final backup = File('lib/services/backup_service.dart').readAsStringSync();

    expect(provider, contains('class CustomFocusSoundProvider'));
    expect(provider, contains('openFile('));
    expect(provider, contains('getApplicationDocumentsDirectory'));
    expect(provider, contains('duoyi_custom_focus_sounds'));
    expect(provider, contains('registerCustomTracks'));
    expect(service, contains('DeviceFileSource(customPath)'));
    expect(service, contains('registerCustomTracks'));
    expect(pomodoroScreen, contains('CustomFocusSoundProvider'));
    expect(pomodoroScreen, contains('导入音频'));
    expect(pomodoroScreen, contains('customProvider.sounds'));
    expect(goalEditScreen, contains('CustomFocusSoundProvider'));
    expect(
      goalEditScreen,
      contains('context.watch<CustomFocusSoundProvider>().sounds'),
    );
    expect(main, contains('CustomFocusSoundProvider()'));
    expect(main, contains('customFocusSoundProvider.loadFromStorage()'));
    expect(backup, contains("'duoyi_custom_focus_sounds'"));
  });
}
