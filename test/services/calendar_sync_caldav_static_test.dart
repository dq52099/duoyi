import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('日历集成暴露 CalDAV 写回配置和测试链路', () {
    final service = File(
      'lib/services/calendar_sync_service.dart',
    ).readAsStringSync();
    final screen = File(
      'lib/screens/integrations_screen.dart',
    ).readAsStringSync();
    final copy = File('lib/core/notification_ui_copy.dart').readAsStringSync();
    final exportScreen = File(
      'lib/screens/export_screen.dart',
    ).readAsStringSync();

    expect(service, contains('class CalDavWriteTarget'));
    expect(service, contains('enum CalDavConflictPolicy'));
    expect(service, contains('class CalDavWriteConflict'));
    expect(service, contains('_calDavPushedEtagsKey'));
    expect(service, contains('writer.remoteEtag(uid)'));
    expect(service, contains('CalDavConflictPolicy.skipRemoteChanges'));
    expect(service, contains('lastCalDavConflicts'));
    expect(service, contains('saveWriteTarget'));
    expect(service, contains('clearWriteTarget'));
    expect(service, contains('testWriteTarget'));
    expect(service, contains('HttpCalDavWriter'));
    expect(service, contains('多仪 CalDAV 写回测试'));
    expect(service, contains('writer.deleteEvent(uid)'));
    expect(service, contains('class CalDavCredentialHelper'));
    expect(service, contains('iCloudCollectionUrlHint'));
    expect(service, contains('iCloudSetupCopy'));
    expect(service, contains('basicAuthorizationHeader'));
    expect(
      service,
      contains("return 'Basic \${base64Encode(utf8.encode(raw))}'"),
    );
    expect(screen, contains('NotificationUiCopy.calDavTargetTitle'));
    expect(copy, contains('CalDAV 写回目标'));
    expect(screen, contains('NotificationUiCopy.authHeaderLabel'));
    expect(copy, contains('Authorization header'));
    expect(screen, contains('NotificationUiCopy.calDavTestWriteback'));
    expect(copy, contains('测试写回'));
    expect(screen, contains('_CalDavWriteTargetCard'));
    expect(screen, contains('_showICloudCalDavDialog'));
    expect(screen, contains('NotificationUiCopy.iCloudDialogTitle'));
    expect(copy, contains('配置 iCloud 日历写回'));
    expect(screen, contains('Apple ID'));
    expect(screen, contains('NotificationUiCopy.appSpecificPasswordLabel'));
    expect(copy, contains('App 专用密码'));
    expect(screen, contains('CalDavCredentialHelper.basicAuthorizationHeader'));
    expect(screen, contains('NotificationUiCopy.oauthCardTitle'));
    expect(service, contains('pushEventsToCalDav'));
    expect(service, contains('_calDavUidFor'));
    expect(service, contains('_calDavPushedUidsKey'));
    expect(service, contains('previousUids.difference(currentUids)'));
    expect(service, contains('await writer.deleteEvent('));
    expect(service, contains('staleUid,'));
    expect(screen, contains('NotificationUiCopy.conflictPolicyLabel'));
    expect(copy, contains('远端冲突处理'));
    expect(screen, contains('NotificationUiCopy.conflictPolicySkipItem'));
    expect(copy, contains('跳过远端已修改事件'));
    expect(exportScreen, contains('export.caldav.conflict.middle'));
    expect(exportScreen, contains('export.caldav.conflict.suffix'));
    expect(exportScreen, contains('export.push_caldav'));
    expect(exportScreen, contains('pushEventsToCalDav'));
  });

  test('CalDAV HTTP 写回使用 ETag 防止覆盖远端改动', () {
    final writer = File('lib/services/caldav_writer.dart').readAsStringSync();

    expect(writer, contains('Future<String?> remoteEtag(String uid)'));
    expect(writer, contains('client.head'));
    expect(writer, contains('resp.statusCode == 405'));
    expect(writer, contains('client.get'));
    expect(writer, contains("_requestHeaders"));
    expect(writer, contains("out['If-Match'] = ifMatch"));
    expect(writer, contains('resp.statusCode == 412'));
    expect(writer, contains('class CalDavConflictException'));
  });

  test('Google 和 Outlook OAuth 日历暴露授权、刷新和事件拉取链路', () {
    final service = File(
      'lib/services/calendar_sync_service.dart',
    ).readAsStringSync();
    final storage = File(
      'lib/core/oauth_calendar_storage.dart',
    ).readAsStringSync();
    final screen = File(
      'lib/screens/integrations_screen.dart',
    ).readAsStringSync();
    final copy = File('lib/core/notification_ui_copy.dart').readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();
    final deepLinkService = File(
      'lib/services/deep_link_service.dart',
    ).readAsStringSync();
    final mainActivity = File(
      'android/app/src/main/kotlin/com/duoyi/duoyi/MainActivity.kt',
    ).readAsStringSync();
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final sceneDelegate = File(
      'ios/Runner/SceneDelegate.swift',
    ).readAsStringSync();

    expect(service, contains('enum OAuthCalendarProvider'));
    expect(service, contains('class OAuthCalendarAccount'));
    expect(service, contains('class OAuthCalendarClient'));
    expect(service, contains('generateCodeVerifier'));
    expect(service, contains('code_challenge_method'));
    expect(service, contains("params['state'] = state"));
    expect(service, contains('authorizationUri'));
    expect(service, contains('exchangeAuthorizationCode'));
    expect(service, contains('refreshAccessToken'));
    expect(service, contains('addOAuthAccountFromCode'));
    expect(service, contains("import '../core/oauth_calendar_storage.dart';"));
    expect(
      _missingOAuthStorageBindings(storage, service),
      isEmpty,
      reason: 'Each exact persisted OAuth key needs its declaration and service alias.',
    );
    expect(service, contains('savePendingOAuthAuthorization'));
    expect(service, contains("'state': state"));
    expect(service, contains('loadPendingOAuthAuthorization'));
    expect(service, contains('clearPendingOAuthAuthorization'));
    expect(service, contains('oauthAccounts'));
    expect(service, contains('allEvents()'));
    expect(service, contains('www.googleapis.com'));
    expect(service, contains('graph.microsoft.com'));
    expect(service, contains('calendarView'));
    expect(service, contains('outlook.timezone="UTC"'));
    expect(service, contains('_googleEventToCalendarEvent'));
    expect(service, contains('_outlookEventToCalendarEvent'));
    expect(service, contains('_parseOAuthDateTime'));
    expect(service, contains('pathSegments'));
    expect(service, contains("id.startsWith('ics_')"));
    expect(service, contains("id.startsWith('oauth_')"));
    expect(service, contains('isExternalCalendarEvent ? null'));
    expect(service, isNot(contains('sourceId: eventId')));
    expect(service, isNot(contains('sourceId: uid')));

    expect(screen, contains('NotificationUiCopy.oauthCardTitle'));
    expect(copy, contains('Google / Outlook OAuth 日历'));
    expect(screen, contains('initialOAuthCallbackUri'));
    expect(screen, contains('_OAuthCalendarCard'));
    expect(screen, contains('_OAuthCalendarTile'));
    expect(screen, contains('showOAuthDialog'));
    expect(screen, contains('callbackUri'));
    expect(screen, contains('OAuthCalendarProvider.values'));
    expect(screen, contains('OAuthCalendarClient.generateCodeVerifier'));
    expect(screen, contains('buildOAuthAuthorizationUri'));
    expect(screen, contains('oauthState'));
    expect(screen, contains("callbackUri.queryParameters['state']"));
    expect(screen, contains('NotificationUiCopy.oauthStateMismatch'));
    expect(copy, contains('OAuth 回调 state 不匹配，请重新授权'));
    expect(screen, contains('state: oauthState'));
    expect(screen, contains('loadPendingOAuthAuthorization'));
    expect(screen, contains('savePendingOAuthAuthorization'));
    expect(screen, contains('clearPendingOAuthAuthorization'));
    expect(screen, contains('duoyi://oauth/calendar'));
    expect(screen, contains('NotificationUiCopy.authUrlSectionTitle'));
    expect(copy, contains('授权链接'));
    expect(screen, contains('Client ID'));
    expect(screen, contains('NotificationUiCopy.clientSecretOptionalLabel'));
    expect(copy, contains('Client Secret（可选）'));
    expect(screen, contains('NotificationUiCopy.authCodeLabel'));
    expect(copy, contains('授权码或回调 URL'));
    expect(screen, contains('addOAuthAccountFromCode'));
    expect(screen, contains('updateOAuthAccount'));
    expect(screen, contains('removeOAuthAccount'));

    expect(deepLinkService, contains("MethodChannel('duoyi/deep_links')"));
    expect(deepLinkService, contains('takeInitialLink'));
    expect(deepLinkService, contains('takeInitialOAuthLink'));
    expect(deepLinkService, contains("call.method != 'onLink'"));
    expect(deepLinkService, contains("uri.scheme == 'duoyi'"));
    expect(deepLinkService, contains('_isDuoyiDeepLink(uri)'));
    expect(deepLinkService, contains("uri.host == 'oauth'"));
    expect(mainActivity, contains('deepLinksChannel = "duoyi/deep_links"'));
    expect(mainActivity, contains('pendingInitialDeepLink'));
    expect(mainActivity, contains('pendingInitialOAuthLink'));
    expect(mainActivity, contains('duoyiDeepLinkFrom(intent)'));
    expect(mainActivity, contains('oauthDeepLinkFrom(intent)'));
    expect(mainActivity, contains('"takeInitialLink"'));
    expect(mainActivity, contains('"takeInitialOAuthLink"'));
    expect(mainActivity, contains('channel.invokeMethod("onLink", deepLink)'));
    expect(mainActivity, contains('uri.scheme != "duoyi"'));
    expect(mainActivity, contains('uri.host != "oauth"'));
    expect(appDelegate, contains('final class DuoyiDeepLinkBridge'));
    expect(appDelegate, contains('"duoyi/deep_links"'));
    expect(appDelegate, contains('case "takeInitialLink"'));
    expect(appDelegate, contains('case "takeInitialOAuthLink"'));
    expect(appDelegate, contains('channel?.invokeMethod("onLink"'));
    expect(appDelegate, contains('url.host == "oauth"'));
    expect(sceneDelegate, contains('openURLContexts URLContexts'));
    expect(
      sceneDelegate,
      contains('for context in connectionOptions.urlContexts {'),
    );
    expect(
      sceneDelegate,
      contains(
        'DuoyiDeepLinkBridge.shared.handle(url: context.url, initial: true)',
      ),
    );
    expect(sceneDelegate, contains('for context in URLContexts {'));
    expect(
      sceneDelegate,
      contains('super.scene(scene, openURLContexts: URLContexts)'),
    );
    expect(main, contains("import 'services/deep_link_service.dart';"));
    expect(main, contains("import 'screens/integrations_screen.dart';"));
    expect(main, contains('DeepLinkService.onLink = handleDeepLink'));
    expect(main, contains("DeepLinkService.init()"));
    expect(main, contains('DeepLinkService.takeInitialLink()'));
    expect(main, contains('DeepLinkService.takeInitialOAuthLink()'));
    expect(main, contains("uri.host == 'oauth'"));
    expect(main, contains('IntegrationsScreen(initialOAuthCallbackUri: uri)'));

    final sheet = File(
      'lib/widgets/calendar_event_sheet.dart',
    ).readAsStringSync();
    final agenda = File(
      'lib/widgets/calendar_day_agenda.dart',
    ).readAsStringSync();
    // Local calendar entries can be edited without a source module. Opening a
    // module detail still follows CalendarEvent.canOpen's source-ID guard.
    expect(
      sheet,
      contains('onPressed: canEdit ? () => _editLocalEvent(context) : null'),
    );
    expect(
      sheet,
      contains(
        'onPressed: widget.event.canOpen ? () => _openDetail(context) : null',
      ),
    );
    final eventModel = File(
      'lib/models/calendar_event.dart',
    ).readAsStringSync();
    expect(
      eventModel,
      contains('bool get canOpen => sourceId != null && sourceId!.isNotEmpty;'),
    );
    expect(agenda, contains('widget.event.sourceId != null'));
  });
  test('OAuth storage guards reject changed keys and mismatched service aliases', () {
    const storage = "static const accountsKey = 'duoyi_oauth_calendar_accounts_v1';\n"
        "static const eventsKeyPrefix = 'duoyi_oauth_calendar_events_';\n"
        "static const pendingAuthorizationKey =\n"
        "    'duoyi_oauth_calendar_pending_authorization_v1';\n";
    const service = 'static const _oauthAccountsKey = OAuthCalendarStorage.accountsKey;\n'
        'static const _oauthEventsKeyPrefix = OAuthCalendarStorage.eventsKeyPrefix;\n'
        'static const _pendingOAuthAuthorizationKey =\n'
        '    OAuthCalendarStorage.pendingAuthorizationKey;\n';
    expect(_missingOAuthStorageBindings(storage, service), isEmpty);
    for (final binding in _oauthStorageKeyBindings) {
      final changed = storage.replaceFirst(binding.$2, '${binding.$2}_changed');
      expect(_missingOAuthStorageBindings(changed, service), ['declaration:${binding.$1}']);
      final wrongAlias = service.replaceFirst('OAuthCalendarStorage.${binding.$1}', 'OAuthCalendarStorage.wrongKey');
      expect(_missingOAuthStorageBindings(storage, wrongAlias), ['alias:${binding.$3}']);
    }
    // Having the literal somewhere else cannot substitute for its declaration.
    expect(_missingOAuthStorageBindings('// ${storage.replaceAll('\n', '\n// ')}', service), hasLength(3));
    expect(_missingOAuthStorageBindings(storage, '// ${service.replaceAll('\n', '\n// ')}'), hasLength(3));
  });
}

const _oauthStorageKeyBindings = [
  ('accountsKey', 'duoyi_oauth_calendar_accounts_v1', '_oauthAccountsKey'),
  ('eventsKeyPrefix', 'duoyi_oauth_calendar_events_', '_oauthEventsKeyPrefix'),
  ('pendingAuthorizationKey', 'duoyi_oauth_calendar_pending_authorization_v1', '_pendingOAuthAuthorizationKey'),
];

List<String> _missingOAuthStorageBindings(String storage, String service) {
  final missing = <String>[];
  for (final binding in _oauthStorageKeyBindings) {
    final declaration = RegExp(
      r'^\s*static\s+const\s+' + RegExp.escape(binding.$1) +
          r"\s*=\s*'" + RegExp.escape(binding.$2) + r"'\s*;",
      multiLine: true,
    );
    final alias = RegExp(
      r'^\s*static\s+const\s+' + RegExp.escape(binding.$3) +
          r'\s*=\s*OAuthCalendarStorage\.' + RegExp.escape(binding.$1) + r'\s*;',
      multiLine: true,
    );
    if (!declaration.hasMatch(storage)) missing.add('declaration:${binding.$1}');
    if (!alias.hasMatch(service)) missing.add('alias:${binding.$3}');
  }
  return missing;
}
