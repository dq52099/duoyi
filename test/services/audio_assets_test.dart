import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:duoyi/core/focus_sound_catalog.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:test/test.dart';

void main() {
  group('音频资源', () {
    const tracks = <String>[
      'rain',
      'forest',
      'cafe',
      'waves',
      'night_rain',
      'fan',
      'deep_stream',
      'thunderstorm',
      'storm_rain',
      'campfire',
      'dawn_birds',
      'waterfall',
      'brook',
      'river',
      'crickets',
      'clock',
      'keyboard',
      'wind',
      'train_station',
      'classroom',
      'pebble_beach',
      'mall',
      'restaurant',
      'garden_birds',
      'country_night',
      'shallow_river',
      'veranda_rain',
      'breeze_birds',
    ];
    const bannedGeneratedNoiseIds = <String>{
      'brown_noise',
      'pink_noise',
      'white_stream',
    };

    test('播放服务、番茄钟和目标编辑器暴露同一组音轨', () {
      final catalog = File(
        'lib/core/focus_sound_catalog.dart',
      ).readAsStringSync();
      final focusService = File(
        'lib/services/focus_sound_service.dart',
      ).readAsStringSync();
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      final mainActivity = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/MainActivity.kt',
      ).readAsStringSync();
      final foregroundService = File(
        'android/app/src/main/kotlin/com/duoyi/duoyi/services/FocusSoundForegroundService.kt',
      ).readAsStringSync();
      final pomodoroScreen = File(
        'lib/screens/pomodoro_screen.dart',
      ).readAsStringSync();
      final goalEditScreen = File(
        'lib/screens/goal_edit_screen.dart',
      ).readAsStringSync();

      for (final id in ['none', ...tracks]) {
        expect(catalog, contains("'$id'"), reason: 'FocusSoundCatalog 缺少 $id');
      }
      for (final id in bannedGeneratedNoiseIds) {
        expect(catalog, isNot(contains("'$id'")), reason: '$id 不应再发布');
      }

      expect(focusService, contains('FocusSoundCatalog.assetMap'));
      expect(focusService, contains('AssetSource(assets.single)'));
      expect(focusService, contains('await player.play('));
      expect(focusService, contains('volume: _volume'));
      expect(focusService, contains('ctx: _focusAudioContext'));
      expect(focusService, contains('AudioContextConfig('));
      expect(focusService, contains('stayAwake: true'));
      expect(focusService, contains('defaultVolume = 0.95'));
      expect(focusService, contains('_playbackGeneration'));
      expect(focusService, contains('assets.length != 1'));
      expect(
        focusService,
        isNot(contains('_attachCompletionHook')),
        reason: 'looping must rely on one player, not manual replay overlays',
      );
      expect(focusService, isNot(contains('Random(')));
      expect(focusService, isNot(contains('sin(')));
      expect(focusService, isNot(contains('Float32List')));
      expect(focusService, isNot(contains('Uint8List')));
      expect(focusService, contains('MethodChannel('));
      expect(focusService, contains("'duoyi/focus_sound_foreground'"));
      expect(focusService, contains('_startForegroundService'));
      expect(focusService, contains('_stopForegroundService'));
      expect(manifest, contains('.services.FocusSoundForegroundService'));
      expect(
        manifest,
        contains('android:foregroundServiceType="mediaPlayback"'),
      );
      expect(manifest, isNot(contains('MissingClass')));
      expect(mainActivity, contains('focusSoundForegroundChannel'));
      expect(foregroundService, contains('startForeground(notificationId'));
      expect(foregroundService, contains('NotificationManager.IMPORTANCE_LOW'));
      expect(pomodoroScreen, contains('FocusSoundCatalog.options'));
      expect(pomodoroScreen, isNot(contains('组合环境音')));
      expect(pomodoroScreen, isNot(contains('组合音轨')));
      expect(goalEditScreen, contains('FocusSoundCatalog.options'));
    });

    test('白噪音不解析也不发布组合配置', () {
      final mixes = <String>[
        'rain+thunderstorm',
        'waves+storm_rain',
        'forest+deep_stream',
        'cafe+rain',
      ];

      for (final mix in mixes) {
        expect(FocusSoundCatalog.trackIdsFor(mix), isEmpty);
        expect(FocusSoundCatalog.assetsFor(mix), isEmpty);
        expect(FocusSoundCatalog.labelFor(mix), '无白噪音');
        expect(
          FocusSoundCatalog.options.map((option) => option.id),
          isNot(contains(mix)),
        );
      }
    });

    test('白噪音音轨齐全且不是占位静音文件', () {
      final files = tracks
          .map((id) => File('assets/sounds/white_noise/$id.mp3'))
          .toList();

      for (final file in files) {
        expect(file.existsSync(), isTrue, reason: '${file.path} 不存在');
        expect(file.lengthSync(), greaterThan(256 * 1024));
      }

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

    test('白噪音来源和授权信息完整记录', () {
      final readme = File(
        'assets/sounds/white_noise/README.md',
      ).readAsStringSync();
      expect(readme, contains('commons.wikimedia.org/wiki/File:'));
      expect(readme, isNot(contains('tool/generate_white_noise.py')));
      for (final id in tracks) {
        expect(readme, contains('$id.mp3'), reason: 'README 缺少 $id.mp3 来源说明');
      }
      for (final license in ['Public domain', 'CC0', 'CC BY']) {
        expect(readme, contains(license), reason: 'README 缺少 $license 授权说明');
      }
      expect(
        readme,
        contains('File:Heavy_rain_in_Glenshaw,_PA.ogg'),
        reason: 'storm_rain.mp3 必须记录单个可追溯来源',
      );
      expect(
        readme,
        contains('File:Trains_through_a_railwa.ogg'),
        reason: 'train_station.mp3 必须记录单个可追溯来源',
      );
      expect(
        readme,
        contains('File:Ambient_classroom_mono.ogg'),
        reason: 'classroom.mp3 必须记录单个可追溯来源',
      );
      expect(
        readme,
        contains('File:On_a_pebble_beach.ogg'),
        reason: 'pebble_beach.mp3 必须记录单个可追溯来源',
      );
      expect(
        readme,
        contains('File:1_minute_at_the_alexa_mall_in_berlin.ogg'),
        reason: 'mall.mp3 必须记录单个可追溯来源',
      );
      expect(
        readme,
        contains('File:Restaurant_ambience.ogg'),
        reason: 'restaurant.mp3 必须记录单个可追溯来源',
      );
      expect(
        readme,
        contains('File:Birds_singing_in_garden.ogg'),
        reason: 'garden_birds.mp3 必须记录单个可追溯来源',
      );
      expect(
        readme,
        contains('File:Country_night_noise.ogg'),
        reason: 'country_night.mp3 必须记录单个可追溯来源',
      );
      expect(
        readme,
        contains('File:Shallow_small_river_with_stony_riverbed.ogg'),
        reason: 'shallow_river.mp3 必须记录单个可追溯来源',
      );
      expect(
        readme,
        contains('File:Rain_on_a_veranda_and_t.ogg'),
        reason: 'veranda_rain.mp3 必须记录单个可追溯来源',
      );
      expect(
        readme,
        contains('File:Gentle_breeze_and_birds_singing.ogg'),
        reason: 'breeze_birds.mp3 必须记录单个可追溯来源',
      );
      for (final id in bannedGeneratedNoiseIds) {
        expect(readme, isNot(contains('$id.mp3')), reason: '$id 来源不应回归');
      }
      expect(readme, contains('禁止新增或恢复'));
      expect(readme, contains('纯合成/纯噪声资源'));
      expect(readme, isNot(contains('待复核')));
      expect(readme, isNot(contains('禁止组合来源')));
    });

    test('纯合成噪声资源和生成脚本不得回归', () {
      expect(File('tool/generate_white_noise.py').existsSync(), isFalse);

      for (final id in bannedGeneratedNoiseIds) {
        expect(
          FocusSoundCatalog.assetMap.keys,
          isNot(contains(id)),
          reason: '$id 不应留在资源映射',
        );
        expect(
          FocusSoundCatalog.tracks.map((track) => track.id),
          isNot(contains(id)),
          reason: '$id 不应留在音轨列表',
        );
        expect(
          FocusSoundCatalog.options.map((option) => option.id),
          isNot(contains(id)),
          reason: '$id 不应留在选择列表',
        );
        expect(FocusSoundCatalog.trackIdsFor(id), isEmpty, reason: '$id 不应可播放');
        expect(FocusSoundCatalog.assetsFor(id), isEmpty, reason: '$id 不应有资源');
        expect(
          File('assets/sounds/white_noise/$id.mp3').existsSync(),
          isFalse,
          reason: '$id.mp3 不应留在资源目录',
        );
      }
    });

    test('纯合成噪声 id 不留 UI 死分支', () {
      final uiFiles = [
        File('lib/screens/pomodoro_screen.dart'),
        File('lib/widgets/pomodoro_session_card.dart'),
      ];

      for (final file in uiFiles) {
        final source = file.readAsStringSync();
        for (final id in bannedGeneratedNoiseIds) {
          expect(
            source,
            isNot(contains("'$id'")),
            reason: '${file.path} 残留 $id',
          );
          expect(
            source,
            isNot(contains('"$id"')),
            reason: '${file.path} 残留 $id',
          );
        }
      }
    });

    test('白噪音文案、资源和 README 来源一一对应', () {
      final readme = File(
        'assets/sounds/white_noise/README.md',
      ).readAsStringSync();
      final assetFiles = Directory('assets/sounds/white_noise')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.mp3'))
          .map((file) => file.uri.pathSegments.last)
          .toSet();
      final catalogFiles = FocusSoundCatalog.tracks
          .map((track) => track.asset.split('/').last)
          .toSet();

      expect(catalogFiles, assetFiles);

      final labels = FocusSoundCatalog.tracks.map((track) => track.label);
      for (final label in labels) {
        expect(label, isNot(contains('噪')), reason: '$label 不应显示为噪声占位名');
        expect(label, isNot(contains('生成')), reason: '$label 不应显示为生成音频');
        expect(label, isNot(contains('合成')), reason: '$label 不应显示为合成音频');
        expect(label, isNot(contains('噪音')), reason: '$label 文案不应像占位噪音');
      }

      for (final track in FocusSoundCatalog.tracks) {
        final fileName = track.asset.split('/').last;
        expect(readme, contains('`$fileName`'), reason: 'README 缺少 $fileName');
        expect(
          readme,
          contains(track.label.replaceAll('低频棕噪', '棕噪')),
          reason: 'README 来源说明应能对应 ${track.label}',
        );
      }
    });

    test('白噪音 manifest 固定真实录音来源、许可和文件哈希', () {
      final manifest = _readWhiteNoiseManifest();
      final readme = File(
        'assets/sounds/white_noise/README.md',
      ).readAsStringSync();
      final processing = Map<String, dynamic>.from(
        manifest['processing'] as Map,
      );
      final manifestTracks = _manifestTracks(manifest);
      final manifestIds = manifestTracks
          .map((track) => track['id']?.toString())
          .toSet();
      final catalogIds = FocusSoundCatalog.tracks
          .map((track) => track.id)
          .toSet();

      expect(manifest['schemaVersion'], 1);
      expect(manifestIds, catalogIds);
      expect(processing['format'], 'mp3');
      expect(processing['durationSeconds'], closeTo(60.029388, 0.001));
      expect(processing['bitRate'], 112054);

      for (final rule in manifest['rules'] as List<dynamic>) {
        final text = rule.toString();
        expect(text, isNot(contains('synthetic placeholder')));
        expect(text.trim(), isNotEmpty);
      }

      final hashes = <String>{};
      for (final track in manifestTracks) {
        final id = track['id']?.toString() ?? '';
        final fileName = track['file']?.toString() ?? '';
        final sourceUrl = track['sourceUrl']?.toString() ?? '';
        final author = track['author']?.toString() ?? '';
        final license = track['license']?.toString() ?? '';
        final expectedSha = track['sha256']?.toString() ?? '';
        final file = File('assets/sounds/white_noise/$fileName');

        expect(tracks, contains(id), reason: 'manifest 出现未发布 id: $id');
        expect(fileName, '$id.mp3');
        expect(
          sourceUrl,
          startsWith('https://commons.wikimedia.org/wiki/File:'),
        );
        expect(author.trim(), isNotEmpty, reason: '$id 缺少作者');
        expect(license.trim(), isNotEmpty, reason: '$id 缺少许可');
        expect(readme, contains(sourceUrl), reason: 'README 缺少 $id 来源链接');
        expect(readme, contains(license), reason: 'README 缺少 $id 许可');
        expect(expectedSha, hasLength(64), reason: '$id sha256 长度错误');
        expect(hashes.add(expectedSha), isTrue, reason: '$id sha256 重复');
        expect(file.existsSync(), isTrue, reason: '$fileName 不存在');
        final actualSha = crypto.sha256
            .convert(file.readAsBytesSync())
            .toString();
        expect(actualSha, expectedSha, reason: '$id 文件内容与 manifest 不一致');
      }
    });

    test('白噪音 manifest 记录的编码规格与真实文件一致', () {
      if (Platform.environment['DUOYI_SKIP_FFMPEG_TESTS'] == '1') {
        return;
      }
      final ffprobe = Process.runSync('which', ['ffprobe']);
      if (ffprobe.exitCode != 0) {
        return;
      }

      final manifest = _readWhiteNoiseManifest();
      final processing = Map<String, dynamic>.from(
        manifest['processing'] as Map,
      );
      final expectedDuration = (processing['durationSeconds'] as num)
          .toDouble();
      final expectedBitRate = (processing['bitRate'] as num).toInt();

      for (final track in _manifestTracks(manifest)) {
        final id = track['id']?.toString() ?? '';
        final fileName = track['file']?.toString() ?? '';
        final result = Process.runSync('ffprobe', [
          '-v',
          'error',
          '-show_entries',
          'format=duration,bit_rate',
          '-of',
          'default=noprint_wrappers=1:nokey=1',
          'assets/sounds/white_noise/$fileName',
        ]);
        expect(result.exitCode, 0, reason: '$id ffprobe 失败: ${result.stderr}');
        final lines = result.stdout
            .toString()
            .split(RegExp(r'\s+'))
            .where((line) => line.trim().isNotEmpty)
            .toList();
        expect(
          lines.length,
          greaterThanOrEqualTo(2),
          reason: '$id ffprobe 输出异常',
        );
        final duration = double.parse(lines[0]);
        final bitRate = int.parse(lines[1]);
        expect(duration, closeTo(expectedDuration, 0.01), reason: '$id 时长异常');
        expect(bitRate, expectedBitRate, reason: '$id 码率异常');
      }
    });

    test('音轨可解码且存在可听信号', () {
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

      for (final entry in features.entries) {
        expect(entry.value.rmsStd, greaterThanOrEqualTo(0));
        expect(entry.value.spectralCentroid.isFinite, isTrue);
        expect(
          entry.value.crestFactor,
          greaterThan(1.05),
          reason: '${entry.key} 解码后接近静音或平直占位信号',
        );
      }
    });

    test('Android 通知提示音存在且不是静音占位文件', () {
      final files = [
        'duoyi_alarm.wav',
        'duoyi_chime.wav',
        'duoyi_bell.wav',
        'duoyi_beep.wav',
        'duoyi_classic.wav',
      ].map((name) => File('android/app/src/main/res/raw/$name'));

      for (final file in files) {
        expect(file.existsSync(), isTrue, reason: '${file.path} 不存在');
        expect(file.lengthSync(), greaterThan(32 * 1024));
        expect(file.lengthSync(), lessThan(256 * 1024));
      }
    });
  });
}

Map<String, dynamic> _readWhiteNoiseManifest() {
  return jsonDecode(
        File('assets/sounds/white_noise/manifest.json').readAsStringSync(),
      )
      as Map<String, dynamic>;
}

List<Map<String, dynamic>> _manifestTracks(Map<String, dynamic> manifest) {
  return (manifest['tracks'] as List<dynamic>)
      .map((track) => Map<String, dynamic>.from(track as Map))
      .toList(growable: false);
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
