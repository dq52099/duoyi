import 'package:duoyi/services/widget_link_dispatch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final host in ['event', 'pomodoro']) {
    final received = Uri.parse(
      'duoyi://$host/%20opaque%2Fid%20'
      '?source=widget&widget_day=2026-10-20&widget_offset=0&widget_account=owner&widget_delivery=tap',
    );
    test(
      '$host detail hydrates before binding and retains opaque receipt',
      () async {
        expect(WidgetLinkDispatch.requiresHydration(received), isTrue);
        expect(WidgetLinkDispatch.requiresBinding(received), isTrue);
        final calls = <String>[];
        final result = await WidgetLinkDispatch.resolve(
          received,
          hydrate: () async => calls.add('hydrate'),
          validate: (uri) async {
            calls.add('validate');
            expect(uri, received);
            return true;
          },
          isCurrent: () => true,
        );
        expect(calls, ['hydrate', 'validate']);
        expect(result.stale, isFalse);
        expect(result.uri!.pathSegments, [' opaque/id ']);
        expect(result.uri!.queryParameters['widget_delivery'], 'tap');
        expect(result.uri!.queryParameters['widget_account'], 'owner');
        expect(result.uri!.queryParameters['source'], isNull);
      },
    );
    test(
      '$host invalid binding returns its existing module without an ID',
      () async {
        final result = await WidgetLinkDispatch.resolve(
          received,
          hydrate: () async {},
          validate: (_) async => false,
          isCurrent: () => true,
        );
        expect(result.stale, isTrue);
        expect(
          result.uri,
          Uri.parse(host == 'event' ? 'duoyi://calendar' : 'duoyi://focus'),
        );
      },
    );
    for (final stage in ['hydrate', 'validate']) {
      test(
        '$host account changed during $stage drops the original navigation',
        () async {
          var current = true;
          final result = await WidgetLinkDispatch.resolve(
            received,
            hydrate: () async {
              if (stage == 'hydrate') current = false;
            },
            validate: (_) async {
              if (stage == 'validate') current = false;
              return true;
            },
            isCurrent: () => current,
          );
          expect(result.uri, isNull);
        },
      );
    }
  }
}
