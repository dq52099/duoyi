import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/services/account_local_data_cleaner.dart';
import 'package:duoyi/services/home_widget_service.dart';
import 'package:duoyi/services/widget_publication.dart';
import 'package:duoyi/services/widget_publication_client.dart';
import 'package:duoyi/services/widget_publication_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object> _values(int first) => {
  for (final key in WidgetPublication.valueKeys)
    key: HomeWidgetService.accountPayloadDefaults[key]!,
  'widget_first_day_of_week': first,
};

WidgetDevicePresentation _presentation(int first) => WidgetDevicePresentation(
  locale: AppLocale.zh,
  completeValues: _values(first),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('week start survives clearing and changes presentation equality', () {
    final sunday = _presentation(7);
    expect(sunday.clearedValues['widget_first_day_of_week'], 7);
    expect(sunday.clearedValues['todo_count'], 0);
    expect(sunday.sameAs(_presentation(1)), isFalse);
    expect(sunday.sameAs(_presentation(7)), isTrue);
    expect(sunday.document(revision: 3).values['widget_first_day_of_week'], 7);
  });

  test(
    'new constructors require week start; only old complete reads default',
    () {
      final document = _presentation(7).document(revision: 3).toJson();
      final old = Map<String, Object>.of(_values(7))
        ..remove('widget_first_day_of_week');
      final legacy = {
        ...document,
        'values': WidgetPublication.clearedValuesFrom(old),
      };
      expect(
        WidgetPublication.tryFromJson(
          legacy,
        )?.values['widget_first_day_of_week'],
        1,
      );
      expect(
        () =>
            WidgetDevicePresentation(locale: AppLocale.zh, completeValues: old),
        throwsFormatException,
      );
      for (final bad in [0, 8, -1, 7.0, '7', true, null]) {
        final values = <String, Object?>{
          ..._presentation(7).clearedValues,
          'widget_first_day_of_week': bad,
        };
        expect(
          WidgetPublication.tryFromJson({...document, 'values': values}),
          isNull,
        );
      }
      for (final values in [
        {...old, 'unknown': 1},
        Map<String, Object>.of(old)..remove('nav_calendar'),
        Map<String, Object>.of(_values(7))..remove('todo_count'),
      ]) {
        expect(
          WidgetPublication.tryFromJson({...document, 'values': values}),
          isNull,
        );
      }
    },
  );

  test(
    'Monday to Sunday to Monday permanently invalidates old capture',
    () async {
      const channel = MethodChannel('duoyi/widget_publication');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final store = _FakeStore();
      messenger.setMockMethodCallHandler(channel, store.handle);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final controller = WidgetPublicationController(
        client: WidgetPublicationClient(channel: channel),
      );
      controller.selectPresentation(_presentation(1));
      final opened = await controller.openWorkspace(
        ValidatedWidgetWorkspace(
          binding: WidgetWorkspaceBinding(kind: 'guest', key: 'local-device'),
          accountGeneration: AccountLocalDataCleaner.accountDataGeneration,
          isCurrent: () => true,
        ),
        forceReset: false,
      );
      expect(opened.storeCommitted, isTrue);
      expect(controller.ready, isTrue);
      final old = controller.capture(_values(1))!;
      controller.selectPresentation(_presentation(7));
      controller.selectPresentation(_presentation(1));
      expect((await controller.publish(old)).status, 'supersededContext');
      expect(store.publishes, 0);
      expect((await controller.advancePresentation()).storeCommitted, isTrue);
      final current = controller.capture(_values(1))!;
      expect(
        current.document.localeRevision,
        greaterThan(old.document.localeRevision),
      );
      expect((await controller.publish(current)).storeCommitted, isTrue);
      expect(store.document!.values['widget_first_day_of_week'], 1);
      expect(store.publishes, 1);
    },
  );
}

class _FakeStore {
  WidgetPublication? document;
  int revision = 0;
  int desired = 0;
  int publishes = 0;
  String operation = 'initial';
  Map? binding;

  Future<Object?> handle(MethodCall call) async {
    if (call.method == 'readWidgetStore') {
      if (document == null) return {'status': 'absent'};
      return {
        'status': 'ready',
        'storeRevision': revision,
        'binding': binding,
        'ownerEpoch': 'fixture-owner',
        'leaseState': 'active',
        'desiredPresentation': {'revision': desired, 'locale': 'zh'},
        'document': document!.toJson(),
        'lastOperationId': operation,
        'lastRequestDigest': List.filled(64, 'a').join(),
      };
    }
    final args = call.arguments as Map;
    operation = args['operationId'] as String;
    revision++;
    if (call.method == 'openWidgetWorkspace') {
      final p = args['presentation'] as Map;
      desired = p['revision'] as int;
      binding = args['binding'] as Map;
      document = WidgetPublication(
        ownerEpoch: 'fixture-owner',
        publicationRevision: 0,
        localeRevision: desired,
        state: WidgetPublicationState.cleared,
        locale: AppLocale.zh,
        snapshotDay: '',
        snapshotUtcOffsetMinutes: 0,
        capturedAtMillis: 0,
        values: Map<String, Object>.from(p['values'] as Map),
      );
    } else if (call.method == 'advanceDesiredWidgetPresentation') {
      desired = (args['desiredPresentation'] as Map)['revision'] as int;
    } else if (call.method == 'publishWidgetPublication') {
      document = WidgetPublication.tryFromJson(args['document'])!;
      publishes++;
    } else {
      throw StateError('Unexpected method ${call.method}');
    }
    return {
      'status': 'applied',
      'operationId': operation,
      'committedStoreRevision': revision,
      'ownerEpoch': 'fixture-owner',
      'publicationRevision': document!.publicationRevision,
      'desiredPresentationRevision': desired,
      'appliedPresentationRevision': document!.localeRevision,
      'documentState': document!.state.name,
      'refreshRequested': false,
      if (call.method == 'openWidgetWorkspace')
        'writerLeaseId': 'fixture-lease',
    };
  }
}
