import 'dart:async';

import 'package:duoyi/services/admin_api.dart';
import 'package:duoyi/services/admin_feedback_export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('export writes, copies, and shares one owned CSV in order', () async {
    final effects = _FakeEffects();
    const csv = '\uFEFFid,title\n42,literal title 原文\n';
    var textCalls = 0;
    var subjectCalls = 0;

    final path = await _export(
      effects,
      csv: csv,
      shareText: () {
        textCalls++;
        return 'literal share text';
      },
      shareSubject: () {
        subjectCalls++;
        return 'literal share subject';
      },
    );

    final file = effects.allocatedFiles.single;
    expect(path, file.path);
    expect(effects.calls, [
      'temporaryDirectory',
      'allocate',
      'write',
      'copyPath',
      'share',
    ]);
    expect(effects.writtenFiles, [file]);
    expect(effects.writtenCsv, [csv]);
    expect(effects.copiedPaths, [file.path]);
    expect(effects.sharedFiles, [file]);
    expect(effects.sharedTexts, ['literal share text']);
    expect(effects.sharedSubjects, ['literal share subject']);
    expect(textCalls, 1);
    expect(subjectCalls, 1);
    expect(effects.cleanedFiles, isEmpty);
  });

  test('an export already expired starts no effect', () async {
    final effects = _FakeEffects();

    await expectLater(
      _export(effects, isCurrent: () => false),
      throwsA(isA<AdminActionExpired>()),
    );

    expect(effects.calls, isEmpty);
  });

  for (final stage in _stages) {
    test(
      '$stage expiry stops later effects after its future settles',
      () async {
        final effects = _FakeEffects();
        final gate = Completer<void>();
        final started = effects.watchNext(stage);
        _holdStage(effects, stage, gate);
        var current = true;

        final pending = _export(effects, isCurrent: () => current);
        final expired = expectLater(
          pending,
          throwsA(isA<AdminActionExpired>()),
        );
        await started.future;
        current = false;
        if (stage == 'write') {
          expect(effects.cleanedFiles, isEmpty);
        }
        gate.complete();
        await expired;

        expect(effects.calls, _callsThrough(stage));
        if (stage == 'temporaryDirectory') {
          expect(effects.allocatedFiles, isEmpty);
          expect(effects.cleanedFiles, isEmpty);
        } else if (stage == 'share') {
          expect(effects.sharedFiles, hasLength(1));
          expect(effects.cleanedFiles, isEmpty);
        } else {
          final file = effects.allocatedFiles.single;
          expect(effects.cleanedFiles, [file]);
        }
      },
    );

    test('$stage preserves a current stage error', () async {
      final effects = _FakeEffects();
      final gate = Completer<void>();
      final started = effects.watchNext(stage);
      final primary = StateError('primary $stage failure');
      _holdStage(effects, stage, gate, failure: primary);

      final pending = _export(effects);
      final rejected = expectLater(pending, throwsA(same(primary)));
      await started.future;
      gate.complete();
      await rejected;

      if (stage == 'write' || stage == 'copyPath') {
        expect(effects.cleanedFiles, [effects.allocatedFiles.single]);
      } else {
        expect(effects.cleanedFiles, isEmpty);
      }
      if (stage == 'share') {
        expect(effects.sharedFiles, hasLength(1));
      }
    });

    test('$stage error after expiry becomes AdminActionExpired', () async {
      final effects = _FakeEffects();
      final gate = Completer<void>();
      final started = effects.watchNext(stage);
      _holdStage(
        effects,
        stage,
        gate,
        failure: StateError('late $stage failure'),
      );
      var current = true;

      final pending = _export(effects, isCurrent: () => current);
      final expired = expectLater(pending, throwsA(isA<AdminActionExpired>()));
      await started.future;
      current = false;
      gate.complete();
      await expired;

      if (stage == 'temporaryDirectory' || stage == 'allocate') {
        expect(effects.cleanedFiles, isEmpty);
      } else if (stage == 'share') {
        expect(effects.sharedFiles, hasLength(1));
        expect(effects.cleanedFiles, isEmpty);
      } else {
        expect(effects.cleanedFiles, [effects.allocatedFiles.single]);
      }
    });
  }

  test('a held write settles before its owned file is cleaned', () async {
    final effects = _FakeEffects();
    final gate = Completer<void>();
    final started = effects.watchNext('write');
    effects.onWrite = (_, _) => gate.future;
    var current = true;

    final pending = _export(effects, isCurrent: () => current);
    final expired = expectLater(pending, throwsA(isA<AdminActionExpired>()));
    await started.future;
    current = false;
    expect(effects.cleanedFiles, isEmpty);
    gate.complete();
    await expired;

    expect(effects.calls, [
      'temporaryDirectory',
      'allocate',
      'write',
      'cleanup',
    ]);
    expect(effects.cleanedFiles, [effects.allocatedFiles.single]);
    expect(effects.copiedPaths, isEmpty);
    expect(effects.sharedFiles, isEmpty);
  });

  test('cleanup failure does not replace the primary stage error', () async {
    final effects = _FakeEffects();
    final primary = StateError('primary write failure');
    effects.onWrite = (_, _) async => throw primary;
    effects.onCleanup = (_) async => throw StateError('cleanup failure');

    await expectLater(_export(effects), throwsA(same(primary)));

    expect(effects.cleanedFiles, [effects.allocatedFiles.single]);
    expect(effects.copiedPaths, isEmpty);
    expect(effects.sharedFiles, isEmpty);
  });

  test(
    'overlapping exports clean only the older operation owned path',
    () async {
      final effects = _FakeEffects();
      final oldWriteGate = Completer<void>();
      final newWriteGate = Completer<void>();
      final oldWriteStarted = effects.watchNext('write');
      effects.onWrite = (_, csv) async {
        if (csv == 'older export') {
          await oldWriteGate.future;
        } else {
          await newWriteGate.future;
        }
      };
      var oldCurrent = true;
      var newCurrent = true;

      final oldPending = _export(
        effects,
        csv: 'older export',
        isCurrent: () => oldCurrent,
      );
      final oldExpired = expectLater(
        oldPending,
        throwsA(isA<AdminActionExpired>()),
      );
      await oldWriteStarted.future;
      final oldFile = effects.allocatedFiles.single;

      final newWriteStarted = effects.watchNext('write');
      final newPending = _export(
        effects,
        csv: 'newer export',
        isCurrent: () => newCurrent,
      );
      await newWriteStarted.future;
      final newFile = effects.allocatedFiles.last;
      expect(newFile.path, isNot(oldFile.path));

      oldCurrent = false;
      oldWriteGate.complete();
      await oldExpired;
      expect(effects.cleanedFiles, [oldFile]);
      expect(effects.cleanedFiles, isNot(contains(newFile)));

      newWriteGate.complete();
      expect(await newPending, newFile.path);
      expect(effects.cleanedFiles, [oldFile]);
      expect(effects.sharedFiles, [newFile]);
      newCurrent = false;
    },
  );
}

const _stages = [
  'temporaryDirectory',
  'allocate',
  'write',
  'copyPath',
  'share',
];

List<String> _callsThrough(String stage) => switch (stage) {
  'temporaryDirectory' => ['temporaryDirectory'],
  'allocate' => ['temporaryDirectory', 'allocate', 'cleanup'],
  'write' => ['temporaryDirectory', 'allocate', 'write', 'cleanup'],
  'copyPath' => [
    'temporaryDirectory',
    'allocate',
    'write',
    'copyPath',
    'cleanup',
  ],
  'share' => ['temporaryDirectory', 'allocate', 'write', 'copyPath', 'share'],
  _ => throw ArgumentError.value(stage, 'stage'),
};

void _holdStage(
  _FakeEffects effects,
  String stage,
  Completer<void> gate, {
  Object? failure,
}) {
  Future<void> settle() async {
    await gate.future;
    if (failure != null) throw failure;
  }

  switch (stage) {
    case 'temporaryDirectory':
      effects.onTemporaryDirectory = () async {
        await settle();
        return '/temporary';
      };
      break;
    case 'allocate':
      effects.onAllocate = (directory) async {
        await settle();
        return effects.newFile(directory);
      };
      break;
    case 'write':
      effects.onWrite = (_, _) => settle();
      break;
    case 'copyPath':
      effects.onCopyPath = (_) => settle();
      break;
    case 'share':
      effects.onShare = (_, _, _) => settle();
      break;
    default:
      throw ArgumentError.value(stage, 'stage');
  }
}

Future<String> _export(
  _FakeEffects effects, {
  String csv = '\uFEFFliteral CSV',
  bool Function()? isCurrent,
  String Function()? shareText,
  String Function()? shareSubject,
}) => exportAdminFeedbackCsv(
  csv: csv,
  isCurrent: isCurrent ?? () => true,
  effects: effects,
  shareText: shareText ?? () => 'synthetic share text',
  shareSubject: shareSubject ?? () => 'synthetic share subject',
);

class _FakeEffects implements AdminFeedbackExportEffects {
  final List<String> calls = [];
  final List<AdminFeedbackExportFile> allocatedFiles = [];
  final List<AdminFeedbackExportFile> writtenFiles = [];
  final List<String> writtenCsv = [];
  final List<String> copiedPaths = [];
  final List<AdminFeedbackExportFile> sharedFiles = [];
  final List<String> sharedTexts = [];
  final List<String> sharedSubjects = [];
  final List<AdminFeedbackExportFile> cleanedFiles = [];
  final Map<String, List<Completer<void>>> _watchers = {};
  int _fileNumber = 0;

  Future<String> Function()? onTemporaryDirectory;
  Future<AdminFeedbackExportFile> Function(String directory)? onAllocate;
  Future<void> Function(AdminFeedbackExportFile file, String csv)? onWrite;
  Future<void> Function(String path)? onCopyPath;
  Future<void> Function(
    AdminFeedbackExportFile file,
    String text,
    String subject,
  )?
  onShare;
  Future<void> Function(AdminFeedbackExportFile file)? onCleanup;

  Completer<void> watchNext(String stage) {
    final completer = Completer<void>();
    _watchers.putIfAbsent(stage, () => []).add(completer);
    return completer;
  }

  AdminFeedbackExportFile newFile(String directory) {
    final id = ++_fileNumber;
    final ownedDirectory = '$directory/export_$id';
    return AdminFeedbackExportFile(
      directory: ownedDirectory,
      path: '$ownedDirectory/duoyi_feedback_$id.csv',
    );
  }

  void _enter(String stage) {
    calls.add(stage);
    final watchers = _watchers[stage];
    if (watchers != null && watchers.isNotEmpty) {
      final watcher = watchers.removeAt(0);
      if (!watcher.isCompleted) watcher.complete();
    }
  }

  @override
  Future<String> temporaryDirectory() async {
    _enter('temporaryDirectory');
    return onTemporaryDirectory == null
        ? '/temporary'
        : onTemporaryDirectory!();
  }

  @override
  Future<AdminFeedbackExportFile> allocate(String temporaryDirectory) async {
    _enter('allocate');
    final file = onAllocate == null
        ? newFile(temporaryDirectory)
        : await onAllocate!(temporaryDirectory);
    allocatedFiles.add(file);
    return file;
  }

  @override
  Future<void> write(AdminFeedbackExportFile file, String csv) async {
    _enter('write');
    writtenFiles.add(file);
    writtenCsv.add(csv);
    if (onWrite != null) await onWrite!(file, csv);
  }

  @override
  Future<void> copyPath(String path) async {
    _enter('copyPath');
    copiedPaths.add(path);
    if (onCopyPath != null) await onCopyPath!(path);
  }

  @override
  Future<void> share(
    AdminFeedbackExportFile file,
    String text,
    String subject,
  ) async {
    _enter('share');
    sharedFiles.add(file);
    sharedTexts.add(text);
    sharedSubjects.add(subject);
    if (onShare != null) await onShare!(file, text, subject);
  }

  @override
  Future<void> cleanup(AdminFeedbackExportFile file) async {
    _enter('cleanup');
    cleanedFiles.add(file);
    if (onCleanup != null) await onCleanup!(file);
  }
}
