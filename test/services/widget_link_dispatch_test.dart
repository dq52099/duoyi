import 'package:duoyi/services/widget_link_dispatch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WidgetLinkDispatch binding policy', () {
    test(
      'legacy unbound entity link keeps its ID and bypasses validation',
      () async {
        final uri = Uri.parse('duoyi://todo/legacy-task?confirm=1');
        var validations = 0;

        final result = await WidgetLinkDispatch.resolve(
          uri,
          hydrate: () async {},
          validate: (_) async {
            validations++;
            return false;
          },
          isCurrent: () => true,
        );

        expect(result.uri, uri);
        expect(result.stale, isFalse);
        expect(validations, 0);
      },
    );

    test(
      'stale bound entity link falls back to its section without the ID',
      () async {
        final uri = Uri.parse(
          'duoyi://todo/currently-stale?source=widget&widget_delivery=d-1',
        );
        var validatedUri = Uri();

        final result = await WidgetLinkDispatch.resolve(
          uri,
          hydrate: () async {},
          validate: (value) async {
            validatedUri = value;
            return false;
          },
          isCurrent: () => true,
        );

        expect(validatedUri, uri);
        expect(result.uri, Uri.parse('duoyi://todo'));
        expect(result.stale, isTrue);
      },
    );

    test(
      'source-marked cached links without snapshot fields fall back for every entity section',
      () async {
        for (final host in WidgetLinkDispatch.entityHosts) {
          final uri = Uri(
            scheme: 'duoyi',
            host: host,
            path: '/cached-id',
            queryParameters: {
              'source': 'widget',
              'widget_delivery': 'cached-$host',
            },
          );
          var validationCalls = 0;
          Uri? validated;

          final result = await WidgetLinkDispatch.resolve(
            uri,
            hydrate: () async {},
            validate: (value) async {
              validationCalls++;
              validated = value;
              return false;
            },
            isCurrent: () => true,
          );

          expect(validationCalls, 1, reason: host);
          expect(validated, uri, reason: host);
          expect(
            result.uri,
            Uri(scheme: 'duoyi', host: host),
            reason: host,
          );
          expect(result.stale, isTrue, reason: host);
        }
      },
    );

    test('stale mutating action is rejected', () async {
      final uri = Uri.parse(
        'duoyi://action/complete_todo?id=task&source=widget&widget_day=old',
      );
      var validations = 0;

      final result = await WidgetLinkDispatch.resolve(
        uri,
        hydrate: () async {},
        validate: (_) async {
          validations++;
          return false;
        },
        isCurrent: () => true,
      );

      expect(validations, 1);
      expect(result.uri, isNull);
      expect(result.stale, isTrue);
    });

    test(
      'valid bound action removes source and preserves delivery identity',
      () async {
        final uri = Uri.parse(
          'duoyi://action/checkin_habit?id=habit&source=widget&widget_delivery=tap-7',
        );

        final result = await WidgetLinkDispatch.resolve(
          uri,
          hydrate: () async {},
          validate: (_) async => true,
          isCurrent: () => true,
        );

        expect(result.stale, isFalse);
        expect(result.uri!.queryParameters['source'], isNull);
        expect(result.uri!.queryParameters['widget_delivery'], 'tap-7');
        expect(result.uri!.queryParameters['id'], 'habit');
      },
    );

    test(
      'recoverable widget actions do not require a snapshot binding',
      () async {
        final refresh = Uri.parse(
          'duoyi://action/refresh_widgets?source=widget&widget_delivery=refresh-1',
        );
        final quickTodo = Uri.parse(
          'duoyi://action/quick_todo?source=widget&widget_delivery=quick-1',
        );
        var validations = 0;

        for (final uri in [refresh, quickTodo]) {
          final result = await WidgetLinkDispatch.resolve(
            uri,
            hydrate: () async {},
            validate: (_) async {
              validations++;
              return false;
            },
            isCurrent: () => true,
          );
          expect(result.uri, uri);
          expect(result.stale, isFalse);
        }
        expect(validations, 0);
      },
    );

    test('quick todo with text remains bound and is validated', () async {
      final uri = Uri.parse(
        'duoyi://action/quick_todo?text=write%20a%20task&source=widget&widget_delivery=quick-text-1',
      );
      var validations = 0;

      final result = await WidgetLinkDispatch.resolve(
        uri,
        hydrate: () async {},
        validate: (_) async {
          validations++;
          return true;
        },
        isCurrent: () => true,
      );

      expect(validations, 1);
      expect(result.uri!.queryParameters['source'], isNull);
      expect(result.uri!.queryParameters['text'], 'write a task');
      expect(result.uri!.queryParameters['widget_delivery'], 'quick-text-1');
    });

    test(
      'plain external links remain outside hydration and binding policy',
      () async {
        final uri = Uri.parse('https://example.test/reminder?id=original');
        var validations = 0;

        expect(WidgetLinkDispatch.requiresHydration(uri), isFalse);
        expect(WidgetLinkDispatch.requiresBinding(uri), isFalse);
        final result = await WidgetLinkDispatch.resolve(
          uri,
          hydrate: () async {},
          validate: (_) async {
            validations++;
            return false;
          },
          isCurrent: () => true,
        );

        expect(result.uri, uri);
        expect(result.stale, isFalse);
        expect(validations, 0);
      },
    );

    test('account generation change during hydration drops the link', () async {
      final uri = Uri.parse(
        'duoyi://note/n-1?source=widget&widget_delivery=note-1',
      );
      var current = true;
      var validations = 0;

      final result = await WidgetLinkDispatch.resolve(
        uri,
        hydrate: () async {
          current = false;
        },
        validate: (_) async {
          validations++;
          return true;
        },
        isCurrent: () => current,
      );

      expect(result.uri, isNull);
      expect(result.stale, isFalse);
      expect(validations, 0);
    });

    test(
      'account generation change during validation drops the link',
      () async {
        final uri = Uri.parse(
          'duoyi://action/start_pomodoro?source=widget&widget_day=today',
        );
        var current = true;

        final result = await WidgetLinkDispatch.resolve(
          uri,
          hydrate: () async {},
          validate: (_) async {
            current = false;
            return true;
          },
          isCurrent: () => current,
        );

        expect(result.uri, isNull);
        expect(result.stale, isFalse);
      },
    );
  });
}
