import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _sectionBetween(String source, String startMarker, String endMarker) {
  final start = source.indexOf(startMarker);
  final end = source.indexOf(endMarker);
  expect(
    start,
    greaterThanOrEqualTo(0),
    reason: 'Missing required section start: $startMarker',
  );
  expect(
    end,
    greaterThanOrEqualTo(0),
    reason: 'Missing required section end: $endMarker',
  );
  expect(
    start,
    lessThan(end),
    reason: 'Section start must come before section end',
  );
  return source.substring(start, end);
}

void _expectCallBefore(String source, String firstCall, String secondCall) {
  final first = source.indexOf(firstCall);
  final second = source.indexOf(secondCall);
  expect(
    first,
    greaterThanOrEqualTo(0),
    reason: 'Missing required call: $firstCall',
  );
  expect(
    second,
    greaterThanOrEqualTo(0),
    reason: 'Missing required call: $secondCall',
  );
  expect(
    first,
    lessThan(second),
    reason: 'Expected $firstCall before $secondCall',
  );
}

void main() {
  final activity = File(
    'android/app/src/main/kotlin/com/duoyi/duoyi/MainActivity.kt',
  ).readAsStringSync();
  final bridge = File(
    'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetLaunchBridge.kt',
  ).readAsStringSync();
  final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
  final sceneDelegate = File(
    'ios/Runner/SceneDelegate.swift',
  ).readAsStringSync();

  test(
    'Android cold and warm Intents enter the app queue before plugin hooks',
    () {
      final cold = _sectionBetween(
        activity,
        'override fun onCreate',
        'override fun onResume',
      );
      final warm = _sectionBetween(
        activity,
        'override fun onNewIntent',
        'private fun scheduleWidgetRestoreAfterResume',
      );
      expect(cold, contains('savedInstanceState == null'));
      _expectCallBefore(
        cold,
        'DuoyiWidgetLaunchBridge.capture(intent)',
        'super.onCreate',
      );
      _expectCallBefore(
        warm,
        'setIntent(intent)',
        'DuoyiWidgetLaunchBridge.capture(intent)',
      );
      _expectCallBefore(
        warm,
        'DuoyiWidgetLaunchBridge.capture(intent)',
        'super.onNewIntent',
      );
      expect(
        activity,
        contains(
          'flutterEngine.plugins.has(DuoyiWidgetLaunchPlugin::class.java)',
        ),
      );
    },
  );

  test(
    'Android launch bridge validates URI shape and replaces transport keys',
    () {
      expect(bridge, contains('HOME_WIDGET_LAUNCH_ACTION'));
      expect(bridge, contains('!uri.isHierarchical'));
      expect(bridge, contains('uri.host !in supportedHosts'));
      expect(bridge, contains('uri.toString().length > 8192'));
      expect(bridge, contains('name == "source" || name == "widget_delivery"'));
      expect(bridge, contains('class DuoyiWidgetLaunchPlugin : FlutterPlugin'));
      expect(bridge, contains('override fun onDetachedFromEngine'));
      expect(bridge, contains('queue.snapshot().map { it.payload() }'));
      expect(bridge, contains('queue.acknowledge(id)'));
    },
  );

  test(
    'iOS configured scene owns each cold URL context without URI coalescing',
    () {
      expect(
        appDelegate,
        contains(
          'object(forInfoDictionaryKey: "UIApplicationSceneManifest") == nil',
        ),
      );
      expect(
        appDelegate,
        contains('DuoyiWidgetLaunchBridge.shared.handle(url: url)'),
      );
      expect(appDelegate, isNot(contains('initialLinks')));
      expect(
        sceneDelegate,
        contains('for context in connectionOptions.urlContexts'),
      );
      expect(sceneDelegate, contains('for context in URLContexts'));
      expect(sceneDelegate, isNot(contains('urlContexts.first')));
      expect(appDelegate, contains('self.channel === nextChannel'));
    },
  );
}
