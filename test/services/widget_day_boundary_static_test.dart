import 'dart:io';

import 'package:test/test.dart';

const _schedulerPath =
    'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetDayBoundaryScheduler.kt';
const _receiverPath =
    'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetDayBoundaryReceiver.kt';
const _registryPath =
    'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetVariantProviders.kt';
const _styledProviderPath =
    'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiStyledWidgetProvider.kt';
const _legacyProviderPath =
    'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetProvider.kt';
const _restoreReceiverPath =
    'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiWidgetRestoreReceiver.kt';
const _focusProviderPath =
    'android/app/src/main/kotlin/com/duoyi/duoyi/DuoyiFocusHabitWidgetProvider.kt';
const _manifestPath = 'android/app/src/main/AndroidManifest.xml';

String _readSource(String path) => File(path).readAsStringSync();

String _functionBody(String source, String signature) {
  final signatureIndex = source.indexOf(signature);
  expect(signatureIndex, greaterThanOrEqualTo(0), reason: 'Missing $signature');
  final openBrace = source.indexOf('{', signatureIndex);
  expect(
    openBrace,
    greaterThan(signatureIndex),
    reason: 'Missing body for $signature',
  );

  var depth = 0;
  for (var index = openBrace; index < source.length; index++) {
    final character = source[index];
    if (character == '{') depth++;
    if (character == '}') {
      depth--;
      if (depth == 0) return source.substring(openBrace, index + 1);
    }
  }
  throw StateError('Unclosed body for $signature');
}

String _sectionBetween(String source, String startMarker, String endMarker) {
  final start = source.indexOf(startMarker);
  expect(start, greaterThanOrEqualTo(0), reason: 'Missing $startMarker');
  final end = source.indexOf(endMarker, start + startMarker.length);
  expect(
    end,
    greaterThan(start),
    reason: 'Missing $endMarker after $startMarker',
  );
  return source.substring(start, end);
}

String _selfClosingReceiver(String manifest, String androidName) {
  final nameIndex = manifest.indexOf('android:name="$androidName"');
  expect(
    nameIndex,
    greaterThanOrEqualTo(0),
    reason: 'Missing receiver $androidName',
  );
  final start = manifest.lastIndexOf('<receiver', nameIndex);
  final end = manifest.indexOf('/>', nameIndex);
  expect(start, greaterThanOrEqualTo(0));
  expect(
    end,
    greaterThan(nameIndex),
    reason: '$androidName must be self-closing',
  );
  return manifest.substring(start, end + 2);
}

void _expectAbsent(String source, Iterable<String> fragments) {
  for (final fragment in fragments) {
    expect(source, isNot(contains(fragment)), reason: 'Unexpected $fragment');
  }
}

void main() {
  test('day-boundary alarm receiver is private and has no manifest filter', () {
    final manifest = _readSource(_manifestPath);
    final receiver = _selfClosingReceiver(
      manifest,
      '.DuoyiWidgetDayBoundaryReceiver',
    );

    expect(receiver, contains('android:exported="false"'));
    expect(receiver, contains('android:enabled="true"'));
    expect(receiver, isNot(contains('android:permission=')));
    expect(receiver, isNot(contains('<intent-filter')));
    expect(receiver, isNot(contains('android.intent.action.')));
  });

  test(
    'receiver accepts only its private action and performs no input-driven work',
    () {
      final receiver = _readSource(_receiverPath);
      final body = _functionBody(receiver, 'override fun onReceive(');

      const actionGuard =
          'if (intent.action != DuoyiWidgetDayBoundaryScheduler.action) return';
      expect(body, contains(actionGuard));
      expect(
        body.indexOf(actionGuard),
        lessThan(body.indexOf('requestUpdateForAllWidgets')),
      );
      expect(body.indexOf(actionGuard), lessThan(body.indexOf('invalidate()')));
      _expectAbsent(receiver, [
        'intent.extras',
        'getStringExtra(',
        'getIntExtra(',
        'getLongExtra(',
        'getParcelableExtra(',
        'putExtra(',
        'nonce',
        'account',
        'payload',
        'deepLink',
        'deeplink',
        'launch',
        'network',
        'Uri.parse(',
        'URL(',
        'java.net.',
        'Socket',
        'startActivity(',
        'startService(',
        'startForegroundService(',
        'HttpURLConnection',
        'OkHttpClient',
        'http://',
        'https://',
      ]);
    },
  );

  test('one immutable alarm identity is reused for create, lookup, and cancel', () {
    final scheduler = _readSource(_schedulerPath);
    final pendingIntent = _functionBody(
      scheduler,
      'private fun pendingIntent(create: Boolean)',
    );
    final schedule = _functionBody(scheduler, 'override fun schedule(');
    final cancel = _functionBody(scheduler, 'override fun cancel(');

    expect(
      scheduler,
      contains('const val action = "com.duoyi.duoyi.WIDGET_DAY_BOUNDARY"'),
    );
    expect(scheduler, contains('private const val requestCode = 14102'));
    expect(RegExp(r'14102').allMatches(scheduler).length, 1);
    expect(
      scheduler,
      contains('Intent(context, DuoyiWidgetDayBoundaryReceiver::class.java)'),
    );
    expect(scheduler, contains('FLAG_IMMUTABLE'));
    expect(scheduler, contains('FLAG_UPDATE_CURRENT'));
    expect(scheduler, contains('FLAG_NO_CREATE'));
    expect(
      pendingIntent,
      contains('action = DuoyiWidgetDayBoundaryScheduler.action'),
    );
    expect(
      pendingIntent,
      contains(
        'if (create) PendingIntent.FLAG_UPDATE_CURRENT else PendingIntent.FLAG_NO_CREATE',
      ),
    );
    expect(
      pendingIntent,
      contains(
        'PendingIntent.getBroadcast(context, requestCode, intent, lookup or mutability)',
      ),
    );
    expect(schedule, contains('pendingIntent(create = true)'));
    expect(cancel, contains('pendingIntent(create = false)'));
    expect(cancel, contains('alarmManager.cancel(pending)'));
    expect(cancel, contains('pending.cancel()'));

    final focusProvider = _readSource(_focusProviderPath);
    expect(
      focusProvider,
      contains('PendingIntent.getBroadcast(context, 14101'),
    );
    expect(focusProvider, contains('timerFinishedAction'));
    expect(focusProvider, contains('setExactAndAllowWhileIdle'));
    expect(scheduler, isNot(contains('14101')));
    expect(focusProvider, isNot(contains('14102')));
    expect(scheduler, isNot(contains('FLAG_MUTABLE')));
    _expectAbsent(scheduler, [
      'intent.extras',
      'getStringExtra(',
      'putExtra(',
      'nonce',
      'account',
      'payload',
      'deepLink',
      'deeplink',
      'launch',
      'network',
      'java.net.',
      'Socket',
      'URL(',
      'startActivity(',
      'startService(',
      'HttpURLConnection',
      'OkHttpClient',
      'http://',
      'https://',
    ]);
  });

  test(
    'day scheduler uses only inexact APIs and requests no exact-alarm permission',
    () {
      final scheduler = _readSource(_schedulerPath);
      final receiver = _readSource(_receiverPath);

      expect(
        scheduler,
        contains(
          'alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, atMillis, pending)',
        ),
      );
      expect(
        scheduler,
        contains(
          'alarmManager.set(AlarmManager.RTC_WAKEUP, atMillis, pending)',
        ),
      );
      _expectAbsent(scheduler, [
        'setExact(',
        'setExactAndAllowWhileIdle(',
        'canScheduleExactAlarms(',
        'SCHEDULE_EXACT_ALARM',
        'USE_EXACT_ALARM',
      ]);
      _expectAbsent(receiver, ['SCHEDULE_EXACT_ALARM', 'USE_EXACT_ALARM']);
    },
  );

  test(
    'registry inventory is based on real widget ids for every family and legacy provider',
    () {
      final registry = _readSource(_registryPath);
      final families = _sectionBetween(
        registry,
        'private val widgetFamilies = listOf(',
        'private val legacyProviderClasses',
      );
      final legacy = _sectionBetween(
        registry,
        'private val legacyProviderClasses',
        'private fun allWidgetProviderClasses',
      );
      final allProviders = _functionBody(
        registry,
        'private fun allWidgetProviderClasses()',
      );
      final installedCount = _functionBody(
        registry,
        'fun installedWidgetCount(',
      );

      expect(RegExp(r'WidgetFamily\(').allMatches(families).length, 10);
      const familyProviderNames = <String, List<String>>{
        'todo': [
          'DuoyiTodoWidgetProvider',
          'DuoyiTodoCompactWidgetProvider',
          'DuoyiTodoDetailedWidgetProvider',
        ],
        'focus': [
          'DuoyiFocusHabitWidgetProvider',
          'DuoyiFocusHabitCompactWidgetProvider',
          'DuoyiFocusHabitDetailedWidgetProvider',
        ],
        'habit': [
          'DuoyiHabitWidgetProvider',
          'DuoyiHabitCompactWidgetProvider',
          'DuoyiHabitDetailedWidgetProvider',
        ],
        'calendar': [
          'DuoyiCalendarWidgetProvider',
          'DuoyiCalendarCompactWidgetProvider',
          'DuoyiCalendarDetailedWidgetProvider',
        ],
        'schedule': [
          'DuoyiScheduleWidgetProvider',
          'DuoyiScheduleCompactWidgetProvider',
          'DuoyiScheduleDetailedWidgetProvider',
        ],
        'goal': [
          'DuoyiGoalWidgetProvider',
          'DuoyiGoalCompactWidgetProvider',
          'DuoyiGoalDetailedWidgetProvider',
        ],
        'course': [
          'DuoyiCourseWidgetProvider',
          'DuoyiCourseCompactWidgetProvider',
          'DuoyiCourseDetailedWidgetProvider',
        ],
        'note': [
          'DuoyiNoteWidgetProvider',
          'DuoyiNoteCompactWidgetProvider',
          'DuoyiNoteDetailedWidgetProvider',
        ],
        'anniversary': [
          'DuoyiAnniversaryWidgetProvider',
          'DuoyiAnniversaryCompactWidgetProvider',
          'DuoyiAnniversaryDetailedWidgetProvider',
        ],
        'diary': [
          'DuoyiDiaryWidgetProvider',
          'DuoyiDiaryCompactWidgetProvider',
          'DuoyiDiaryDetailedWidgetProvider',
        ],
      };
      for (final entry in familyProviderNames.entries) {
        expect(families, contains('"${entry.key}"'));
        for (final provider in entry.value) {
          expect(families, contains('$provider::class.java'));
        }
      }
      expect(legacy, contains('DuoyiWidgetProvider::class.java'));
      expect(
        allProviders,
        contains(
          'legacyProviderClasses + widgetFamilies.flatMap { it.providerClasses }',
        ),
      );
      expect(installedCount, contains('AppWidgetManager.getInstance(context)'));
      expect(installedCount, contains('allWidgetProviderClasses().sumOf'));
      expect(
        installedCount,
        contains(
          'manager.getAppWidgetIds(ComponentName(context, providerClass)).size',
        ),
      );
      _expectAbsent(installedCount, [
        'activeVariantProviderComponents',
        'pendingVariantProvidersKey',
        'activeVariantProvidersKey',
        'isActiveVariantProvider',
      ]);
    },
  );

  test(
    'styled and legacy providers reconcile widget lifecycle actions in finally',
    () {
      final scheduler = _readSource(_schedulerPath);
      final lifecycleAllowlist = _sectionBetween(
        scheduler,
        'fun isWidgetLifecycleAction(',
        '@Synchronized',
      );
      final styled = _functionBody(
        _readSource(_styledProviderPath),
        'override fun onReceive(',
      );
      final legacy = _functionBody(
        _readSource(_legacyProviderPath),
        'override fun onReceive(',
      );

      for (final action in [
        'ACTION_APPWIDGET_ENABLED',
        'ACTION_APPWIDGET_UPDATE',
        'ACTION_APPWIDGET_OPTIONS_CHANGED',
        'ACTION_APPWIDGET_RESTORED',
        'ACTION_APPWIDGET_DELETED',
        'ACTION_APPWIDGET_DISABLED',
      ]) {
        expect(lifecycleAllowlist, contains(action));
      }

      for (final providerBody in [styled, legacy]) {
        expect(providerBody, contains('try {'));
        expect(providerBody, contains('super.onReceive(context, intent)'));
        expect(providerBody, contains('finally {'));
        expect(
          providerBody,
          contains(
            'DuoyiWidgetDayBoundaryScheduler.isWidgetLifecycleAction(intent.action)',
          ),
        );
        expect(
          providerBody,
          contains('DuoyiWidgetDayBoundaryScheduler.reconcile(context)'),
        );
        expect(
          providerBody.indexOf('finally {'),
          lessThan(
            providerBody.indexOf(
              'DuoyiWidgetDayBoundaryScheduler.reconcile(context)',
            ),
          ),
        );
      }
    },
  );

  test(
    'registry update and restore paths reconcile, with restore forcing rearm',
    () {
      final registry = _readSource(_registryPath);
      final requestUpdate = _functionBody(
        registry,
        'private fun requestUpdateComponents(',
      );
      final restore = _functionBody(
        registry,
        'fun restoreEnabledProvidersForExistingWidgets(',
      );

      expect(requestUpdate, contains('try {'));
      expect(requestUpdate, contains('manager.getAppWidgetIds(component)'));
      expect(requestUpdate, contains('context.sendBroadcast(intent)'));
      expect(requestUpdate, contains('finally {'));
      expect(
        requestUpdate,
        contains('DuoyiWidgetDayBoundaryScheduler.reconcile(context)'),
      );
      expect(
        requestUpdate.indexOf('finally {'),
        lessThan(
          requestUpdate.indexOf(
            'DuoyiWidgetDayBoundaryScheduler.reconcile(context)',
          ),
        ),
      );
      expect(
        restore,
        contains(
          'DuoyiWidgetDayBoundaryScheduler.reconcile(context, force = true)',
        ),
      );
      expect(
        restore.indexOf('if (restoredCount > 0)'),
        lessThan(
          restore.indexOf(
            'DuoyiWidgetDayBoundaryScheduler.reconcile(context, force = true)',
          ),
        ),
      );
      expect(
        restore.indexOf(
          'DuoyiWidgetDayBoundaryScheduler.reconcile(context, force = true)',
        ),
        lessThan(restore.indexOf('return restoredCount')),
      );
    },
  );

  test(
    'system restore receiver rearms after restore and update even when work fails',
    () {
      final restoreReceiver = _functionBody(
        _readSource(_restoreReceiverPath),
        'override fun onReceive(',
      );

      expect(restoreReceiver, contains('supportedActions'));
      expect(
        restoreReceiver,
        contains('DuoyiWidgetDayBoundaryScheduler.invalidate()'),
      );
      expect(
        restoreReceiver,
        contains('restoreEnabledProvidersForExistingWidgets(appContext)'),
      );
      expect(
        restoreReceiver,
        contains('requestUpdateForAllWidgets(appContext)'),
      );
      expect(restoreReceiver, contains('finally {'));
      expect(
        restoreReceiver,
        contains('DuoyiWidgetDayBoundaryScheduler.reconcile(appContext)'),
      );
      expect(
        restoreReceiver.indexOf('finally {'),
        lessThan(
          restoreReceiver.indexOf(
            'DuoyiWidgetDayBoundaryScheduler.reconcile(appContext)',
          ),
        ),
      );

      final source = _readSource(_restoreReceiverPath);
      expect(source, isNot(contains('DuoyiWidgetDayBoundaryScheduler.action')));
    },
  );

  test(
    'alarm receiver catches dispatch failure and always reconciles in finally',
    () {
      final body = _functionBody(
        _readSource(_receiverPath),
        'override fun onReceive(',
      );
      final dispatch = body.indexOf('requestUpdateForAllWidgets(appContext)');
      final catchBlock = body.indexOf('catch (error: RuntimeException)');
      final finallyBlock = body.indexOf('finally {');
      final reconcile = body.indexOf(
        'DuoyiWidgetDayBoundaryScheduler.reconcile(appContext)',
      );

      expect(body, contains('DuoyiWidgetDayBoundaryScheduler.invalidate()'));
      expect(dispatch, greaterThanOrEqualTo(0));
      expect(catchBlock, greaterThan(dispatch));
      expect(finallyBlock, greaterThan(catchBlock));
      expect(reconcile, greaterThan(finallyBlock));
    },
  );

  test(
    'scheduler and receiver do not write widget publication or account state',
    () {
      final scheduler = _readSource(_schedulerPath);
      final receiver = _readSource(_receiverPath);
      const publicationWrites = [
        'SharedPreferences',
        'HomeWidgetPlugin',
        'DuoyiWidgetSnapshot',
        'saveWidgetData',
        'widget_snapshot_day',
        'widget_account_nonce',
        'account_nonce',
        'putString(',
        'putInt(',
        'putLong(',
        'putBoolean(',
        'putStringSet(',
        '.edit()',
      ];

      _expectAbsent(scheduler, publicationWrites);
      _expectAbsent(receiver, publicationWrites);
    },
  );
}
