import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

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

    test('环境音轨存在可辨识动态差异，不只是同一种呼呼底噪', () {
      if (Platform.environment['DUOYI_SKIP_FFMPEG_TESTS'] == '1') {
        return;
      }
      final ffmpeg = Process.runSync('which', ['ffmpeg']);
      if (ffmpeg.exitCode != 0) {
        return;
      }

      final features = <String, _AudioFeature>{};
      for (final id in tracks) {
        features[id] = _readAudioFeature(
          File('assets/sounds/white_noise/$id.mp3'),
        );
      }

      expect(
        features['fan']!.spectralCentroid,
        lessThan(900),
        reason: '风扇应有低频转动基音，而不是高频白噪',
      );
      expect(
        features['brown_noise']!.spectralCentroid,
        lessThan(700),
        reason: '棕噪应明显偏低频',
      );
      expect(
        features['waves']!.rmsStd,
        greaterThan(features['pink_noise']!.rmsStd * 1.4),
        reason: '海浪应有周期性浪涌，不能和平稳粉噪一样平',
      );
      expect(
        features['forest']!.crestFactor,
        greaterThan(5.0),
        reason: '森林音轨应有鸟鸣/叶响点缀峰值',
      );
      expect(
        features['deep_stream']!.crestFactor,
        greaterThan(4.0),
        reason: '溪流音轨应有细碎水波峰值',
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

_AudioFeature _readAudioFeature(File mp3) {
  final temp = File(
    '${Directory.systemTemp.path}/duoyi_audio_${mp3.uri.pathSegments.last}.raw',
  );
  final result = Process.runSync('ffmpeg', [
    '-hide_banner',
    '-loglevel',
    'error',
    '-y',
    '-i',
    mp3.path,
    '-ar',
    '8000',
    '-ac',
    '1',
    '-t',
    '20',
    '-f',
    's16le',
    temp.path,
  ]);
  expect(result.exitCode, 0, reason: '${mp3.path} 解码失败: ${result.stderr}');
  final bytes = temp.readAsBytesSync();
  if (temp.existsSync()) temp.deleteSync();
  final data = ByteData.sublistView(Uint8List.fromList(bytes));
  final samples = <double>[];
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    samples.add(data.getInt16(i, Endian.little) / 32768.0);
  }
  const sampleRate = 8000;
  final frame = sampleRate;
  const centroidFrame = 1024;
  final rms = <double>[];
  for (var start = 0; start + frame <= samples.length; start += frame) {
    var sumSquares = 0.0;
    for (var i = start; i < start + frame; i++) {
      sumSquares += samples[i] * samples[i];
    }
    rms.add(math.sqrt(sumSquares / frame));
  }
  final rmsMean = rms.reduce((a, b) => a + b) / rms.length;
  final rmsStd = math.sqrt(
    rms.map((v) => math.pow(v - rmsMean, 2)).reduce((a, b) => a + b) /
        rms.length,
  );
  final peak = samples.map((v) => v.abs()).reduce(math.max);
  final totalRms = math.sqrt(
    samples.map((v) => v * v).reduce((a, b) => a + b) / samples.length,
  );
  return _AudioFeature(
    rmsStd: rmsStd,
    spectralCentroid: _spectralCentroid(
      samples.take(centroidFrame).toList(),
      sampleRate,
    ),
    crestFactor: peak / totalRms,
  );
}

double _spectralCentroid(List<double> samples, int sampleRate) {
  final n = samples.length;
  var weighted = 0.0;
  var total = 0.0;
  for (var k = 1; k <= n ~/ 2; k++) {
    var real = 0.0;
    var imag = 0.0;
    for (var i = 0; i < n; i++) {
      final angle = 2 * math.pi * k * i / n;
      real += samples[i] * math.cos(angle);
      imag -= samples[i] * math.sin(angle);
    }
    final magnitude = math.sqrt(real * real + imag * imag);
    final freq = k * sampleRate / n;
    weighted += magnitude * freq;
    total += magnitude;
  }
  return total == 0 ? 0 : weighted / total;
}

class _AudioFeature {
  final double rmsStd;
  final double spectralCentroid;
  final double crestFactor;

  const _AudioFeature({
    required this.rmsStd,
    required this.spectralCentroid,
    required this.crestFactor,
  });
}
