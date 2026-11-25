import 'dart:async';

import 'package:duoyi/services/shared_text_import_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'locked receipt opens one confirmation after unlock without writing',
    () async {
      final f = _Fixture()..blocked = true;
      f.queue.receive('  original text  ');
      await f.queue.drain();
      expect(f.opened, isEmpty);
      f.blocked = false;
      await f.queue.drain();
      expect(f.opened.single.text, 'original text');
      expect(f.writes, 0);
      await f.queue.drain();
      expect(f.opened, hasLength(1));
    },
  );

  test('account change before dispatch discards the old receipt', () async {
    final f = _Fixture();
    f.queue.receive('old account');
    f.generation++;
    f.queue.receive('new account');
    await f.queue.drain();
    expect(f.opened.map((r) => r.text), ['new account']);
  });

  test(
    'native read remains bound to its account before the asynchronous read',
    () async {
      final f = _Fixture();
      final origin = f.generation;
      f.generation++;
      f.queue.receive(
        'late native response',
        receivedAccountGeneration: origin,
      );
      await f.queue.drain();
      expect(f.opened, isEmpty);
    },
  );

  test('held confirmation rejects a same ID new session', () async {
    final f = _Fixture();
    final confirmation = Completer<void>();
    f.action = (request) async {
      await confirmation.future;
      if (request.canProceed) f.writes++;
    };
    f.queue.receive('draft');
    final running = f.queue.drain();
    f.generation++;
    confirmation.complete();
    await running;
    expect(f.writes, 0);
    expect(f.opened.single.canProceed, isFalse);
  });

  test(
    'lock during permission wait reopens the original choice and never auto imports',
    () async {
      final f = _Fixture();
      final permission = Completer<void>();
      f.action = (request) async {
        await permission.future;
        if (!request.canProceed) {
          request.defer();
          request.defer();
          return;
        }
        f.writes++;
      };
      f.queue.receive('draft to confirm again');
      final running = f.queue.drain();
      f.blocked = true;
      permission.complete();
      await running;
      expect(f.writes, 0);
      f.blocked = false;
      f.action = (_) async {};
      await f.queue.drain();
      expect(f.opened, hasLength(2));
      expect(f.opened.first, same(f.opened.last));
      expect(f.writes, 0);
    },
  );

  test('accepted write cannot be replayed by a later lock', () async {
    final f = _Fixture();
    f.action = (request) async {
      request.markActionStarted();
      f.writes++;
      f.blocked = true;
      request.defer();
    };
    f.queue.receive('write once');
    await f.queue.drain();
    f.blocked = false;
    await f.queue.drain();
    expect(f.writes, 1);
    expect(f.opened, hasLength(1));
  });

  test('shares serialize while the current sheet is open', () async {
    final f = _Fixture();
    final firstSheet = Completer<void>();
    f.action = (request) async {
      if (request.text == 'first') await firstSheet.future;
    };
    f.queue.receive('first');
    f.queue.receive('second');
    final running = f.queue.drain();
    await f.queue.drain();
    expect(f.opened.map((r) => r.text), ['first']);
    firstSheet.complete();
    await running;
    expect(f.opened.map((r) => r.text), ['first', 'second']);
  });

  test('a failed sheet does not block the next share', () async {
    final f = _Fixture();
    f.action = (request) async {
      if (request.text == 'first') throw StateError('sheet failed');
    };
    f.queue.receive('first');
    f.queue.receive('second');
    await f.queue.drain();
    expect(f.errors, hasLength(1));
    expect(f.opened.map((r) => r.text), ['first', 'second']);
  });

  test('explicit retry retains note identity and cannot queue twice', () async {
    final f = _Fixture();
    f.queue.receive('literal shared draft');
    await f.queue.drain();
    final original = f.opened.single;
    original.markActionStarted();
    expect(original.canDeliverFeedback, isTrue);
    expect(original.retry(), isTrue);
    expect(original.retry(), isFalse);
    await f.queue.drain();
    expect(f.opened, hasLength(2));
    expect(f.opened.last.noteId, original.noteId);
    expect(f.opened.last.text, original.text);
    expect(f.opened.last.canProceed, isFalse);
  });

  test(
    'retained retry rejects lock and old account without losing eligibility',
    () async {
      final f = _Fixture();
      f.queue.receive('draft');
      await f.queue.drain();
      final original = f.opened.single;
      f.blocked = true;
      expect(original.retry(), isFalse);
      f.blocked = false;
      f.generation++;
      expect(original.retry(), isFalse);
      await f.queue.drain();
      expect(f.opened, hasLength(1));
    },
  );
}

class _Fixture {
  int generation = 1;
  bool blocked = false;
  int writes = 0;
  final opened = <SharedTextImportRequest>[];
  final errors = <Object>[];
  Future<void> Function(SharedTextImportRequest)? action;
  late final queue = SharedTextImportQueue(
    accountGeneration: () => generation,
    isBlocked: () => blocked,
    isReady: () => true,
    open: (request) async {
      opened.add(request);
      await action?.call(request);
    },
    onError: (error, _) => errors.add(error),
  );
}
