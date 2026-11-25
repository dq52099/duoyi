import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart' as ast;
import 'package:analyzer/dart/ast/token.dart' show Token, TokenType;
import 'package:pub_semver/pub_semver.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

void main() {
  test('diagnostic substring checks do not hide API root requests', () {
    final temp = Directory.systemTemp.createTempSync('duoyi-route-literals-');
    try {
      File('${temp.path}/fixture.dart').writeAsStringSync('''
        lower.contains('/api/');
        client.get('/api/');
      ''');
      final literals = _extractApiLiterals(temp);
      expect(literals.map((literal) => literal.path).toList(), ['/api']);
    } finally {
      temp.deleteSync(recursive: true);
    }
  });

  test('guarded announcement wrapper preserves route extraction', () {
    final calls = _genericRequestApiCalls('''
      _sendAnnouncementAction('POST', '/api/admin/announcements', payload);
      _sendAnnouncementAction('PATCH', '/api/admin/announcements/\$id', payload);
      _sendAnnouncementAction('DELETE', '/api/admin/announcements/\$id', null);
    ''', 'fixture.dart');
    expect(calls.map((call) => (call.method, call.path)).toSet(), {
      ('POST', '/api/admin/announcements'),
      ('PATCH', '/api/admin/announcements/{param}'),
      ('DELETE', '/api/admin/announcements/{param}'),
    });
  });

  test('guarded user wrapper preserves methods and route extraction', () {
    final calls = _genericRequestApiCalls('''
      _sendUserAction('POST', '/api/admin/users/\$userId/coins', payload);
      _sendUserAction('POST', '/api/admin/users/bulk-status', payload,
          isCurrent: current);
      _sendUserAction('PATCH', '/api/admin/users/\$userId', payload);
      _sendUserAction('DELETE', '/api/admin/users/\$userId', null);
    ''', 'fixture.dart');
    expect(calls.map((call) => (call.method, call.path)).toSet(), {
      ('POST', '/api/admin/users/{param}/coins'),
      ('POST', '/api/admin/users/bulk-status'),
      ('PATCH', '/api/admin/users/{param}'),
      ('DELETE', '/api/admin/users/{param}'),
    });
  });

  test('guarded feedback wrapper preserves methods and route extraction', () {
    final calls = _genericRequestApiCalls('''
      _sendFeedbackAction('GET', '/api/admin/feedback/\$feedbackId', null);
      _sendFeedbackAction('POST', '/api/admin/feedback/reply', payload);
      _sendFeedbackAction('POST', '/api/admin/feedback/bulk-status', payload,
          isCurrent: current);
      _sendFeedbackAction('DELETE', '/api/admin/feedback/\$feedbackId', null,
          isCurrent: current);
      _sendFeedbackActionForAudit('POST',
          '/api/admin/feedback/must-not-be-extracted', payload);
      const unusedPath = '/api/admin/feedback/unused';
    ''', 'fixture.dart');
    final routes = calls.map((call) => (call.method, call.path)).toSet();
    expect(routes, {
      ('GET', '/api/admin/feedback/{param}'),
      ('POST', '/api/admin/feedback/reply'),
      ('POST', '/api/admin/feedback/bulk-status'),
      ('DELETE', '/api/admin/feedback/{param}'),
    });
    expect(calls, hasLength(4));
    expect(
      calls.any((call) => call.path.contains('must-not-be-extracted')),
      isFalse,
    );
    expect(calls.any((call) => call.path.endsWith('/unused')), isFalse);
  });

  test('literal client /api calls match backend FastAPI routes and methods', () {
    final backendRoutes = _extractBackendRoutes(
      File('backend/main.py').readAsStringSync(),
    );
    final clientCalls = _extractClientCalls(Directory('lib'), syntaxPolicy: _ApiSyntaxPolicy.compilationUnit);

    expect(
      backendRoutes,
      isNotEmpty,
      reason: 'backend/main.py should expose FastAPI HTTP routes.',
    );
    expect(
      clientCalls,
      isNotEmpty,
      reason: 'lib should contain literal client /api calls to check.',
    );

    final failures = <String>[];
    for (final call in clientCalls) {
      final exactMatch = backendRoutes.any(
        (route) => route.method == call.method && _samePathShape(route, call),
      );
      if (exactMatch) continue;

      final samePathMethods =
          backendRoutes
              .where((route) => _samePathShape(route, call))
              .map((route) => route.method)
              .toSet()
              .toList()
            ..sort();
      final suffix = samePathMethods.isEmpty
          ? 'no matching backend path'
          : 'backend path exists with ${samePathMethods.join(', ')}';
      failures.add('${call.location}: ${call.method} ${call.path} ($suffix)');
    }

    expect(
      failures,
      isEmpty,
      reason:
          'Every literal /api call in lib must match an @app route in '
          'backend/main.py with the same HTTP method.\n${failures.join('\n')}',
    );
  });

  test(
    'every backend api literal in lib is covered by contract extraction',
    () {
      final clientCalls = _extractClientCalls(Directory('lib'), syntaxPolicy: _ApiSyntaxPolicy.compilationUnit);
      final apiLiterals = _extractApiLiterals(Directory('lib'));

      expect(
        apiLiterals,
        isNotEmpty,
        reason: 'lib should contain backend /api literals to audit.',
      );

      final missing = <String>[];
      for (final literal in apiLiterals) {
        if (literal.unresolved != null) {
          missing.add('${literal.location}: ${literal.unresolved} [${literal.expressionStart},${literal.expressionEnd})');
          continue;
        }
        final covered = clientCalls.any(
          (call) => _samePathShape(
            call,
            _RouteContract(
              method: call.method,
              path: literal.coveragePath,
              location: literal.location,
            ),
          ),
        );
        if (!covered) missing.add('${literal.location}: ${literal.coveragePath} (source ${literal.path})');
      }

      expect(
        missing,
        isEmpty,
        reason:
            'Every backend-bound /api literal in lib must be visible to the '
            'static route-contract extractor, otherwise new call shapes can '
            'bypass the 404 guard.\n${missing.join('\n')}',
      );
    },
  );

  test('web shell does not carry stale backend api paths', () {
    final webApiLiterals = _extractTextApiLiterals(Directory('web'));

    expect(
      webApiLiterals,
      isEmpty,
      reason:
          'web/ is the Flutter shell/static manifest area. It must not keep '
          'stale hard-coded /api paths that bypass the Flutter ApiClient '
          'route-contract guard.\n${webApiLiterals.join('\n')}',
    );
  });

  test('client runtime contract hash matches backend required routes', () {
    final backend = File('backend/main.py').readAsStringSync();
    final client = File('lib/services/api_client.dart').readAsStringSync();
    final routesStart = backend.indexOf('API_CONTRACT_REQUIRED_ROUTES = [');
    final routesEnd = backend.indexOf(']', routesStart);
    expect(routesStart, greaterThanOrEqualTo(0));
    expect(routesEnd, greaterThan(routesStart));
    final routesBlock = backend.substring(routesStart, routesEnd);
    final routes = RegExp(
      r'"([^"]+)"',
    ).allMatches(routesBlock).map((match) => match.group(1)!).toList();
    expect(routes, isNotEmpty);

    final routesHash = sha256
        .convert(utf8.encode(routes.join('\n')))
        .toString()
        .substring(0, 16);
    expect(
      backend,
      contains('"required_routes_hash": API_CONTRACT_ROUTES_HASH'),
    );
    expect(client, contains("requiredApiContractRoutesHash = '$routesHash'"));
    expect(client, contains("decoded['required_routes_hash']"));
    expect(client, contains('requiredApiContractRoutesHash'));
  });

  test('account profile email avatar and coin routes stay compatible', () {
    final backend = File('backend/main.py').readAsStringSync();
    final authProvider = File(
      'lib/providers/auth_provider.dart',
    ).readAsStringSync();
    final aiService = File('lib/services/ai_service.dart').readAsStringSync();
    final feedbackScreen = File(
      'lib/screens/feedback_screen.dart',
    ).readAsStringSync();
    final loginScreen = File(
      'lib/screens/login_screen.dart',
    ).readAsStringSync();
    final profileScreen = File(
      'lib/screens/profile_screen.dart',
    ).readAsStringSync();
    final mineScreen = File('lib/screens/mine_screen.dart').readAsStringSync();
    final surfaceComponents = File(
      'lib/widgets/surface_components.dart',
    ).readAsStringSync();
    final adminApi = File('lib/services/admin_api.dart').readAsStringSync();

    for (final route in [
      '@app.post("/api/me/profile")',
      '@app.patch("/api/me/profile")',
      '@app.put("/api/me/profile")',
      '@app.post("/api/auth/login")',
      '@app.get("/api/auth/me")',
      '@app.get("/api/me")',
      '@app.post("/api/auth/logout")',
      '@app.post("/api/me/email")',
      '@app.patch("/api/me/email")',
      '@app.put("/api/me/email")',
      '@app.post("/api/me/email/bind")',
      '@app.patch("/api/me/email/bind")',
      '@app.put("/api/me/email/bind")',
      '@app.post("/api/me/bind-email")',
      '@app.patch("/api/me/bind-email")',
      '@app.put("/api/me/bind-email")',
      '@app.post("/api/auth/email")',
      '@app.patch("/api/auth/email")',
      '@app.put("/api/auth/email")',
      '@app.post("/api/auth/email/bind")',
      '@app.patch("/api/auth/email/bind")',
      '@app.put("/api/auth/email/bind")',
      '@app.post("/api/auth/bind-email")',
      '@app.patch("/api/auth/bind-email")',
      '@app.put("/api/auth/bind-email")',
      '@app.post("/api/me/email-code")',
      '@app.post("/api/me/email-code/send")',
      '@app.post("/api/me/email_code")',
      '@app.post("/api/me/email_code/send")',
      '@app.post("/api/me/email/send")',
      '@app.post("/api/me/email/send-code")',
      '@app.post("/api/auth/email-code")',
      '@app.post("/api/auth/email-code/send")',
      '@app.post("/api/auth/email_code")',
      '@app.post("/api/auth/email_code/send")',
      '@app.post("/api/auth/email/send")',
      '@app.post("/api/auth/email/send-code")',
      '@app.post("/api/auth/send-email-code")',
      '@app.post("/api/auth/send-email_code")',
      '@app.post("/api/auth/email-login")',
      '@app.post("/api/auth/email/login")',
      '@app.post("/api/auth/login/email")',
      '@app.post("/api/auth/email-code-login")',
      '@app.post("/api/auth/login/email-code")',
      '@app.post("/api/auth/email_code_login")',
      '@app.post("/api/auth/login/email_code")',
      '@app.post("/api/me/avatar")',
      '@app.patch("/api/me/avatar")',
      '@app.put("/api/me/avatar")',
      '@app.post("/api/me/profile/avatar")',
      '@app.patch("/api/me/profile/avatar")',
      '@app.put("/api/me/profile/avatar")',
      '@app.post("/api/auth/avatar")',
      '@app.patch("/api/auth/avatar")',
      '@app.put("/api/auth/avatar")',
      '@app.post("/api/auth/profile/avatar")',
      '@app.patch("/api/auth/profile/avatar")',
      '@app.put("/api/auth/profile/avatar")',
      '@app.post("/api/me/password")',
      '@app.post("/api/auth/change-password")',
      '@app.get("/api/uploads/avatars/{filename}")',
      '@app.post("/api/ai/chat")',
      '@app.get("/api/ai/usage")',
      '@app.post("/api/feedback")',
      '@app.get("/api/feedback/me")',
      '@app.get("/api/me/feedback")',
      '@app.get("/api/admin/feedback")',
      '@app.get("/api/admin/feedback/{fb_id}")',
      '@app.post("/api/admin/feedback/reply")',
      '@app.post("/api/admin/feedback/bulk-status")',
      '@app.delete("/api/admin/feedback/{fb_id}")',
      '@app.get("/api/admin/settings")',
      '@app.patch("/api/admin/settings")',
      '@app.get("/api/admin/system-settings")',
      '@app.post("/api/admin/system-settings")',
      '@app.patch("/api/admin/system-settings")',
      '@app.put("/api/admin/system-settings")',
      '@app.post("/api/admin/ai/test")',
      '@app.post("/api/admin/account-email/test")',
      '@app.get("/api/admin/groups")',
      '@app.get("/api/admin/user-groups")',
      '@app.get("/api/admin/user_groups")',
      '@app.post("/api/admin/groups")',
      '@app.post("/api/admin/user-groups")',
      '@app.post("/api/admin/user_groups")',
      '@app.delete("/api/admin/groups/{group_id}")',
      '@app.delete("/api/admin/user-groups/{group_id}")',
      '@app.delete("/api/admin/user_groups/{group_id}")',
      '@app.patch("/api/admin/groups/{group_id}")',
      '@app.put("/api/admin/groups/{group_id}")',
      '@app.patch("/api/admin/user-groups/{group_id}")',
      '@app.put("/api/admin/user-groups/{group_id}")',
      '@app.patch("/api/admin/user_groups/{group_id}")',
      '@app.put("/api/admin/user_groups/{group_id}")',
      '@app.post("/api/admin/users/{user_id}/coins")',
      '@app.patch("/api/admin/users/{user_id}/coins")',
      '@app.put("/api/admin/users/{user_id}/coins")',
      '@app.post("/api/admin/users/{user_id}/coin")',
      '@app.patch("/api/admin/users/{user_id}/coin")',
      '@app.put("/api/admin/users/{user_id}/coin")',
      '@app.post("/api/admin/users/{user_id}/coin-balance")',
      '@app.patch("/api/admin/users/{user_id}/coin-balance")',
      '@app.put("/api/admin/users/{user_id}/coin-balance")',
      '@app.post("/api/admin/users/{user_id}/coin_balance")',
      '@app.patch("/api/admin/users/{user_id}/coin_balance")',
      '@app.put("/api/admin/users/{user_id}/coin_balance")',
      '@app.post("/api/admin/users/{user_id}/quota")',
      '@app.patch("/api/admin/users/{user_id}/quota")',
      '@app.put("/api/admin/users/{user_id}/quota")',
      '@app.post("/api/admin/users/{user_id}/time-coins")',
      '@app.patch("/api/admin/users/{user_id}/time-coins")',
      '@app.put("/api/admin/users/{user_id}/time-coins")',
      '@app.post("/api/admin/users/{user_id}/time-coin-balance")',
      '@app.patch("/api/admin/users/{user_id}/time-coin-balance")',
      '@app.put("/api/admin/users/{user_id}/time-coin-balance")',
      '@app.post("/api/admin/users/{user_id}/time_coins")',
      '@app.patch("/api/admin/users/{user_id}/time_coins")',
      '@app.put("/api/admin/users/{user_id}/time_coins")',
      '@app.post("/api/admin/users/{user_id}/time_coin_balance")',
      '@app.patch("/api/admin/users/{user_id}/time_coin_balance")',
      '@app.put("/api/admin/users/{user_id}/time_coin_balance")',
      '@app.post("/api/admin/users/{user_id}/credits")',
      '@app.patch("/api/admin/users/{user_id}/credits")',
      '@app.put("/api/admin/users/{user_id}/credits")',
      '@app.post("/api/admin/users/{user_id}/credit-balance")',
      '@app.patch("/api/admin/users/{user_id}/credit-balance")',
      '@app.put("/api/admin/users/{user_id}/credit-balance")',
      '@app.post("/api/admin/users/{user_id}/credit_balance")',
      '@app.patch("/api/admin/users/{user_id}/credit_balance")',
      '@app.put("/api/admin/users/{user_id}/credit_balance")',
      '@app.post("/api/admin/users/{user_id}/coins/adjust")',
      '@app.patch("/api/admin/users/{user_id}/coins/adjust")',
      '@app.put("/api/admin/users/{user_id}/coins/adjust")',
      '@app.post("/api/admin/users/{user_id}/time-coins/adjust")',
      '@app.patch("/api/admin/users/{user_id}/time-coins/adjust")',
      '@app.put("/api/admin/users/{user_id}/time-coins/adjust")',
      '@app.post("/api/admin/users/{user_id}/time_coins/adjust")',
      '@app.patch("/api/admin/users/{user_id}/time_coins/adjust")',
      '@app.put("/api/admin/users/{user_id}/time_coins/adjust")',
      '@app.post("/api/admin/users/{user_id}/time-coin-balance/adjust")',
      '@app.patch("/api/admin/users/{user_id}/time-coin-balance/adjust")',
      '@app.put("/api/admin/users/{user_id}/time-coin-balance/adjust")',
      '@app.post("/api/admin/users/{user_id}/time_coin_balance/adjust")',
      '@app.patch("/api/admin/users/{user_id}/time_coin_balance/adjust")',
      '@app.put("/api/admin/users/{user_id}/time_coin_balance/adjust")',
      '@app.post("/api/admin/users/{user_id}/quota/adjust")',
      '@app.patch("/api/admin/users/{user_id}/quota/adjust")',
      '@app.put("/api/admin/users/{user_id}/quota/adjust")',
      '@app.post("/api/admin/users/{user_id}/coin-adjustment")',
      '@app.patch("/api/admin/users/{user_id}/coin-adjustment")',
      '@app.put("/api/admin/users/{user_id}/coin-adjustment")',
      '@app.post("/api/admin/users/{user_id}/coin_adjustment")',
      '@app.patch("/api/admin/users/{user_id}/coin_adjustment")',
      '@app.put("/api/admin/users/{user_id}/coin_adjustment")',
      '@app.get("/api/mobile/apps/{app_id}/update")',
      '@app.get("/api/config")',
    ]) {
      expect(backend, contains(route), reason: route);
    }

    expect(
      authProvider,
      contains("'/api/me/profile',"),
      reason: '资料保存应把当前后端主路由放在兼容路径第一位。',
    );
    expect(
      authProvider,
      contains("'/api/me/email',"),
      reason: '邮箱绑定应把当前后端主路由放在兼容路径第一位。',
    );
    expect(
      authProvider,
      contains("_uploadFirstAvailable("),
      reason: '头像上传应走可被契约扫描识别的兼容路由兜底。',
    );

    for (final call in [
      "'/api/me/profile'",
      "'/api/me/email'",
      "'/api/me/email-code'",
      "'/api/me/avatar'",
      "'/api/me/password'",
      "'/api/auth/change-password'",
      "'/api/auth/email-code'",
      "'/api/auth/email-login'",
      "'/api/auth/login'",
      "'/api/auth/me'",
      "'/api/auth/logout'",
    ]) {
      expect(authProvider, contains(call), reason: call);
    }
    for (final compatibilityFallback in [
      "'/api/auth/login/email-code'",
      "'/api/me/email-code/send'",
      "'/api/auth/email-code/send'",
      "'/api/me/profile/avatar'",
      "'/api/account/avatar'",
    ]) {
      expect(
        authProvider,
        contains(compatibilityFallback),
        reason:
            '$compatibilityFallback should remain as a stale-backend fallback after the main route.',
      );
    }

    expect(aiService, contains("post('/api/ai/chat'"));
    expect(feedbackScreen, contains("'/api/feedback'"));
    expect(feedbackScreen, contains("'/api/feedback/me?page="));
    expect(adminApi, contains("'/api/admin/users/\$userId/coins'"));
    expect(
      adminApi,
      matches(
        RegExp(
          r"_sendUserAction\(\s*'POST',\s*'/api/admin/users/\$userId/coins',\s*body,",
        ),
      ),
    );
    for (final noisyFallback in [
      "'/api/admin/users/\$userId/quota/adjust'",
      "'/api/admin/users/\$userId/time-coins/adjust'",
      "'/api/admin/users/\$userId/time_coin_balance/adjust'",
      "'/api/admin/users/\$userId/coin-adjustment'",
    ]) {
      expect(
        adminApi,
        isNot(contains(noisyFallback)),
        reason:
            '$noisyFallback should remain a backend alias, not a frontend probe.',
      );
    }
    expect(adminApi, contains("'/api/admin/settings'"));
    expect(adminApi, contains("'/api/admin/system-settings'"));
    expect(adminApi, contains("'/api/admin/groups'"));
    expect(adminApi, contains("'/api/admin/user-groups'"));
    expect(adminApi, contains("'/api/admin/user_groups'"));
    expect(adminApi, contains("'/api/admin/feedback'"));
    expect(
      adminApi,
      contains('Future<Map<String, dynamic>> getFeedbackDetail'),
    );
    expect(
      adminApi,
      matches(
        RegExp(
          r'''Future<Map<String, dynamic>> getFeedbackDetail\([\s\S]*?\)\s*=>\s*_sendFeedbackAction\(\s*'GET'\s*,\s*'/api/admin/feedback/\$id'\s*,\s*null\s*,\s*isCurrent:\s*isCurrent\s*,?\s*\);''',
        ),
      ),
    );
    expect(adminApi, contains("'/api/admin/feedback/export.csv'"));
    expect(adminApi, contains("'/api/admin/feedback/reply'"));
    expect(adminApi, contains("'/api/admin/feedback/bulk-status'"));
    expect(adminApi, contains("'/api/admin/ai/test'"));
    expect(adminApi, contains("'/api/admin/account-email/test'"));
    expect(loginScreen, contains('class _LoginActionField'));
    expect(loginScreen, contains('Widget _emailCodeSendField({'));
    expect(
      loginScreen,
      contains('final actionWidth = constraints.maxWidth < 360 ? 68.0 : 76.0'),
    );
    expect(
      surfaceComponents,
      contains('disabledBackgroundColor: disabledBackground'),
    );
    expect(loginScreen, contains(r"'${_emailCooldownSeconds}s 后'"));

    expect(profileScreen, contains('readOnly: true'));
    expect(profileScreen, contains("I18n.tr('profile.username.locked')"));
    expect(profileScreen, contains('sendBindEmailCode('));
    expect(
      profileScreen,
      matches(
        RegExp(
          r'_auth\.bindEmail\(\s*email:\s*email,\s*code:\s*code,\s*sessionLease:\s*_sessionLease,?\s*\)',
        ),
      ),
    );
    expect(profileScreen, contains('uploadAvatarBytes('));
    expect(profileScreen, contains('onPreview: _showAvatarPreview'));
    expect(profileScreen, contains('onEdit: _uploadAvatar'));
    expect(profileScreen, contains('onEdit: _pickLocalAvatar'));
    expect(profileScreen, isNot(contains('Icons.photo_camera_outlined')));
    expect(mineScreen, contains('onShowAvatarPreview: _showAvatarPreview'));
    expect(
      mineScreen,
      contains('if (canAct()) onShowAvatarPreview(actionContext)'),
    );
    expect(mineScreen, contains('onOpenProfileEditor: _openProfileEditor'));
    expect(mineScreen, contains('onTap: () => onOpenProfileEditor(context)'));
    expect(
      mineScreen,
      contains('void _openProfileEditor(BuildContext context'),
    );
    expect(mineScreen, isNot(contains("title: '账号资料'")));
  });

  test('high-risk account admin ai and feedback calls are route-backed', () {
    final backendRoutes = _extractBackendRoutes(
      File('backend/main.py').readAsStringSync(),
    );
    final clientCalls = _extractClientCalls(Directory('lib'), syntaxPolicy: _ApiSyntaxPolicy.compilationUnit);

    final expectations = <_RouteContract>[
      const _RouteContract(
        method: 'GET',
        path: '/api/feedback/me',
        location: '',
      ),
      const _RouteContract(method: 'POST', path: '/api/feedback', location: ''),
      const _RouteContract(
        method: 'GET',
        path: '/api/admin/feedback',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/admin/feedback/{param}',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/admin/feedback/export.csv',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/admin/feedback/reply',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/admin/feedback/bulk-status',
        location: '',
      ),
      const _RouteContract(
        method: 'DELETE',
        path: '/api/admin/feedback/{param}',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/admin/ai/test',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/admin/provider-healthcheck',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/admin/groups',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/admin/user-groups',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/admin/user_groups',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/admin/groups',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/admin/user-groups',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/admin/user_groups',
        location: '',
      ),
      const _RouteContract(
        method: 'DELETE',
        path: '/api/admin/groups/{param}',
        location: '',
      ),
      const _RouteContract(
        method: 'DELETE',
        path: '/api/admin/user-groups/{param}',
        location: '',
      ),
      const _RouteContract(
        method: 'DELETE',
        path: '/api/admin/user_groups/{param}',
        location: '',
      ),
      const _RouteContract(
        method: 'PATCH',
        path: '/api/admin/groups/{param}',
        location: '',
      ),
      const _RouteContract(
        method: 'PUT',
        path: '/api/admin/groups/{param}',
        location: '',
      ),
      const _RouteContract(
        method: 'PATCH',
        path: '/api/admin/user-groups/{param}',
        location: '',
      ),
      const _RouteContract(
        method: 'PUT',
        path: '/api/admin/user-groups/{param}',
        location: '',
      ),
      const _RouteContract(
        method: 'PATCH',
        path: '/api/admin/user_groups/{param}',
        location: '',
      ),
      const _RouteContract(
        method: 'PUT',
        path: '/api/admin/user_groups/{param}',
        location: '',
      ),
      const _RouteContract(
        method: 'PATCH',
        path: '/api/admin/settings',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/admin/system-settings',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/admin/system-settings',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/mobile/apps/duoyi/update',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/admin/users/{param}/coins',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/admin/roles',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/admin/roles',
        location: '',
      ),
      const _RouteContract(
        method: 'PATCH',
        path: '/api/admin/roles/{param}',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/admin/announcements',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/admin/announcements',
        location: '',
      ),
      const _RouteContract(
        method: 'PATCH',
        path: '/api/admin/announcements/{param}',
        location: '',
      ),
      const _RouteContract(
        method: 'DELETE',
        path: '/api/admin/announcements/{param}',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/admin/invite-codes',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/admin/invite-codes',
        location: '',
      ),
      const _RouteContract(
        method: 'DELETE',
        path: '/api/admin/invite-codes/{param}',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/admin/audit-log',
        location: '',
      ),
      const _RouteContract(
        method: 'PATCH',
        path: '/api/me/profile',
        location: '',
      ),
      const _RouteContract(
        method: 'PATCH',
        path: '/api/me/email',
        location: '',
      ),
      const _RouteContract(method: 'POST', path: '/api/me/email', location: ''),
      const _RouteContract(
        method: 'POST',
        path: '/api/me/avatar',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/auth/email-code',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/me/email-code',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/auth/email-login',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/auth/login',
        location: '',
      ),
      const _RouteContract(method: 'GET', path: '/api/auth/me', location: ''),
      const _RouteContract(method: 'GET', path: '/api/me', location: ''),
      const _RouteContract(
        method: 'POST',
        path: '/api/auth/logout',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/me/password',
        location: '',
      ),
    ];

    final failures = <String>[];
    for (final expected in expectations) {
      final inClient = _hasContract(clientCalls, expected);
      final inBackend = backendRoutes.any(
        (route) =>
            route.method == expected.method && _samePathShape(route, expected),
      );
      if (!inClient || !inBackend) {
        failures.add(
          '${expected.method} ${expected.path} '
          '(client=${inClient ? 'yes' : 'no'}, backend=${inBackend ? 'yes' : 'no'})',
        );
      }
    }

    expect(
      failures,
      isEmpty,
      reason:
          'High-risk API calls must be present in the Flutter contract scan '
          'and backed by backend/main.py routes.\n${failures.join('\n')}',
    );
    expect(
      backendRoutes.any(
        (route) =>
            route.method == 'POST' &&
            _samePathShape(
              route,
              const _RouteContract(
                method: 'POST',
                path: '/api/admin/welfare-grants',
                location: '',
              ),
            ),
      ),
      isTrue,
      reason:
          '/api/admin/welfare-grants is a backend compatibility route; the '
          'current app adjusts per-user time coins through AdminApi.',
    );
  });

  test('legacy api service entrypoint delegates to api client', () {
    final source = File('lib/services/api_service.dart').readAsStringSync();

    expect(source, contains("import 'api_client.dart';"));
    expect(source, contains('class ApiService extends ApiClient'));
    expect(source, contains('super.httpClient'));
    expect(
      source,
      contains(
        "ApiService({super.baseUrl = '', super.token, super.httpClient})",
      ),
    );
  });

  test('RE0 style non-AI route aliases stay live', () {
    final backend = File('backend/main.py').readAsStringSync();

    for (final route in [
      '@app.post("/api/me/feedback")',
      '@app.get("/api/me/feedback")',
      '@app.get("/api/me/feedback/{fb_id}")',
      '@app.get("/api/feedback/me/{fb_id}")',
      '@app.get("/api/admin/feedback/{fb_id}")',
      '@app.post("/api/admin/feedback/{fb_id}/status")',
      '@app.post("/api/admin/feedback/{fb_id}/reply")',
      '@app.post("/api/admin/feedback/{fb_id}/ai-summary")',
      '@app.get("/api/admin/feedback/automation")',
      '@app.post("/api/admin/feedback/automation")',
      '@app.post("/api/admin/feedback/auto-run")',
      '@app.post("/api/admin/feedback/auto-reply")',
      '@app.get("/api/admin/feedback/insights")',
      '@app.post("/api/admin/feedback/export")',
      '@app.post("/api/me/password")',
      '@app.post("/api/auth/password-reset")',
      '@app.post("/api/auth/password-reset/request")',
      '@app.post("/api/auth/password-reset/confirm")',
      '@app.post("/api/auth/reset-password")',
      '@app.post("/api/auth/reset-password/request")',
      '@app.post("/api/auth/reset-password/confirm")',
      '@app.post("/api/auth/forgot-password")',
      '@app.post("/api/auth/forgot-password/request")',
      '@app.post("/api/auth/forgot-password/confirm")',
      '@app.post("/api/password-reset")',
      '@app.post("/api/password-reset/request")',
      '@app.post("/api/password-reset/confirm")',
      '@app.get("/api/admin/overview")',
      '@app.get("/api/admin/local-backups")',
      '@app.post("/api/admin/local-backups/run")',
    ]) {
      expect(backend, contains(route), reason: route);
    }

    expect(
      backend,
      contains('def admin_feedback_status_alias'),
      reason:
          'RE0 admin feedback status route should delegate to current handler.',
    );
    expect(
      backend,
      contains('def admin_feedback_reply_alias'),
      reason:
          'RE0 admin feedback reply route should delegate to current handler.',
    );
  });

  test('focus room share admin and sync route families stay backed', () {
    final backend = File('backend/main.py').readAsStringSync();
    final focusRoomApi = File(
      'lib/services/focus_room_api.dart',
    ).readAsStringSync();
    final shareProvider = File(
      'lib/providers/share_provider.dart',
    ).readAsStringSync();
    final adminApi = File('lib/services/admin_api.dart').readAsStringSync();
    final syncProvider = File(
      'lib/providers/cloud_sync_provider.dart',
    ).readAsStringSync();
    final emailSink = File(
      'lib/services/backend_reminder_email_sink.dart',
    ).readAsStringSync();

    for (final route in [
      '@app.post("/api/focus-rooms/{room_id}/heartbeat")',
      '@app.get("/api/focus-rooms/{room_id}/ranking")',
      '@app.get("/api/focus-rooms/{room_id}/events")',
      '@app.post("/api/focus-rooms/{room_id}/leave")',
      '@app.get("/api/focus-friends")',
      '@app.get("/api/focus-friends/requests")',
      '@app.post("/api/focus-friends")',
      '@app.delete("/api/focus-friends/{friend_user_id}")',
      '@app.post("/api/focus-friend-requests/{requester_user_id}/accept")',
      '@app.post("/api/focus-friend-requests/{requester_user_id}/reject")',
      '@app.delete("/api/focus-friend-requests/{friend_user_id}")',
      '@app.get("/api/focus-leaderboard/friends")',
      '@app.get("/api/focus-leaderboard/global")',
      '@app.get("/api/focus-leaderboard/global/events")',
      '@app.post("/api/focus-rooms/{room_id}/invites")',
      '@app.get("/api/focus-rooms/{room_id}/invites")',
      '@app.delete("/api/focus-room-invites/{invite_id}")',
      '@app.post("/api/focus-room-invites/{code}/accept")',
      '@app.get("/api/workspaces")',
      '@app.post("/api/workspaces")',
      '@app.post("/api/workspaces/{workspace_id}/invites")',
      '@app.post("/api/invites/{code}/accept")',
      '@app.patch("/api/workspaces/{workspace_id}/members/{member_user_id}")',
      '@app.delete("/api/workspaces/{workspace_id}/members/{member_user_id}")',
      '@app.get("/api/workspaces/{workspace_id}/comments")',
      '@app.post("/api/workspaces/{workspace_id}/comments")',
      '@app.get("/api/workspaces/mentions")',
      '@app.post("/api/workspaces/mentions/{mention_id}/read")',
      '@app.get("/api/workspaces/{workspace_id}/activities")',
      '@app.get("/api/workspaces/{workspace_id}/leaderboard")',
      '@app.get("/api/admin/stats")',
      '@app.post("/api/admin/provider-healthcheck")',
      '@app.post("/api/admin/welfare-grants")',
      '@app.post("/api/admin/reminders/email/test")',
      '@app.post("/api/reminders/email/once")',
      '@app.post("/api/reminders/email/repeating")',
      '@app.delete("/api/reminders/email/{reminder_id}")',
      '@app.get("/api/admin/backups")',
      '@app.get("/api/admin/backups/export.csv")',
      '@app.delete("/api/admin/backups/{user_id}")',
      '@app.get("/api/admin/server-backups")',
      '@app.get("/api/admin/server-backups/export.csv")',
      '@app.post("/api/admin/server-backups/run")',
      '@app.post("/api/sync")',
      '@app.post("/api/sync/delta")',
      '@app.post("/api/sync/item-delta")',
      '@app.post("/api/sync/pull")',
      '@app.get("/api/sync/status")',
      '@app.get("/api/sync/events")',
    ]) {
      expect(backend, contains(route), reason: route);
    }

    for (final call in [
      "'/api/focus-rooms/\${Uri.encodeComponent(roomId)}/heartbeat'",
      "'/api/focus-friends'",
      "'/api/focus-leaderboard/global/events?\$query'",
      "'/api/focus-room-invites/\${Uri.encodeComponent(code)}/accept'",
    ]) {
      expect(focusRoomApi, contains(call), reason: call);
    }

    for (final call in [
      "'/api/workspaces'",
      "'/api/workspaces/mentions'",
      "'/api/workspaces/\$workspaceId/comments'",
      "'/api/invites/\${Uri.encodeComponent(code)}/accept'",
    ]) {
      expect(shareProvider, contains(call), reason: call);
    }

    for (final call in [
      "'/api/admin/stats'",
      "'/api/admin/provider-healthcheck'",
      "'/api/admin/reminders/email/test'",
      "'/api/admin/backups'",
      "'/api/admin/server-backups'",
      "'/api/admin/server-backups/run'",
    ]) {
      expect(adminApi, contains(call), reason: call);
    }

    for (final call in [
      "'/api/sync/events'",
      "'/api/sync/status'",
      "'/api/sync'",
      "'/api/sync/item-delta'",
      "'/api/sync/delta'",
      "'/api/sync/pull'",
    ]) {
      expect(syncProvider, contains(call), reason: call);
    }

    for (final call in [
      "'/api/reminders/email/once'",
      "'/api/reminders/email/repeating'",
      "'/api/reminders/email/\$id'",
    ]) {
      expect(emailSink, contains(call), reason: call);
    }
  });

  test(
    'admin coin adjustment uses one primary route while backend keeps aliases',
    () {
      final backendRoutes = _extractBackendRoutes(
        File('backend/main.py').readAsStringSync(),
      );
      final adminApiSource = File(
        'lib/services/admin_api.dart',
      ).readAsStringSync();
      final adminApiCalls = [
        ..._genericRequestApiCalls(
          adminApiSource,
          'lib/services/admin_api.dart',
        ),
        ..._literalApiMethodCalls(
          adminApiSource,
          'lib/services/admin_api.dart',
        ),
        ..._nestedPathApiMethodCalls(
          adminApiSource,
          'lib/services/admin_api.dart',
        ),
        ..._getPageApiCalls(adminApiSource, 'lib/services/admin_api.dart'),
        ..._firstAvailableApiCalls(
          adminApiSource,
          'lib/services/admin_api.dart',
        ),
      ];

      const primary = _RouteContract(
        method: 'POST',
        path: '/api/admin/users/{param}/coins',
        location: '',
      );
      final coinAdjustmentStart = adminApiSource.indexOf(
        'Future<Map<String, dynamic>> adjustUserCoins(',
      );
      final coinValidationStart = adminApiSource.indexOf(
        'Map<String, dynamic> _validateCoinAdjustmentResponse(',
        coinAdjustmentStart,
      );
      expect(coinAdjustmentStart, isNonNegative);
      expect(coinValidationStart, greaterThan(coinAdjustmentStart));
      final coinAdjustmentSource = adminApiSource.substring(
        coinAdjustmentStart,
        coinValidationStart,
      );
      final coinAdjustmentCalls = _genericRequestApiCalls(
        coinAdjustmentSource,
        'lib/services/admin_api.dart',
      );
      expect(
        coinAdjustmentCalls.map((call) => (call.method, call.path)).toList(),
        [('POST', primary.path)],
        reason:
            'AdminApi.adjustUserCoins must dispatch exactly one POST to the '
            'current primary route through its guarded action wrapper.',
      );
      expect(
        backendRoutes.any(
          (route) =>
              route.method == primary.method && _samePathShape(route, primary),
        ),
        isTrue,
        reason: 'The primary admin coin route must exist in backend/main.py.',
      );

      final backendAliasPaths = [
        '/api/admin/users/{param}/coins',
        '/api/admin/users/{param}/coin',
        '/api/admin/users/{param}/coin-balance',
        '/api/admin/users/{param}/coin_balance',
        '/api/admin/users/{param}/time-coins',
        '/api/admin/users/{param}/time_coins',
        '/api/admin/users/{param}/time-coin-balance',
        '/api/admin/users/{param}/time_coin_balance',
        '/api/admin/users/{param}/credits',
        '/api/admin/users/{param}/credit-balance',
        '/api/admin/users/{param}/credit_balance',
        '/api/admin/users/{param}/coins/adjust',
        '/api/admin/users/{param}/time-coins/adjust',
        '/api/admin/users/{param}/time_coins/adjust',
        '/api/admin/users/{param}/time-coin-balance/adjust',
        '/api/admin/users/{param}/time_coin_balance/adjust',
        '/api/admin/users/{param}/coin-adjustment',
        '/api/admin/users/{param}/coin_adjustment',
        '/api/admin/users/{param}/quota',
        '/api/admin/users/{param}/quota/adjust',
        '/api/admin/users/{param}',
      ];

      for (final method in ['POST', 'PATCH', 'PUT']) {
        for (final path in backendAliasPaths) {
          final expected = _RouteContract(
            method: method,
            path: path,
            location: '',
          );
          expect(
            backendRoutes.any(
              (route) =>
                  route.method == method && _samePathShape(route, expected),
            ),
            isTrue,
            reason:
                'Backend admin coin compatibility alias must exist: '
                '$method $path',
          );
        }
      }

      for (final path
          in backendAliasPaths
              .skip(1)
              .where((path) => path != '/api/admin/users/{param}')) {
        final clientProbe = _RouteContract(
          method: 'POST',
          path: path,
          location: '',
        );
        expect(
          _hasContract(adminApiCalls, clientProbe),
          isFalse,
          reason:
              'Compatibility alias $path should not be actively probed by '
              'AdminApi.adjustUserCoins.',
        );
      }

      for (final expected in [
        const _RouteContract(
          method: 'POST',
          path: '/api/admin/ai/test',
          location: '',
        ),
        const _RouteContract(
          method: 'POST',
          path: '/api/admin/provider-healthcheck',
          location: '',
        ),
      ]) {
        expect(
          _hasContract(adminApiCalls, expected),
          isTrue,
          reason:
              'AdminApi.testAi primary and fallback routes must both be '
              'contract-covered: ${expected.method} ${expected.path}',
        );
        expect(
          backendRoutes.any(
            (route) =>
                route.method == expected.method &&
                _samePathShape(route, expected),
          ),
          isTrue,
          reason:
              'AdminApi.testAi primary and fallback routes must both exist in '
              'backend/main.py: ${expected.method} ${expected.path}',
        );
      }
    },
  );

  test('dynamic and external api paths are classified correctly', () {
    final backendRoutes = _extractBackendRoutes(
      File('backend/main.py').readAsStringSync(),
    );
    final clientCalls = _extractClientCalls(Directory('lib'), syntaxPolicy: _ApiSyntaxPolicy.compilationUnit);

    for (final call in [
      const _RouteContract(
        method: 'POST',
        path: '/api/focus-rooms/{param}/heartbeat',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/focus-rooms/{param}/ranking',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/focus-rooms/{param}/events',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/focus-leaderboard/global/events',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/focus-rooms/{param}/leave',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/focus-friend-requests/{param}/accept',
        location: '',
      ),
      const _RouteContract(
        method: 'DELETE',
        path: '/api/focus-friends/{param}',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/focus-friends/requests',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/focus-rooms/{param}/invites',
        location: '',
      ),
      const _RouteContract(
        method: 'DELETE',
        path: '/api/focus-room-invites/{param}',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/focus-room-invites/{param}/accept',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/mobile/apps/duoyi/update',
        location: '',
      ),
      const _RouteContract(method: 'GET', path: '/api/config', location: ''),
      const _RouteContract(method: 'GET', path: '/api/auth/me', location: ''),
      const _RouteContract(
        method: 'GET',
        path: '/api/announcements',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/reminders/email/once',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/reminders/email/repeating',
        location: '',
      ),
      const _RouteContract(
        method: 'DELETE',
        path: '/api/reminders/email/{param}',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/sync/events',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/sync/status',
        location: '',
      ),
      const _RouteContract(method: 'POST', path: '/api/sync', location: ''),
      const _RouteContract(
        method: 'POST',
        path: '/api/sync/item-delta',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/sync/delta',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/sync/pull',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/admin/backups',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/admin/backups/export.csv',
        location: '',
      ),
      const _RouteContract(
        method: 'DELETE',
        path: '/api/admin/backups/{param}',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/admin/server-backups',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/admin/server-backups/export.csv',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/admin/server-backups/run',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/admin/users/export.csv',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/admin/feedback/export.csv',
        location: '',
      ),
      const _RouteContract(
        method: 'PATCH',
        path: '/api/me/profile',
        location: '',
      ),
      const _RouteContract(method: 'POST', path: '/api/me/email', location: ''),
      const _RouteContract(
        method: 'POST',
        path: '/api/me/password',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/me/avatar',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/admin/users/{param}/coins',
        location: '',
      ),
    ]) {
      expect(
        _hasContract(clientCalls, call),
        isTrue,
        reason: '${call.method} ${call.path} should be extracted from lib/.',
      );
      expect(
        backendRoutes.any(
          (route) => route.method == call.method && _samePathShape(route, call),
        ),
        isTrue,
        reason: '${call.method} ${call.path} should exist in backend/main.py.',
      );
    }

    expect(
      clientCalls.any((call) => call.path.contains('api.github.com')),
      isFalse,
      reason: 'External GitHub release checks are not backend /api routes.',
    );
  });

  test('contract extractor covers compatibility and uri edge cases', () {
    const source = '''
Future<void> sample(ApiClient client) async {
  await _sendFirstAvailable(
    const ['PATCH', 'POST', 'PUT'],
    const ['/api/me/profile', '/api/auth/profile'],
    {},
  );
  await _postFirstAvailable(const [
    '/api/auth/email-code',
    '/api/auth/email-code/send',
  ], {});
  await _getFirstAvailable(const ['/api/auth/me', '/api/me']);
  await _uploadFirstAvailable(const [
    '/api/me/avatar',
    '/api/auth/avatar',
  ], fieldName: 'avatar', filename: 'a.png', bytes: bytes);
  final request = http.MultipartRequest(
    'POST',
    Uri.parse('/api/me/avatar'),
  );
  final multipartPathUri = http.MultipartRequest(
    'POST',
    Uri(path: '/api/auth/avatar'),
  );
  final response = await http.get(Uri(path: '/api/config'));
  final httpsResponse = await http.get(
    Uri.https('example.test', '/api/mobile/apps/duoyi/update', {
      'current_version_code': '1',
    }),
  );
  final httpResponse = await http.post(
    Uri.http('example.test', '/api/feedback', {'page': '1'}),
  );
  final feedbackReplyResponse = await http.post(
    Uri.https('example.test', '/api/admin/feedback/reply', {
      'source': 'uri-fixture',
    }),
  );
  final feedbackItemUri = Uri(
    path: '/api/admin/feedback/\$feedbackId',
    queryParameters: {'include': 'detail'},
  );
  await http.delete(feedbackItemUri);
  final aliasedUri = Uri.https('example.test', '/api/admin/overview', {
    'scope': 'summary',
  });
  await http.get(aliasedUri);
  final backendUri = _backendUri(base, '/api/mobile/apps/duoyi/update');
  await http.get(backendUri);
  final Uri typedUri = Uri(path: '/api/announcements', queryParameters: {
    'limit': '5',
  });
  await http.get(typedUri);
  static const String typedPath = '/api/admin/audit-log';
  await client.get(typedPath);
  const apiBase = '/api/admin';
  final joinedPath = apiBase + '/users';
  await client.get(joinedPath);
  await client.delete('/api/admin/users/' + userId);
  await client.getList('/api/announcements');
  await client.post('/api/reminders/email/once', {});
  await client.delete('/api/reminders/email/\$reminderId');
  await client.streamLines('/api/sync/events');
  await client.getRaw(_path('/api/admin/backups', {'limit': 20}));
  await client.getText(_path('/api/admin/backups/export.csv', {'limit': 20}));
  await client.post('/api/focus-rooms/\${Uri.encodeComponent(roomId)}/leave');
  const methods = ['PATCH', 'POST'];
  const profileFallbacks = ['/api/me/profile', '/api/auth/profile'];
  await _sendFirstAvailable(methods, profileFallbacks, {});
	  const avatarFallbacks = ['/api/account/avatar'];
	  await _uploadFirstAvailable(avatarFallbacks, fieldName: 'avatar', filename: 'a.png', bytes: bytes);
	  await client.request('PATCH', '/api/admin/settings', {});
	  await client.requestWithoutRouteDiagnosis('PATCH', '/api/admin/system-settings', {});
	  await client.request(method: 'DELETE', path: '/api/admin/feedback/123');
	}
	''';
    final calls = [
      ..._literalApiMethodCalls(source, 'synthetic.dart'),
      ..._nestedPathApiMethodCalls(source, 'synthetic.dart'),
      ..._firstAvailableApiCalls(source, 'synthetic.dart', syntaxPolicy: _ApiSyntaxPolicy.legacyLocalStaticText),
      ..._multipartApiCalls(source, 'synthetic.dart'),
      ..._uriPathApiCalls(source, 'synthetic.dart'),
      ..._httpUriConstructorApiCalls(source, 'synthetic.dart'),
      ..._httpUriAliasApiCalls(source, 'synthetic.dart', syntaxPolicy: _ApiSyntaxPolicy.legacyLocalStaticText),
      ..._localLiteralAliasApiCalls(source, 'synthetic.dart', syntaxPolicy: _ApiSyntaxPolicy.legacyLocalStaticText),
      ..._genericRequestApiCalls(source, 'synthetic.dart'),
      ..._concatenatedApiMethodCalls(source, 'synthetic.dart'),
    ];

    for (final call in [
      const _RouteContract(
        method: 'PATCH',
        path: '/api/me/profile',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/auth/profile',
        location: '',
      ),
      const _RouteContract(
        method: 'PUT',
        path: '/api/me/profile',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/auth/email-code',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/auth/email-code/send',
        location: '',
      ),
      const _RouteContract(method: 'GET', path: '/api/auth/me', location: ''),
      const _RouteContract(method: 'GET', path: '/api/me', location: ''),
      const _RouteContract(
        method: 'POST',
        path: '/api/me/avatar',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/auth/avatar',
        location: '',
      ),
      const _RouteContract(
        method: 'PATCH',
        path: '/api/account/avatar',
        location: '',
      ),
      const _RouteContract(
        method: 'PUT',
        path: '/api/account/avatar',
        location: '',
      ),
      const _RouteContract(method: 'GET', path: '/api/config', location: ''),
      const _RouteContract(
        method: 'GET',
        path: '/api/mobile/apps/duoyi/update',
        location: '',
      ),
      const _RouteContract(method: 'POST', path: '/api/feedback', location: ''),
      const _RouteContract(
        method: 'POST',
        path: '/api/admin/feedback/reply',
        location: '',
      ),
      const _RouteContract(
        method: 'DELETE',
        path: '/api/admin/feedback/{param}',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/admin/overview',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/announcements',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/admin/audit-log',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/admin/users',
        location: '',
      ),
      const _RouteContract(
        method: 'DELETE',
        path: '/api/admin/users/{param}',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/announcements',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/sync/events',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/admin/backups',
        location: '',
      ),
      const _RouteContract(
        method: 'GET',
        path: '/api/admin/backups/export.csv',
        location: '',
      ),
      const _RouteContract(
        method: 'POST',
        path: '/api/focus-rooms/{param}/leave',
        location: '',
      ),
      const _RouteContract(
        method: 'PATCH',
        path: '/api/admin/settings',
        location: '',
      ),
      const _RouteContract(
        method: 'PATCH',
        path: '/api/admin/system-settings',
        location: '',
      ),
      const _RouteContract(
        method: 'DELETE',
        path: '/api/admin/feedback/{param}',
        location: '',
      ),
    ]) {
      expect(
        _hasContract(calls, call),
        isTrue,
        reason: '${call.method} ${call.path}',
      );
    }
    expect(
      calls
          .where((call) => call.path.startsWith('/api/admin/feedback/'))
          .map((call) => (call.method, call.path))
          .toSet(),
      {
        ('POST', '/api/admin/feedback/reply'),
        ('DELETE', '/api/admin/feedback/{param}'),
        ('DELETE', '/api/admin/feedback/123'),
      },
      reason: 'Feedback URI and generic calls must keep their method and path.',
    );
  });
  test('delimiter tokens keep preference GETs separate from config and register', () {
    const source = "prefs.get('auth_state');\n"
        "preferences.get('auth_state');\n"
        "client.get(\n"
        "  '/api/config',\n"
        ");\n"
        "client.post(\n"
        "  '/api/auth/register',\n"
        "  {},\n"
        ");\n";
    final calls = _literalApiMethodCalls(source, 'fixture.dart');
    expect(calls.map((call) => (call.method, call.path, call.location)).toList(), [
      ('GET', '/api/config', 'fixture.dart:3'),
      ('POST', '/api/auth/register', 'fixture.dart:6'),
    ]);
    expect(calls.any((call) => call.method == 'GET' && call.path == '/api/auth/register'), isFalse);
    expect(calls.any((call) => call.path.contains('\n') || call.path.contains('client.')), isFalse);

    final temp = Directory.systemTemp.createTempSync('duoyi-route-token-inventory-');
    try {
      File('${temp.path}/fixture.dart').writeAsStringSync(source);
      final literals = _extractApiLiterals(temp);
      expect(literals.map((literal) => (literal.path, literal.location)).toList(), [
        ('/api/auth/register', 'lib/fixture.dart:7'),
        ('/api/config', 'lib/fixture.dart:4'),
      ]);
    } finally {
      temp.deleteSync(recursive: true);
    }

    final backend = _extractBackendRoutes('@app.get("/api/config")\n@app.post("/api/auth/register")\n');
    final wrongMethod = _literalApiMethodCalls("client.get('/api/auth/register');", 'wrong.dart');
    expect(wrongMethod.map((call) => (call.method, call.path)).toList(), [('GET', '/api/auth/register')]);
    expect(_hasContract(backend, wrongMethod.single), isFalse);
    final unknown = _literalApiMethodCalls("client.post('/api/not-backed');", 'unknown.dart');
    expect(unknown.single.path, '/api/not-backed');
    expect(_hasContract(backend, unknown.single), isFalse);
  });

  test('raw escaped multiline and interpolation tokens retain routes', () {
    const source = r"""
prefs.get('it\'s auth_state');
prefs.get(r'raw\auth_state');
// client.get('/api/comment-only');
/* nested /* client.post('/api/nested-comment'); */ comment */
const diagnostic = "client.get('/api/string-only');";
client.get(
  r'/api/config',
);
client.get('/api/auth/m\u0065');
client.get('/api/con\x66ig');
client.get('/api/con\u{66}ig');
client.get('/api/con'
  r'fig');
client.get('''/api/announcements''');
client.post('/api/focus-rooms/${Uri.encodeComponent(room['id'])}/leave');
client.get('/api/admin/users/${lookup({'id': client.get('/api/config')})}');
client.get(r'/api/$literal');
client.get('/api/\$escaped');
""";
    final calls = _literalApiMethodCalls(source, 'tokens.dart');
    expect(calls.map((call) => (call.method, call.path)).toList(), [
      ('GET', '/api/config'),
      ('GET', '/api/auth/me'),
      ('GET', '/api/config'),
      ('GET', '/api/config'),
      ('GET', '/api/config'),
      ('GET', '/api/announcements'),
      ('POST', '/api/focus-rooms/{param}/leave'),
      ('GET', '/api/admin/users/{param}'),
      ('GET', '/api/config'),
      ('GET', r'/api/$literal'),
      ('GET', r'/api/$escaped'),
    ]);
    expect(calls.any((call) => call.path.contains('comment') || call.path.contains('string-only')), isFalse);
    final lex = _DartRouteSource(source);
    expect(lex.strings.values.any((token) => token.value == r'/api/$literal'), isTrue);
    expect(lex.strings.values.any((token) => token.value == '/api/focus-rooms/{param}/leave'), isTrue);
    expect(lex.joinedStrings().where((token) => token.value == '/api/config'), hasLength(5));
    for (final call in calls) {
      expect(call.path, isNot(contains('\n')));
    }
  });

  test('balanced URI concat fallback and named arguments cannot cross calls', () {
    const source = r"""
http.get(
  Uri.https('example.test', '/api/mobile/apps/duoyi/update', {'q': ']);'}),
);
http.post(Uri.http('example.test', '/api/feedback'));
http.delete(Uri.parse('/api/admin/feedback/123'));
http.get(Uri(path: '/api/announcements', queryParameters: {'q': ')'}));
final Uri actual = Uri.https('example.test', '/api/admin/overview');
final Uri unused = Uri.parse('/api/unused-uri');
http.get(actual);
const base = '/api/admin';
final joined = base + '/users';
const unusedPath = '/api/unused-path';
client.get(joined);
client.delete('/api/admin/users/' + userId);
client.getRaw(_path('/api/admin/backups', {'q': '],);'}));
_getPage('/api/sync/status');
_sendFirstAvailable(const ['PATCH', 'POST'], const ['/api/me/profile', '/api/auth/profile'], {});
const methods = ['PUT', 'PATCH'];
const paths = ['/api/me/profile'];
_sendFirstAvailable(methods, paths, {});
_postFirstAvailable(const ['/api/auth/email-code'], {});
_postEmailCodeFirstAvailable(const ['/api/me/email-code'], {});
_getRawFirstAvailable(const ['/api/admin/backups/export.csv']);
_getFirstAvailable(const ['/api/auth/me', '/api/me']);
_uploadFirstAvailable(const ['/api/me/avatar'], fieldName: 'avatar');
http.MultipartRequest('POST', Uri(path: '/api/me/avatar'));
client.request(method: 'GET', path: 'not-an-api-path');
client.request(path: '/api/admin/feedback/123', method: 'DELETE');
client.requestWithoutRouteDiagnosis('PATCH', '/api/admin/settings', {});
_sendFeedbackActionForAudit('POST', '/api/must-not-extract', {});
""";
    final calls = [
      ..._httpUriParseApiCalls(source, 'balanced.dart'),
      ..._httpUriConstructorApiCalls(source, 'balanced.dart'),
      ..._httpUriAliasApiCalls(source, 'balanced.dart', syntaxPolicy: _ApiSyntaxPolicy.statementFragment),
      ..._uriPathApiCalls(source, 'balanced.dart'),
      ..._localLiteralAliasApiCalls(source, 'balanced.dart', syntaxPolicy: _ApiSyntaxPolicy.statementFragment),
      ..._concatenatedApiMethodCalls(source, 'balanced.dart'),
      ..._nestedPathApiMethodCalls(source, 'balanced.dart'),
      ..._getPageApiCalls(source, 'balanced.dart'),
      ..._firstAvailableApiCalls(source, 'balanced.dart', syntaxPolicy: _ApiSyntaxPolicy.statementFragment),
      ..._multipartApiCalls(source, 'balanced.dart'),
      ..._genericRequestApiCalls(source, 'balanced.dart'),
    ];
    for (final route in [
      ('GET', '/api/mobile/apps/duoyi/update'),
      ('POST', '/api/feedback'),
      ('DELETE', '/api/admin/feedback/123'),
      ('GET', '/api/announcements'),
      ('GET', '/api/admin/overview'),
      ('GET', '/api/admin/users'),
      ('DELETE', '/api/admin/users/{param}'),
      ('GET', '/api/admin/backups'),
      ('GET', '/api/sync/status'),
      ('PATCH', '/api/me/profile'),
      ('POST', '/api/me/profile'),
      ('PUT', '/api/me/profile'),
      ('PATCH', '/api/auth/profile'),
      ('POST', '/api/auth/profile'),
      ('POST', '/api/auth/email-code'),
      ('POST', '/api/me/email-code'),
      ('GET', '/api/admin/backups/export.csv'),
      ('GET', '/api/auth/me'),
      ('GET', '/api/me'),
      ('POST', '/api/me/avatar'),
      ('PATCH', '/api/me/avatar'),
      ('PUT', '/api/me/avatar'),
      ('PATCH', '/api/admin/settings'),
    ]) {
      expect(calls.any((call) => call.method == route.$1 && call.path == route.$2), isTrue, reason: route.toString());
    }
    expect(calls.any((call) => call.path.contains('unused') || call.path.contains('must-not-extract')), isFalse);
    final generic = _genericRequestApiCalls(source, 'balanced.dart');
    expect(generic.map((call) => (call.method, call.path)).toList(), [
      ('DELETE', '/api/admin/feedback/123'),
      ('PATCH', '/api/admin/settings'),
    ]);
  });

  test('unterminated Dart tokens fail closed instead of reaching later routes', () {
    expect(() => _DartRouteSource("prefs.get('auth_state\nclient.get('/api/config');"), throwsFormatException);
    expect(() => _DartRouteSource(r"client.get('/api/${unclosed');"), throwsFormatException);
    expect(() => _DartRouteSource('/* unclosed'), throwsFormatException);
  });

  test('conditional URI aliases retain every branch and consumer method', () {
    const source = "final Uri choice = flag\n"
        "  ? Uri.parse('/api/config')\n"
        "  : Uri.https('example.test', '/api/auth/register');\n"
        "await http.get(choice);\n"
        "client.get('/api/config');\n"
        "client.post('/api/auth/register', {});\n"
        "final Uri unused = flag ? Uri.parse('/api/not-consumed-a') : Uri(path: '/api/not-consumed-b');\n"
        "const decoy = \"Uri.parse('/api/quoted-decoy')\";\n"
        "/* Uri.parse('/api/comment-decoy'); */\n"
        "final Uri nested = flag\n"
        "  ? (other ? Uri(path: '/api/me') : Uri.http('example.test', '/api/auth/me'))\n"
        "  : _backendUri(base, '/api/announcements');\n"
        "await http.post(nested);\n";
    final aliasCalls = _httpUriAliasApiCalls(source, 'conditional.dart', syntaxPolicy: _ApiSyntaxPolicy.statementFragment);
    expect(aliasCalls.map((call) => (call.method, call.path, call.location)).toList(), [
      ('GET', '/api/config', 'conditional.dart:4 via conditional.dart:1'),
      ('GET', '/api/auth/register', 'conditional.dart:4 via conditional.dart:1'),
      ('POST', '/api/me', 'conditional.dart:13 via conditional.dart:10'),
      ('POST', '/api/auth/me', 'conditional.dart:13 via conditional.dart:10'),
      ('POST', '/api/announcements', 'conditional.dart:13 via conditional.dart:10'),
    ]);
    expect(aliasCalls.any((call) => call.path.contains('not-consumed') || call.path.contains('decoy')), isFalse);

    final direct = _literalApiMethodCalls(source, 'conditional.dart');
    expect(direct.map((call) => (call.method, call.path)).toList(), [
      ('GET', '/api/config'),
      ('POST', '/api/auth/register'),
    ]);
    final backend = _extractBackendRoutes('@app.get("/api/config")\n@app.post("/api/auth/register")\n');
    final choiceCalls = aliasCalls.take(2).toList();
    // Successful direct calls and global literal coverage cannot excuse an
    // incompatible method on the conditional alias's actual consumer.
    expect(_hasContract(direct, choiceCalls.first), isTrue);
    expect(direct.any((call) => call.method == 'POST' && call.path == '/api/auth/register'), isTrue);
    expect(choiceCalls.where((call) => !_hasContract(backend, call)).map((call) => (call.method, call.path)).toList(), [
      ('GET', '/api/auth/register'),
    ]);
    expect(_hasContract(backend, choiceCalls.last), isFalse);
    final replaced = source.replaceFirst('await http.get(choice);', 'await http.post(choice);');
    expect(_httpUriAliasApiCalls(replaced, 'post.dart', syntaxPolicy: _ApiSyntaxPolicy.statementFragment).take(2).map((call) => (call.method, call.path)).toList(), [
      ('POST', '/api/config'),
      ('POST', '/api/auth/register'),
    ]);
    final withoutConsumer = source.replaceFirst('await http.get(choice);', '');
    expect(_httpUriAliasApiCalls(withoutConsumer, 'unused.dart', syntaxPolicy: _ApiSyntaxPolicy.statementFragment).any((call) => call.path == '/api/config' || call.path == '/api/auth/register'), isFalse);
  });

  test('CR LF and CRLF comments preserve wrong method calls and locations', () {
    for (final newline in ['\r', '\n', '\r\n']) {
      final source = '// note$newline'
          "client.get('/api/auth/register');$newline"
          "client.post('/api/auth/register', {});$newline"
          "client.get('/api/config');$newline";
      final lex = _DartRouteSource(source);
      final calls = _literalApiMethodCalls(source, 'newlines.dart');
      expect(lex.code.length, source.length);
      expect(calls.map((call) => (call.method, call.path, call.location)).toList(), [
        ('GET', '/api/auth/register', 'newlines.dart:2'),
        ('POST', '/api/auth/register', 'newlines.dart:3'),
        ('GET', '/api/config', 'newlines.dart:4'),
      ], reason: newline.codeUnits.toString());
      final tokens = lex.joinedStrings();
      expect(tokens.map((token) => (token.value, _lineOf(source, token.start))).toList(), [
        ('/api/auth/register', 2),
        ('/api/auth/register', 3),
        ('/api/config', 4),
      ]);
      final backend = _extractBackendRoutes('@app.get("/api/config")\n@app.post("/api/auth/register")\n');
      expect(calls.where((call) => !_hasContract(backend, call)).map((call) => (call.method, call.path)).toList(), [
        ('GET', '/api/auth/register'),
      ]);
    }
    expect(_lineOf('one\r\ntwo\rthree\nfour', 'one\r\ntwo\rthree\nfour'.length), 4);
  });
  test('constant concat keeps real suffix and independent source coverage', () {
    final temp = Directory.systemTemp.createTempSync('duoyi-concat-controls-');
    try {
      final file = File('${temp.path}/fixture.dart');
      file.writeAsStringSync("void sample(dynamic client) {\n"
          "  client.get('/api/config' + '/missing');\n"
          "  client.get('/api/config');\n"
          "}\n");
      final calls = _extractClientCalls(temp, syntaxPolicy: _ApiSyntaxPolicy.compilationUnit);
      expect(calls.map((c) => (c.method, c.path, c.location)).toList(), [
        ('GET', '/api/config/missing', 'lib/fixture.dart:2'),
        ('GET', '/api/config', 'lib/fixture.dart:3'),
      ]);
      final inventory = _extractApiLiterals(temp);
      expect(inventory.map((i) => (i.path, i.coveragePath, i.location)).toSet(), {
        ('/api/config', '/api/config/missing', 'lib/fixture.dart:2'),
        ('/api/config', '/api/config', 'lib/fixture.dart:3'),
      });
      final backend = _extractBackendRoutes('@app.get("/api/config")\n@app.get("/api/config/static")\n');
      expect(calls.where((c) => !_hasContract(backend, c)).map((c) => c.path), ['/api/config/missing']);
      expect(inventory.where((i) => !calls.any((c) => c.path == i.coveragePath)), isEmpty);

      file.writeAsStringSync("void sample(dynamic client) {\n"
          "  client.get('/api/config' + '/static');\n"
          "}\n");
      final sole = _extractClientCalls(temp, syntaxPolicy: _ApiSyntaxPolicy.compilationUnit);
      final soleInventory = _extractApiLiterals(temp);
      expect(sole.map((c) => (c.method, c.path, c.location)).toList(), [
        ('GET', '/api/config/static', 'lib/fixture.dart:2'),
      ]);
      expect(soleInventory.single.path, '/api/config');
      expect(soleInventory.single.coveragePath, '/api/config/static');
      expect(soleInventory.single.sourceTokens.map((t) => t.value).toList(), ['/api/config', '/static']);
      expect(soleInventory.single.unresolved, isNull);
      expect(_hasContract(backend, sole.single), isTrue);
    } finally {
      temp.deleteSync(recursive: true);
    }
  });

  test('concat inventory retains unconsumed aliases and same-line expressions', () {
    final temp = Directory.systemTemp.createTempSync('duoyi-concat-inventory-');
    try {
      final file = File('${temp.path}/fixture.dart');
      file.writeAsStringSync("void sample(dynamic client) {\n"
          "  const route = '/api/config' + '/static';\n"
          "  client.get(route);\n"
          "}\n");
      final calls = _extractClientCalls(temp, syntaxPolicy: _ApiSyntaxPolicy.compilationUnit);
      expect(calls.map((c) => (c.method, c.path, c.location)).toList(), [
        ('GET', '/api/config/static', 'lib/fixture.dart:3 via lib/fixture.dart:2'),
      ]);
      expect(_extractApiLiterals(temp).single.coveragePath, '/api/config/static');

      file.writeAsStringSync("void sample(dynamic client) {\n"
          "  const unused = '/api/config' + '/static';\n"
          "  client.get('/api/config');\n"
          "}\n");
      final prefixOnly = _extractClientCalls(temp, syntaxPolicy: _ApiSyntaxPolicy.compilationUnit);
      final unconsumed = _extractApiLiterals(temp);
      expect(prefixOnly.map((c) => (c.method, c.path, c.location)).toList(), [
        ('GET', '/api/config', 'lib/fixture.dart:3'),
      ]);
      expect(unconsumed.where((i) => !prefixOnly.any((c) => c.path == i.coveragePath))
          .map((i) => (i.coveragePath, i.location)).toList(), [
        ('/api/config/static', 'lib/fixture.dart:2'),
      ]);

      file.writeAsStringSync("void sample(dynamic client) {\n"
          "  const good = '/api/config' + '/static'; const unused = '/api/config' + '/missing'; client.get(good);\n"
          "}\n");
      final sameLine = _extractApiLiterals(temp);
      expect(sameLine, hasLength(2));
      expect(sameLine.map((i) => (i.path, i.coveragePath, i.location)).toSet(), {
        ('/api/config', '/api/config/static', 'lib/fixture.dart:2'),
        ('/api/config', '/api/config/missing', 'lib/fixture.dart:2'),
      });
      expect(sameLine.map((i) => i.expressionStart).toSet(), hasLength(2));
      expect(_extractClientCalls(temp, syntaxPolicy: _ApiSyntaxPolicy.compilationUnit).map((c) => (c.method, c.path, c.location)).toList(), [
        ('GET', '/api/config/static', 'lib/fixture.dart:2 via lib/fixture.dart:2'),
      ]);
    } finally {
      temp.deleteSync(recursive: true);
    }
  });

  test('concat preserves one bounded segment joined tokens and assembled roots', () {
    final temp = Directory.systemTemp.createTempSync('duoyi-concat-segment-');
    try {
      final file = File('${temp.path}/fixture.dart');
      file.writeAsStringSync("void sample(dynamic client, String userId) {\n"
          "  client.delete('/api/admin/users/' + userId);\n"
          "  client.post('/api/admin/users/' + userId + '/coins');\n"
          "  client.get('/a' + 'pi/config' + '/static');\n"
          "  client.get('/api/con' r'fig' /* part */ + '/static');\n"
          "}\n");
      final calls = _extractClientCalls(temp, syntaxPolicy: _ApiSyntaxPolicy.compilationUnit);
      expect(calls.map((c) => (c.method, c.path, c.location)).toList(), [
        ('DELETE', '/api/admin/users/{param}', 'lib/fixture.dart:2'),
        ('POST', '/api/admin/users/{param}/coins', 'lib/fixture.dart:3'),
        ('GET', '/api/config/static', 'lib/fixture.dart:4'),
        ('GET', '/api/config/static', 'lib/fixture.dart:5'),
      ]);
      final inventory = _extractApiLiterals(temp);
      expect(inventory, hasLength(4));
      expect(inventory.map((i) => (i.path, i.coveragePath, i.location)).toSet(), {
        ('/api/admin/users', '/api/admin/users/{param}', 'lib/fixture.dart:2'),
        ('/api/admin/users', '/api/admin/users/{param}/coins', 'lib/fixture.dart:3'),
        ('/api/config/static', '/api/config/static', 'lib/fixture.dart:4'),
        ('/api/config', '/api/config/static', 'lib/fixture.dart:5'),
      });
      expect(inventory.singleWhere((i) => i.location == 'lib/fixture.dart:4')
          .sourceTokens.map((t) => t.value).toList(), ['/a', 'pi/config', '/static']);
      expect(inventory.singleWhere((i) => i.location == 'lib/fixture.dart:5')
          .sourceTokens.map((t) => t.value).toList(), ['/api/con', 'fig', '/static']);
      expect(inventory.every((i) => i.unresolved == null), isTrue);
    } finally {
      temp.deleteSync(recursive: true);
    }
  });

  test('unsupported concat remains an inventory failure despite prefix calls', () {
    final temp = Directory.systemTemp.createTempSync('duoyi-concat-unresolved-');
    try {
      final file = File('${temp.path}/fixture.dart');
      for (final expression in [
        "'/api/config' + (flag ? '/static' : '/missing')",
        "'/api/admin/users/' + userId + '/' + secondId",
        "'/api/config' + userId",
        "host + '/api/config'",
        "'/api/config' +",
      ]) {
        file.writeAsStringSync('void sample(dynamic client, bool flag) {\n'
            '  const unused = $expression;\n'
            "  client.get('/api/config');\n"
            '}\n');
        final inventory = _extractApiLiterals(temp);
        expect(inventory.where((i) => i.unresolved != null), isNotEmpty, reason: expression);
        expect(inventory.where((i) => i.location == 'lib/fixture.dart:3').single.unresolved, isNull);
      }
      file.writeAsStringSync('void sample(dynamic client, bool flag) {\n'
          "  client.get('/api/config' + (flag ? '/static' : '/missing'));\n"
          "  client.get('/api/config');\n"
          '}\n');
      expect(() => _extractClientCalls(temp, syntaxPolicy: _ApiSyntaxPolicy.compilationUnit), throwsFormatException);
      expect(_extractApiLiterals(temp).where((i) => i.unresolved != null).single.location,
          'lib/fixture.dart:2');
    } finally {
      temp.deleteSync(recursive: true);
    }
  });

  test('concat boundaries preserve nested path getPage and list entry inventory', () {
    final temp = Directory.systemTemp.createTempSync('duoyi-concat-boundary-');
    try {
      File('${temp.path}/fixture.dart').writeAsStringSync(
          "void sample(dynamic client) {\n"
          "  client.getRaw(_path('/api/config' + '/static', {'q': '],);'}));\n"
          "  _getPage('/api/config' + '/static');\n"
          "  const unused = ['/api/config' + '/missing', '/api/me'];\n"
          "}\n");
      expect(_extractClientCalls(temp, syntaxPolicy: _ApiSyntaxPolicy.compilationUnit).map((c) => (c.method, c.path, c.location)).toList(), [
        ('GET', '/api/config/static', 'lib/fixture.dart:2'),
        ('GET', '/api/config/static', 'lib/fixture.dart:3'),
      ]);
      expect(_extractApiLiterals(temp).map((i) => (i.coveragePath, i.location)).toSet(), {
        ('/api/config/static', 'lib/fixture.dart:2'),
        ('/api/config/static', 'lib/fixture.dart:3'),
        ('/api/config/missing', 'lib/fixture.dart:4'),
        ('/api/me', 'lib/fixture.dart:4'),
      });
    } finally {
      temp.deleteSync(recursive: true);
    }
  });
  test('rejected and computed API concat always retain a failed source obligation', () {
    final temp = Directory.systemTemp.createTempSync('duoyi-concat-rejected-');
    try {
      final file = File('${temp.path}/fixture.dart');
      // Each complete expression is handwritten, consumer-free, and followed
      // by a real legal prefix call which must not discharge the failure.
      for (final expression in [
        "'/api/config' + '//missing'",
        "'/api/config' + '/has space'",
        "'/a' + 'pi/config' + '/has space'",
        "'/a' + 'pi/config/' + userId + '/' + secondId",
        "(flag ? '/api/config' : '/api/config') + '/missing'",
        "wrap('/api/config') + '/missing'",
        "'/api/config/' + userId + '//missing'",
      ]) {
        file.writeAsStringSync('void sample(dynamic client, bool flag, String userId, String secondId) {\n'
            '  final unused = $expression;\n'
            "  client.get('/api/config');\n"
            '}\n');
        final calls = _extractClientCalls(temp, syntaxPolicy: _ApiSyntaxPolicy.compilationUnit);
        expect(calls.map((c) => (c.method, c.path, c.location)).toList(), [
          ('GET', '/api/config', 'lib/fixture.dart:3'),
        ], reason: expression);
        final inventory = _extractApiLiterals(temp);
        final failed = inventory.where((i) => i.unresolved != null).toList();
        expect(failed, hasLength(1), reason: expression);
        expect(failed.single.location, 'lib/fixture.dart:2');
        expect(failed.single.expressionStart, isNotNull);
        expect(failed.single.expressionEnd,
            greaterThan(failed.single.expressionStart!));
        expect(failed.single.sourceTokens, isNotEmpty);
        expect(inventory.where((i) => i.location == 'lib/fixture.dart:3')
            .single.unresolved, isNull);
      }

      file.writeAsStringSync('void sample(dynamic client) {\n'
          "  client.get('/a' + 'pi/config' + '/has space');\n"
          "  client.get('/api/config');\n"
          '}\n');
      expect(() => _extractClientCalls(temp, syntaxPolicy: _ApiSyntaxPolicy.compilationUnit), throwsFormatException);
      final assembledFailure = _extractApiLiterals(temp)
          .where((i) => i.unresolved != null).single;
      expect(assembledFailure.location, 'lib/fixture.dart:2');
      expect(assembledFailure.sourceTokens.map((t) => t.value).toList(),
          ['/a', 'pi/config', '/has space']);

      file.writeAsStringSync('void sample(dynamic client, bool flag) {\n'
          "  final unused = wrap('/api/config') + '/missing';\n"
          "  client.get('/api/config');\n"
          '}\n');
      final computedFailure = _extractApiLiterals(temp)
          .where((i) => i.unresolved != null).single;
      expect(computedFailure.sourceTokens.map((t) => t.value).toList(),
          ['/api/config', '/missing']);

      file.writeAsStringSync('void sample(dynamic client, String userId) {\n'
          "  client.get('auth_state-' + userId);\n"
          "  client.get('/api/config');\n"
          '}\n');
      expect(_extractClientCalls(temp, syntaxPolicy: _ApiSyntaxPolicy.compilationUnit).map((c) => (c.method, c.path, c.location)).toList(), [
        ('GET', '/api/config', 'lib/fixture.dart:3'),
      ]);
      final nonApi = _extractApiLiterals(temp);
      expect(nonApi, hasLength(1));
      expect(nonApi.single.path, '/api/config');
      expect(nonApi.single.unresolved, isNull);
    } finally {
      temp.deleteSync(recursive: true);
    }
  });

}

List<_RouteContract> _extractBackendRoutes(String source) {
  final routePattern = RegExp(
    r'''@app\.(get|post|patch|delete|put)\(\s*(["'])(/api/[^"']*)\2''',
    multiLine: true,
  );
  return [
    for (final match in routePattern.allMatches(source))
      _RouteContract(
        method: match.group(1)!.toUpperCase(),
        path: _normalizePath(match.group(3)!),
        location: 'backend/main.py:${_lineOf(source, match.start)}',
      ),
  ];
}

List<_RouteContract> _extractClientCalls(Directory root, {
  required _ApiSyntaxPolicy syntaxPolicy,
}) {
  final calls = <_RouteContract>{};
  final files =
      root
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in files) {
    final source = file.readAsStringSync();
    final relativePath = file.path.replaceFirst('${root.path}/', 'lib/');
    final context = _apiContext(source, relativePath, policy: syntaxPolicy);
    calls.addAll(_literalApiMethodCalls(source, relativePath));
    calls.addAll(_nestedPathApiMethodCalls(source, relativePath));
    calls.addAll(_getPageApiCalls(source, relativePath));
    calls.addAll(_httpUriParseApiCalls(source, relativePath));
    calls.addAll(_httpUriConstructorApiCalls(source, relativePath));
    calls.addAll(_httpUriAliasApiCalls(source, relativePath, context: context));
    calls.addAll(_localLiteralAliasApiCalls(source, relativePath, context: context));
    calls.addAll(_concatenatedApiMethodCalls(source, relativePath));
    calls.addAll(_firstAvailableApiCalls(source, relativePath, context: context));
    calls.addAll(_multipartApiCalls(source, relativePath));
    calls.addAll(_uriPathApiCalls(source, relativePath));
    calls.addAll(_genericRequestApiCalls(source, relativePath));
    // Real aggregation admits every complete original unit; no fixture fallback.
    context.index;
    context.requireNoFatalIssues();
  }
  return calls.toList()..sort((a, b) => a.location.compareTo(b.location));
}

List<_ApiLiteral> _extractApiLiterals(Directory root) {
  final literals = <_ApiLiteral>{};
  final files = root.listSync(recursive: true).whereType<File>()
      .where((file) => file.path.endsWith('.dart')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    final source = file.readAsStringSync();
    final relativePath = file.path.replaceFirst('${root.path}/', 'lib/');
    final lex = _DartRouteSource(source);
    final syntheticExpressions = <int>{};
    final failedExpressions = <String>{};
    for (final token in lex.joinedStrings()) {
      // Preserve the exact original diagnostic exception, including real /api/.
      final prefix = source.substring(token.start > 32 ? token.start - 32 : 0, token.start);
      if (token.value == '/api/' && RegExp(r'\.\s*contains\(\s*$').hasMatch(prefix)) continue;
      final rawPath = _pathFromBackendApiLiteral(token.value);
      final expression = _concatExpressionAt(lex, token);
      if (expression == null) {
        if (rawPath != null) {
          literals.add(_ApiLiteral(rawPath, '$relativePath:${_lineOf(source, token.start)}'));
        }
        continue;
      }
      final apiTokens = expression.sourceTokens.where(
          (part) => _pathFromBackendApiLiteral(part.value) != null).toList();
      if (expression.unresolved != null && expression.sourceApiPath != null) {
        // Failure is a whole source obligation, independent of the currently
        // visited token and of whether a resolved coverage route exists.
        if (failedExpressions.add('${expression.start}:${expression.end}')) {
          literals.add(_ApiLiteral(
            expression.sourceApiPath!,
            '$relativePath:${_lineOf(source, expression.start)}',
            coverage: expression.path,
            expressionStart: expression.start,
            expressionEnd: expression.end,
            sourceTokens: expression.sourceTokens,
            unresolved: expression.unresolved,
          ));
        }
        continue;
      }
      if (rawPath != null) {
        literals.add(_ApiLiteral(
          rawPath, '$relativePath:${_lineOf(source, token.start)}',
          coverage: expression.path,
          expressionStart: expression.start,
          expressionEnd: expression.end,
          sourceTokens: expression.sourceTokens,
          unresolved: expression.unresolved,
        ));
      } else if (apiTokens.isEmpty && expression.path != null &&
          syntheticExpressions.add(expression.start)) {
        // No token had an API root: preserve real parts as expression evidence.
        literals.add(_ApiLiteral(
          expression.path!, '$relativePath:${_lineOf(source, expression.start)}',
          coverage: expression.path,
          expressionStart: expression.start,
          expressionEnd: expression.end,
          sourceTokens: expression.sourceTokens,
          unresolved: expression.unresolved,
        ));
      }
    }
  }
  return literals.toList()..sort((a, b) {
    final byPath = a.path.compareTo(b.path);
    if (byPath != 0) return byPath;
    final byLocation = a.location.compareTo(b.location);
    if (byLocation != 0) return byLocation;
    return (a.expressionStart ?? -1).compareTo(b.expressionStart ?? -1);
  });
}

List<String> _extractTextApiLiterals(Directory root) {
  if (!root.existsSync()) return const [];
  final files =
      root
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => _isAuditableTextFile(file.path))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final matches = <String>[];
  final apiPattern = RegExp(r'/api(?:/[A-Za-z0-9_{}.$%:+-]+)*');

  for (final file in files) {
    final source = file.readAsStringSync();
    for (final match in apiPattern.allMatches(source)) {
      matches.add('${file.path}:${_lineOf(source, match.start)} ${match[0]}');
    }
  }
  return matches;
}

bool _isAuditableTextFile(String path) {
  return path.endsWith('.html') ||
      path.endsWith('.json') ||
      path.endsWith('.js') ||
      path.endsWith('.css') ||
      path.endsWith('.txt') ||
      path.endsWith('.xml');
}

List<_RouteContract> _literalApiMethodCalls(String source, String filePath) {
  return _tokenPathCalls(source, filePath, RegExp(
    r'\.\s*(get|post|patch|put|delete|getList|getRaw|getText|streamLines|uploadBytes)\s*\(',
  ));
}

List<_RouteContract> _nestedPathApiMethodCalls(String source, String filePath) {
  return _tokenPathCalls(source, filePath, RegExp(
    r'\.\s*(get|post|patch|put|delete|getList|getRaw|getText|streamLines)\s*\(',
  ), nestedPath: true);
}

List<_RouteContract> _getPageApiCalls(String source, String filePath) {
  return _tokenPathCalls(source, filePath, RegExp(r'\b_getPage\s*\('), fixedMethod: 'GET');
}

List<_RouteContract> _httpUriParseApiCalls(String source, String filePath) {
  return _tokenPathCalls(source, filePath, RegExp(
    r'\bhttp\.(get|post|patch|delete|put)\s*\(',
  ), httpMethod: true, uri: true, uriConstructors: const {'Uri.parse'});
}

List<_RouteContract> _httpUriConstructorApiCalls(String source, String filePath) {
  return _tokenPathCalls(source, filePath, RegExp(
    r'\bhttp\.(get|post|patch|delete|put)\s*\(', caseSensitive: false,
  ), httpMethod: true, uri: true, uriConstructors: const {'Uri.https', 'Uri.http'});
}

List<_RouteContract> _httpUriAliasApiCalls(String source, String filePath, {
  _ApiSyntaxPolicy syntaxPolicy = _ApiSyntaxPolicy.compilationUnit,
  _ApiSourceContext? context,
}) {
  final ctx = context ?? _apiContext(source, filePath, policy: syntaxPolicy);
  final lex = ctx.lex;
  final calls = <_RouteContract>[];
  final prefix = RegExp(r'\bhttp\.(get|post|patch|delete|put)\s*\(');
  for (final match in prefix.allMatches(lex.code)) {
    final arguments = lex.arguments(match.end - 1);
    if (arguments.isEmpty) continue;
    final argument = arguments.first;
    final result = ctx.resolve(argument, _ApiValueKind.uri);
    if (!result.known) continue;
    final declaration = ctx.index.declarationAt(lex.trivia(argument.start));
    if (declaration == null) continue;
    for (final value in result.values!) {
      final path = _pathFromLiteral(value);
      if (path == null) continue;
      calls.add(_RouteContract(method: match.group(1)!.toUpperCase(), path: path,
        location: '$filePath:${_lineOf(source, match.start)} via '
          '$filePath:${_lineOf(source, declaration.declarationOffset)}'));
    }
  }
  for (final invocation in ctx.index.httpClientInvocations) {
    final arguments = invocation.argumentList.arguments;
    if (arguments.isEmpty) continue;
    final first = arguments.first;
    if (first is ast.NamedExpression) continue;
    final argument = _DartRouteArgument(ctx.index.originalOffset(first.offset),
        ctx.index.originalOffset(first.end));
    final result = ctx.resolve(argument, _ApiValueKind.uri);
    if (!result.known) continue;
    final declaration = ctx.index.declarationAt(lex.trivia(argument.start));
    if (declaration == null) continue;
    for (final value in result.values!) {
      final path = _pathFromLiteral(value);
      if (path == null) continue;
      calls.add(_RouteContract(method: invocation.methodName.name.toUpperCase(), path: path,
        location: '$filePath:${_lineOf(source, ctx.index.originalOffset(invocation.offset))} via '
          '$filePath:${_lineOf(source, declaration.declarationOffset)}'));
    }
  }
  ctx.requireNoFatalIssues();
  return calls;
}

List<_RouteContract> _localLiteralAliasApiCalls(String source, String filePath, {
  _ApiSyntaxPolicy syntaxPolicy = _ApiSyntaxPolicy.compilationUnit,
  _ApiSourceContext? context,
}) {
  final ctx = context ?? _apiContext(source, filePath, policy: syntaxPolicy);
  final lex = ctx.lex;
  final calls = <_RouteContract>[];
  final prefix = RegExp(
    r'\.\s*(get|post|patch|put|delete|getList|getRaw|getText|streamLines|uploadBytes)\s*\(',
  );
  for (final match in prefix.allMatches(lex.code)) {
    final arguments = lex.arguments(match.end - 1);
    if (arguments.isEmpty) continue;
    // The existing explicit http family consumes URI aliases, rather than
    // asking the String family to reject that same typed Uri declaration.
    if (RegExp(r'\bhttp\s*$').hasMatch(lex.code.substring(0, match.start))) continue;
    if (ctx.index.isHttpClientMethodAt(lex.trivia(match.start + 1))) continue;
    final argument = arguments.first;
    final result = ctx.resolve(argument, _ApiValueKind.string);
    if (result.values?.length != 1) continue;
    final path = _pathFromLiteral(result.values!.single);
    if (path == null) continue;
    final declaration = ctx.index.declarationAt(lex.trivia(argument.start));
    if (declaration == null) continue;
    calls.add(_RouteContract(method: _methodForClientCall(match.group(1)!), path: path,
      location: '$filePath:${_lineOf(source, match.start)} via '
        '$filePath:${_lineOf(source, declaration.declarationOffset)}'));
  }
  ctx.requireNoFatalIssues();
  return calls;
}

List<_RouteContract> _concatenatedApiMethodCalls(String source, String filePath) {
  return _tokenPathCalls(source, filePath, RegExp(
    r'\.\s*(get|post|patch|put|delete|getList|getRaw|getText|streamLines|uploadBytes)\s*\(',
  ), concatenated: true);
}

List<_RouteContract> _firstAvailableApiCalls(String source, String filePath, {
  _ApiSyntaxPolicy syntaxPolicy = _ApiSyntaxPolicy.compilationUnit,
  _ApiSourceContext? context,
}) {
  final ctx = context ?? _apiContext(source, filePath, policy: syntaxPolicy);
  final lex = ctx.lex;
  List<String>? values(_DartRouteArgument argument) =>
      lex.stringList(argument) ?? _stringListAliases(ctx, argument);
  final prefix = RegExp(
    r'\b(_sendFirstAvailable|_getRawFirstAvailable|_post(?:EmailCode)?FirstAvailable|_uploadFirstAvailable|_getFirstAvailable)\s*\(',
  );
  final calls = <_RouteContract>[];
  for (final match in prefix.allMatches(lex.code)) {
    final arguments = lex.arguments(match.end - 1);
    if (arguments.isEmpty) continue;
    final name = match.group(1)!;
    final sending = name == '_sendFirstAvailable';
    if (sending && arguments.length < 2) continue;
    final methods = sending
        ? values(arguments[0])
        : name == '_uploadFirstAvailable'
        ? const ['POST', 'PATCH', 'PUT']
        : name.startsWith('_get')
        ? const ['GET']
        : const ['POST'];
    final paths = values(arguments[sending ? 1 : 0]);
    if (methods == null || paths == null) continue;
    for (final method in methods) {
      for (final literal in paths) {
        final path = _pathFromLiteral(literal);
        if (path == null) continue;
        calls.add(_RouteContract(
          method: method.toUpperCase(),
          path: path,
          location: '$filePath:${_lineOf(source, match.start)}',
        ));
      }
    }
  }
  ctx.requireNoFatalIssues();
  return calls;
}

List<_RouteContract> _multipartApiCalls(String source, String filePath) {
  final lex = _DartRouteSource(source);
  final prefix = RegExp(r'\bMultipartRequest\s*\(', caseSensitive: false);
  final calls = <_RouteContract>[];
  for (final match in prefix.allMatches(lex.code)) {
    final arguments = lex.arguments(match.end - 1);
    if (arguments.length < 2) continue;
    final method = lex.literal(arguments[0])?.toUpperCase();
    if (!const {'GET', 'POST', 'PATCH', 'PUT', 'DELETE'}.contains(method)) continue;
    final value = _uriArgumentLiteral(lex, arguments[1], constructors: const {'Uri.parse', 'Uri'});
    if (value == null) continue;
    final path = _pathFromLiteral(value);
    if (path == null) continue;
    calls.add(_RouteContract(
      method: method!, path: path,
      location: '$filePath:${_lineOf(source, match.start)}',
    ));
  }
  return calls;
}

List<_RouteContract> _uriPathApiCalls(String source, String filePath) {
  return _tokenPathCalls(source, filePath, RegExp(
    r'\bhttp\.(get|post|patch|put|delete)\s*\(', caseSensitive: false,
  ), httpMethod: true, uri: true, uriConstructors: const {'Uri'});
}

List<_RouteContract> _genericRequestApiCalls(String source, String filePath) {
  final lex = _DartRouteSource(source);
  final prefix = RegExp(
    r'(?:\.\s*request(?:WithoutRouteDiagnosis)?|\b_send(?:Announcement|User|Feedback)Action)\s*\(',
    caseSensitive: false,
  );
  final calls = <_RouteContract>[];
  for (final match in prefix.allMatches(lex.code)) {
    final arguments = lex.arguments(match.end - 1);
    String? method;
    String? value;
    if (arguments.length >= 2) {
      method = lex.literal(arguments[0]);
      value = lex.literal(arguments[1]);
    }
    // Named arguments are bounded to this call, including reordered arguments.
    if (method == null && match.group(0)!.trimLeft().startsWith('.')) {
      for (final argument in arguments) {
        final label = RegExp(r'(method|path)\s*:\s*').matchAsPrefix(lex.code, argument.start);
        if (label == null) continue;
        final literal = lex.literal(_DartRouteArgument(lex.trivia(label.end), argument.end));
        if (label.group(1) == 'method') method = literal;
        if (label.group(1) == 'path') value = literal;
      }
    }
    final normalizedMethod = method?.toUpperCase();
    if (!const {'GET', 'POST', 'PATCH', 'PUT', 'DELETE'}.contains(normalizedMethod) || value == null) continue;
    final path = _pathFromLiteral(value);
    if (path == null) continue;
    calls.add(_RouteContract(
      method: normalizedMethod!, path: path,
      location: '$filePath:${_lineOf(source, match.start)}',
    ));
  }
  return calls;
}

List<String>? _stringListAliases(_ApiSourceContext context, _DartRouteArgument argument) =>
    context.resolve(argument, _ApiValueKind.stringList).values;

String _methodForClientCall(String method) {
  return switch (method) {
    'post' || 'uploadBytes' => 'POST',
    'patch' => 'PATCH',
    'put' => 'PUT',
    'delete' => 'DELETE',
    _ => 'GET',
  };
}

String? _pathFromLiteral(String literal) {
  final apiMatch = RegExp(r'/api(?=/|\?|$)').firstMatch(literal);
  if (apiMatch == null) return null;
  return _normalizePath(literal.substring(apiMatch.start));
}

String? _pathFromBackendApiLiteral(String literal) {
  final path = _pathFromLiteral(literal);
  if (path == null) return null;
  if (path.contains(RegExp(r'\s'))) return null;
  if (!RegExp(r'^/api(?:/[A-Za-z0-9_{}.$%:+-]+)*$').hasMatch(path)) {
    return null;
  }
  return path;
}

String _normalizePath(String path) {
  var normalized = path.split('?').first.trim();
  // Interpolation is normalized by the Dart token reader. Raw and escaped
  // dollar signs are literal path characters, not interpolation parameters.
  if (normalized.length > 1 && normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

bool _samePathShape(_RouteContract route, _RouteContract call) {
  final routeSegments = route.path.split('/');
  final callSegments = call.path.split('/');
  if (routeSegments.length != callSegments.length) return false;
  for (var i = 0; i < routeSegments.length; i += 1) {
    final routeSegment = routeSegments[i];
    final callSegment = callSegments[i];
    if (routeSegment == callSegment) continue;
    if (_isPathParam(routeSegment) || _isPathParam(callSegment)) continue;
    return false;
  }
  return true;
}

bool _isPathParam(String segment) =>
    segment.startsWith('{') && segment.endsWith('}');

bool _hasContract(List<_RouteContract> contracts, _RouteContract expected) {
  return contracts.any(
    (contract) =>
        contract.method == expected.method &&
        _samePathShape(contract, expected),
  );
}

int _lineOf(String source, int offset) {
  // CRLF is one line ending; standalone CR and LF also end Dart line comments.
  return RegExp(r'\r\n|\r|\n').allMatches(source.substring(0, offset)).length + 1;
}

class _RouteContract {
  final String method;
  final String path;
  final String location;

  const _RouteContract({
    required this.method,
    required this.path,
    required this.location,
  });

  @override
  bool operator ==(Object other) =>
      other is _RouteContract &&
      method == other.method &&
      path == other.path &&
      location == other.location;

  @override
  int get hashCode => Object.hash(method, path, location);
}

/// UTF-16 offsets stay aligned with RegExp and the original source diagnostics.
/// Strings are read once to their own delimiter; interpolation code is scanned
/// recursively, but its value contributes only a route parameter placeholder.
class _DartRouteSource {
  final String source;
  final List<int> _mask;
  final Map<int, _DartRouteString> strings = {};
  final Map<int, int> _argumentEnds = {};
  late final String code;

  _DartRouteSource(this.source) : _mask = source.codeUnits.toList() {
    var cursor = 0;
    while (cursor < source.length) {
      final commentEnd = _comment(cursor);
      if (commentEnd != null) {
        cursor = commentEnd;
      } else if (_stringStart(cursor)) {
        cursor = _string(cursor).end;
      } else {
        cursor++;
      }
    }
    code = String.fromCharCodes(_mask);
  }

  void _hide(int start, int end) {
    for (var i = start; i < end; i++) {
      if (_mask[i] != 10 && _mask[i] != 13) _mask[i] = 32;
    }
  }

  bool _stringStart(int offset) =>
      source[offset] == "'" || source[offset] == '"' ||
      (source[offset] == 'r' && offset + 1 < source.length &&
          (source[offset + 1] == "'" || source[offset + 1] == '"'));

  int? _comment(int offset) {
    if (source.startsWith('//', offset)) {
      var end = offset + 2;
      while (end < source.length && source[end] != '\r' && source[end] != '\n') {
        end++;
      }
      _hide(offset, end);
      return end;
    }
    if (!source.startsWith('/*', offset)) return null;
    var depth = 1;
    var cursor = offset + 2;
    while (cursor < source.length && depth > 0) {
      if (source.startsWith('/*', cursor)) {
        depth++;
        cursor += 2;
      } else if (source.startsWith('*/', cursor)) {
        depth--;
        cursor += 2;
      } else {
        cursor++;
      }
    }
    if (depth != 0) throw FormatException('Unterminated Dart comment', source, offset);
    _hide(offset, cursor);
    return cursor;
  }

  _DartRouteString _string(int start) {
    final raw = source[start] == 'r';
    final quoteStart = start + (raw ? 1 : 0);
    final quote = source[quoteStart];
    final tripleDelimiter = quote + quote + quote;
    final triple = source.startsWith(tripleDelimiter, quoteStart);
    final delimiter = triple ? tripleDelimiter : quote;
    var cursor = quoteStart + delimiter.length;
    _hide(start, cursor);
    _mask[start] = 64; // A non-whitespace token marker, never source code.
    final value = StringBuffer();
    while (cursor < source.length) {
      if (source.startsWith(delimiter, cursor)) {
        _hide(cursor, cursor + delimiter.length);
        _mask[cursor + delimiter.length - 1] = 64;
        final token = _DartRouteString(start, cursor + delimiter.length, value.toString());
        strings[start] = token;
        return token;
      }
      final char = source[cursor];
      if (!triple && (char == '\n' || char == '\r')) {
        throw FormatException('Newline in single-line Dart string', source, cursor);
      }
      if (!raw && char == r'\') {
        final escapeStart = cursor;
        cursor++;
        if (cursor >= source.length) break;
        final escaped = source[cursor++];
        const escapes = {'n': '\n', 'r': '\r', 't': '\t', 'b': '\b', 'f': '\f', 'v': '\u000b'};
        if (escapes.containsKey(escaped)) {
          value.write(escapes[escaped]);
        } else if (escaped == 'u' || escaped == 'x') {
          final braced = escaped == 'u' && cursor < source.length && source[cursor] == '{';
          final end = braced ? source.indexOf('}', cursor + 1) : cursor + (escaped == 'u' ? 4 : 2);
          final digitsStart = cursor + (braced ? 1 : 0);
          if (end < digitsStart || end > source.length) {
            throw FormatException('Unterminated Dart character escape', source, escapeStart);
          }
          final digits = source.substring(digitsStart, end);
          final scalar = int.tryParse(digits, radix: 16);
          if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(digits) || scalar == null || scalar > 0x10ffff || (braced && digits.length > 6)) {
            throw FormatException('Invalid Dart character escape', source, escapeStart);
          }
          value.write(String.fromCharCode(scalar));
          cursor = end + (braced ? 1 : 0);
        } else if (escaped == r'\' || escaped == "'" || escaped == '"' || escaped == r'$') {
          value.write(escaped);
        } else {
          throw FormatException('Unsupported Dart escape', source, escapeStart);
        }
        _hide(escapeStart, cursor);
        continue;
      }
      if (!raw && char == r'$' && cursor + 1 < source.length) {
        if (source[cursor + 1] == '{') {
          _hide(cursor, cursor + 2);
          cursor = _interpolation(cursor + 2);
          value.write('{param}');
          continue;
        }
        final identifier = RegExp(r'[A-Za-z_][A-Za-z0-9_]*').matchAsPrefix(source, cursor + 1);
        if (identifier != null) {
          _hide(cursor, identifier.end);
          cursor = identifier.end;
          value.write('{param}');
          continue;
        }
      }
      value.write(char);
      _hide(cursor, cursor + 1);
      cursor++;
    }
    throw FormatException('Unterminated Dart string', source, start);
  }

  int _interpolation(int cursor) {
    var depth = 1;
    while (cursor < source.length) {
      final commentEnd = _comment(cursor);
      if (commentEnd != null) {
        cursor = commentEnd;
      } else if (_stringStart(cursor)) {
        cursor = _string(cursor).end;
      } else if (source[cursor] == '{') {
        depth++;
        cursor++;
      } else if (source[cursor] == '}') {
        depth--;
        if (depth == 0) {
          _hide(cursor, cursor + 1);
          return cursor + 1;
        }
        cursor++;
      } else {
        cursor++;
      }
    }
    throw FormatException('Unterminated Dart interpolation', source, cursor);
  }

  int trivia(int offset) {
    while (offset < source.length && const [9, 10, 11, 12, 13, 32].contains(_mask[offset])) {
      offset++;
    }
    return offset;
  }

  _DartRouteString? stringAt(int offset) => strings[trivia(offset)];

  _DartRouteString _joinString(_DartRouteString first, Set<int> consumed) {
    final value = StringBuffer(first.value);
    var end = first.end;
    while (true) {
      final next = strings[trivia(end)];
      if (next == null) break;
      consumed.add(next.start);
      value.write(next.value);
      end = next.end;
    }
    return _DartRouteString(first.start, end, value.toString());
  }

  List<_DartRouteString> joinedStrings() {
    final ordered = strings.values.toList()..sort((a, b) => a.start.compareTo(b.start));
    final consumed = <int>{};
    return [
      for (final token in ordered)
        if (!consumed.contains(token.start)) _joinString(token, consumed),
    ];
  }

  /// Reads one balanced call/list; commas inside strings or nested expressions
  /// cannot escape into another argument or a later call.
  List<_DartRouteArgument> arguments(int open) {
    final closes = {'(': ')', '[': ']', '{': '}'};
    final first = source[open];
    final close = closes[first];
    if (close == null) throw ArgumentError.value(open, 'open');
    final stack = <String>[close];
    final result = <_DartRouteArgument>[];
    var start = trivia(open + 1);
    var cursor = start;
    while (cursor < source.length) {
      final token = strings[cursor];
      if (token != null) {
        cursor = token.end;
        continue;
      }
      final char = code[cursor];
      if (closes.containsKey(char)) {
        stack.add(closes[char]!);
      } else if (char == ')' || char == ']' || char == '}') {
        if (char != stack.last) throw FormatException('Mismatched Dart delimiter', source, cursor);
        stack.removeLast();
        if (stack.isEmpty) {
          _argumentEnds[open] = cursor + 1;
          final end = _trimEnd(cursor);
          if (start < end) result.add(_DartRouteArgument(start, end));
          return result;
        }
      } else if (char == ',' && stack.length == 1) {
        result.add(_DartRouteArgument(start, _trimEnd(cursor)));
        start = trivia(cursor + 1);
      }
      cursor++;
    }
    throw FormatException('Unterminated Dart arguments', source, open);
  }

  int _trimEnd(int offset) {
    while (offset > 0 && const [9, 10, 11, 12, 13, 32].contains(_mask[offset - 1])) {
      offset--;
    }
    return offset;
  }

  String? literal(_DartRouteArgument argument) {
    final first = stringAt(argument.start);
    if (first == null) return null;
    final token = _joinString(first, <int>{});
    return trivia(token.end) >= argument.end ? token.value : null;
  }

  List<String>? stringList(_DartRouteArgument argument) {
    var start = trivia(argument.start);
    final constant = RegExp(r'const\b\s*').matchAsPrefix(code, start);
    if (constant != null) start = trivia(constant.end);
    if (start >= argument.end || source[start] != '[') return null;
    final items = arguments(start);
    if (trivia(_argumentEnds[start]!) < argument.end) return null;
    final result = <String>[];
    for (final item in items) {
      final value = literal(item);
      if (value == null) return null;
      result.add(value);
    }
    return result;
  }

  int statementEnd(int start) {
    final closes = {'(': ')', '[': ']', '{': '}'};
    final stack = <String>[];
    var cursor = start;
    while (cursor < source.length) {
      final token = strings[cursor];
      if (token != null) {
        cursor = token.end;
        continue;
      }
      final char = code[cursor];
      if (char == ';' && stack.isEmpty) return cursor;
      if (closes.containsKey(char)) {
        stack.add(closes[char]!);
      } else if (char == ')' || char == ']' || char == '}') {
        if (stack.isEmpty || stack.removeLast() != char) {
          throw FormatException('Mismatched Dart initializer', source, cursor);
        }
      }
      cursor++;
    }
    throw FormatException('Unterminated Dart initializer', source, start);
  }

  List<_DartRouteArgument> expressionParts(String separator) {
    final closes = {'(': ')', '[': ']', '{': '}'};
    final stack = <String>[];
    final result = <_DartRouteArgument>[];
    var start = trivia(0);
    var cursor = start;
    while (cursor < source.length) {
      final token = strings[cursor];
      if (token != null) {
        cursor = token.end;
        continue;
      }
      final char = code[cursor];
      if (closes.containsKey(char)) {
        stack.add(closes[char]!);
      } else if (char == ')' || char == ']' || char == '}') {
        if (stack.isEmpty || stack.removeLast() != char) {
          throw FormatException('Mismatched Dart expression', source, cursor);
        }
      } else if (char == separator && stack.isEmpty) {
        result.add(_DartRouteArgument(start, _trimEnd(cursor)));
        start = trivia(cursor + 1);
      }
      cursor++;
    }
    if (stack.isNotEmpty) throw FormatException('Unterminated Dart expression', source);
    if (start < _trimEnd(source.length)) result.add(_DartRouteArgument(start, _trimEnd(source.length)));
    return result;
  }
}

class _DartRouteString {
  final int start;
  final int end;
  final String value;
  const _DartRouteString(this.start, this.end, this.value);
}

class _DartRouteArgument {
  final int start;
  final int end;
  const _DartRouteArgument(this.start, this.end);
}

List<_RouteContract> _tokenPathCalls(
  String source,
  String filePath,
  RegExp prefix, {
  String? fixedMethod,
  bool httpMethod = false,
  bool nestedPath = false,
  bool uri = false,
  Set<String>? uriConstructors,
  bool concatenated = false,
}) {
  final lex = _DartRouteSource(source);
  final calls = <_RouteContract>[];
  for (final match in prefix.allMatches(lex.code)) {
    final arguments = lex.arguments(match.end - 1);
    if (arguments.isEmpty) continue;
    var argument = arguments.first;
    if (nestedPath) {
      final nested = RegExp(r'_path\s*\(').matchAsPrefix(lex.code, argument.start);
      if (nested == null) continue;
      final nestedArguments = lex.arguments(nested.end - 1);
      if (nestedArguments.isEmpty) continue;
      argument = nestedArguments.first;
    }
    String? value;
    if (uri) {
      value = _uriArgumentLiteral(lex, argument, constructors: uriConstructors);
    } else {
      final first = lex.stringAt(argument.start);
      if (first == null) continue;
      final token = lex._joinString(first, <int>{});
      final after = lex.trivia(token.end);
      final hasConcat = after < argument.end && source[after] == '+';
      if (concatenated && !hasConcat) continue;
      value = hasConcat
          ? _boundedConcatPath(source.substring(argument.start, argument.end))
          : lex.literal(argument) ?? token.value;
    }
    if (value == null) continue;
    final path = _pathFromLiteral(value);
    if (path == null) continue;
    calls.add(_RouteContract(
      method: fixedMethod ?? (httpMethod ? match.group(1)!.toUpperCase() : _methodForClientCall(match.group(1)!)),
      path: path,
      location: '$filePath:${_lineOf(source, match.start)}',
    ));
  }
  return calls;
}

String? _uriArgumentLiteral(_DartRouteSource lex, _DartRouteArgument argument, {Set<String>? constructors}) {
  final prefix = RegExp(r'(Uri\.(?:parse|https|http)|Uri|_backendUri)\s*\(').matchAsPrefix(lex.code, argument.start);
  if (prefix == null) return null;
  final arguments = lex.arguments(prefix.end - 1);
  final constructor = prefix.group(1)!;
  if (constructors != null && !constructors.contains(constructor)) return null;
  if (constructor == 'Uri.parse') return arguments.isEmpty ? null : lex.literal(arguments.first);
  if (constructor != 'Uri') return arguments.length < 2 ? null : lex.literal(arguments[1]);
  for (final item in arguments) {
    final named = RegExp(r'path\s*:\s*').matchAsPrefix(lex.code, item.start);
    if (named != null) return lex.literal(_DartRouteArgument(lex.trivia(named.end), item.end));
  }
  return null;
}

/// A source expression is independent of whether a consumer was extracted.
/// Its offsets and original tokens remain available for inventory diagnostics.
class _ApiConcatExpression {
  final int start;
  final int end;
  final List<_DartRouteArgument> parts;
  final List<_DartRouteString> sourceTokens;
  final String? path;
  final String? sourceApiPath;
  final String? unresolved;

  const _ApiConcatExpression({
    required this.start,
    required this.end,
    required this.parts,
    required this.sourceTokens,
    required this.path,
    required this.sourceApiPath,
    required this.unresolved,
  });
}

int _concatOperandEnd(_DartRouteSource lex, int start) {
  var cursor = lex.trivia(start);
  final string = lex.stringAt(cursor);
  if (string != null) {
    cursor = lex._joinString(string, <int>{}).end;
  } else if (cursor < lex.source.length &&
      const ['(', '[', '{'].contains(lex.code[cursor])) {
    lex.arguments(cursor);
    cursor = lex._argumentEnds[cursor]!;
  } else {
    final word = RegExp(r'[A-Za-z0-9_$]+').matchAsPrefix(lex.code, cursor);
    if (word == null) return cursor;
    cursor = word.end;
  }
  // Keep postfix calls, property reads and indexes in the same operand. They
  // are evidence of unsupported computation, never a single bare segment.
  while (true) {
    final next = lex.trivia(cursor);
    if (next >= lex.source.length) return cursor;
    if (lex.code[next] == '.' || lex.code[next] == '?') {
      var nameStart = next + 1;
      if (lex.code[next] == '?') {
        if (nameStart >= lex.source.length || lex.code[nameStart] != '.') {
          return cursor;
        }
        nameStart++;
      }
      final name = RegExp(r'[A-Za-z_$][A-Za-z0-9_$]*')
          .matchAsPrefix(lex.code, lex.trivia(nameStart));
      if (name == null) return cursor;
      cursor = name.end;
    } else if (lex.code[next] == '(' || lex.code[next] == '[') {
      lex.arguments(next);
      cursor = lex._argumentEnds[next]!;
    } else {
      return cursor;
    }
  }
}

int? _precedingConcatOperand(_DartRouteSource lex, int edge) {
  edge = lex._trimEnd(edge);
  if (edge == 0) return null;
  for (final token in lex.joinedStrings()) {
    if (token.end == edge) return token.start;
  }
  final last = lex.code[edge - 1];
  if (last == ')' || last == ']' || last == '}') {
    final pairs = {')': '(', ']': '[', '}': '{'};
    final stack = <String>[pairs[last]!];
    var cursor = edge - 2;
    while (cursor >= 0) {
      _DartRouteString? ended;
      for (final token in lex.strings.values) {
        if (token.end == cursor + 1) {
          ended = token;
          break;
        }
      }
      if (ended != null) {
        cursor = ended.start - 1;
        continue;
      }
      final char = lex.code[cursor];
      if (pairs.containsKey(char)) {
        stack.add(pairs[char]!);
      } else if (const ['(', '[', '{'].contains(char)) {
        if (char != stack.last) return null;
        stack.removeLast();
        if (stack.isEmpty) {
          final before = lex._trimEnd(cursor);
          final receiver = RegExp(r'[A-Za-z_$][A-Za-z0-9_$]*(?:\s*\.\s*[A-Za-z_$][A-Za-z0-9_$]*)*$')
              .firstMatch(lex.code.substring(0, before));
          return receiver?.start ?? cursor;
        }
      }
      cursor--;
    }
    return null;
  }
  return RegExp(r'[A-Za-z0-9_$]+(?:\s*\.\s*[A-Za-z_$][A-Za-z0-9_$]*)*$')
      .firstMatch(lex.code.substring(0, edge))?.start;
}

_ApiConcatExpression? _concatExpressionAt(
  _DartRouteSource lex,
  _DartRouteString token,
) {
  var start = token.start;
  while (true) {
    final before = lex._trimEnd(start);
    if (before == 0 || lex.code[before - 1] != '+') break;
    final previous = _precedingConcatOperand(lex, before - 1);
    if (previous == null) {
      return _ApiConcatExpression(
        start: before - 1,
        end: token.end,
        parts: const [],
        sourceTokens: [token],
        path: null,
        sourceApiPath: _pathFromLiteral(token.value),
        unresolved: 'Cannot bound the preceding concat operand',
      );
    }
    start = previous;
  }
  final parts = <_DartRouteArgument>[];
  var cursor = start;
  var sawPlus = false;
  while (true) {
    final end = _concatOperandEnd(lex, cursor);
    if (end <= cursor) break;
    parts.add(_DartRouteArgument(cursor, end));
    cursor = end;
    final next = lex.trivia(cursor);
    if (next >= lex.source.length || lex.code[next] != '+') break;
    sawPlus = true;
    cursor = lex.trivia(next + 1);
  }
  if (parts.length < 2) {
    if (!sawPlus) return null;
    return _ApiConcatExpression(
      start: start,
      end: cursor,
      parts: parts,
      sourceTokens: [token],
      path: null,
      sourceApiPath: _pathFromLiteral(token.value),
      unresolved: 'Concat is missing its next operand',
    );
  }
  final end = parts.last.end;
  final originalTokens = lex.strings.values
      .where((part) => part.start >= start && part.end <= end)
      .toList()..sort((a, b) => a.start.compareTo(b.start));
  final values = [for (final part in parts) lex.literal(part)];
  // API provenance survives final-path rejection and computed operands. Join
  // only contiguous known runs; never erase an unknown to fabricate a route.
  String? sourceApiPath;
  var knownRun = StringBuffer();
  for (final value in values) {
    if (value == null) {
      sourceApiPath ??= _pathFromLiteral(knownRun.toString());
      knownRun = StringBuffer();
    } else {
      knownRun.write(value);
    }
  }
  sourceApiPath ??= _pathFromLiteral(knownRun.toString());
  for (final original in originalTokens) {
    sourceApiPath ??= _pathFromLiteral(original.value);
  }
  String? unresolved;
  String? path;
  final unknown = [for (var i = 0; i < values.length; i++) if (values[i] == null) i];
  if (unknown.isEmpty) {
    path = _pathFromBackendApiLiteral(values.cast<String>().join());
  } else if (unknown.length == 1) {
    final index = unknown.single;
    final name = lex.code.substring(parts[index].start, parts[index].end).trim();
    final prefix = values.take(index).whereType<String>().join();
    final suffix = values.skip(index + 1).whereType<String>().join();
    if (index > 0 &&
        RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(name) &&
        prefix.endsWith('/') &&
        (suffix.isEmpty || suffix.startsWith('/')) &&
        _pathFromLiteral(prefix) != null) {
      // Inherits the existing userId-is-one-segment contract. No inserted
      // separator, arbitrary function result or partial segment is admitted.
      path = _pathFromBackendApiLiteral('$prefix{param}$suffix');
    } else {
      unresolved = 'Concat is not constants or one bounded identifier segment';
    }
  } else {
    unresolved = 'Concat has multiple unknown operands';
  }
  if (sourceApiPath != null && path == null && unresolved == null) {
    unresolved = 'Complete API concat is outside the auditable path grammar';
  }
  final after = lex.trivia(end);
  if (after < lex.source.length &&
      !const [',', ';', ')', ']', '}', ':'].contains(lex.code[after])) {
    unresolved = 'Unsupported operator or incomplete concat expression';
    path = null;
  }
  return _ApiConcatExpression(
    start: start,
    end: end,
    parts: parts,
    sourceTokens: originalTokens,
    path: path,
    sourceApiPath: sourceApiPath,
    unresolved: unresolved,
  );
}

String? _boundedConcatPath(String expression) {
  final lex = _DartRouteSource(expression);
  final first = lex.stringAt(0);
  if (first == null) return null;
  final concat = _concatExpressionAt(lex, lex._joinString(first, <int>{}));
  if (concat == null || concat.sourceApiPath == null) return null;
  if (concat.unresolved != null || lex.trivia(concat.end) < expression.length) {
    throw FormatException(concat.unresolved ?? 'Incomplete concat', expression);
  }
  return concat.path;
}

class _ApiLiteral {
  final String path;
  final String location;
  final String? _coverage;
  final int? expressionStart;
  final int? expressionEnd;
  final List<_DartRouteString> sourceTokens;
  final String? unresolved;

  const _ApiLiteral(this.path, this.location, {
    String? coverage,
    this.expressionStart,
    this.expressionEnd,
    this.sourceTokens = const [],
    this.unresolved,
  }) : _coverage = coverage;

  String get coveragePath => _coverage ?? path;

  @override
  bool operator ==(Object other) =>
      other is _ApiLiteral && path == other.path && location == other.location &&
      expressionStart == other.expressionStart && expressionEnd == other.expressionEnd &&
      coveragePath == other.coveragePath && unresolved == other.unresolved;

  @override
  int get hashCode => Object.hash(path, location, expressionStart, expressionEnd, coveragePath, unresolved);
}

// Main-owned source candidate; append after the protected original main.
// Public imports required by the successor:
// analyzer/dart/analysis/features.dart (FeatureSet), utilities.dart (parseString),
// analyzer/dart/ast/ast.dart as ast; pub_semver/pub_semver.dart (Version).
// No AST, import, or control execution is claimed by this source.

enum _ApiSyntaxPolicy { compilationUnit, statementFragment, legacyLocalStaticText }
enum _ApiValueKind { string, uri, stringList }

final _apiContexts = <(String, String, _ApiSyntaxPolicy), _ApiSourceContext>{};
_ApiSourceContext _apiContext(String source, String filePath,
    {required _ApiSyntaxPolicy policy}) =>
    _apiContexts.putIfAbsent((source, filePath, policy),
        () => _ApiSourceContext(source, filePath, policy: policy));

class _ApiSourceContext {
  final String source;
  final String filePath;
  final _ApiSyntaxPolicy policy;
  final _DartRouteSource lex;
  final List<_ApiBindingIssue> issues = [];
  _ApiScopeIndex? _index;
  final bool enforceGate;

  _ApiSourceContext(this.source, this.filePath,
      {this.policy = _ApiSyntaxPolicy.compilationUnit, this.enforceGate = true})
      : lex = _DartRouteSource(source);

  _ApiScopeIndex get index => _index ??= _ApiScopeIndex(this);

  _ApiResolvedValue resolve(_DartRouteArgument argument, _ApiValueKind kind) {
    // The original bounded lexer validates this argument before AST admission.
    final name = lex.code.substring(argument.start, argument.end).trim();
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(name)) {
      return const _ApiResolvedValue.unknown('notBareAlias');
    }
    final offset = lex.trivia(argument.start);
    return index.consume(name, offset, kind);
  }

  void requireNoFatalIssues({bool force = false}) {
    if (!enforceGate && !force) return;
    final fatal = issues.where((issue) => issue.fatal).toList();
    if (fatal.isNotEmpty) {
      throw FormatException('Blocked consumed API binding: '
          '${fatal.map((issue) => issue.description).join('; ')}',
          source, fatal.first.consumerOffset);
    }
  }
}

class _ApiBindingIssue {
  final int consumerOffset;
  final _ApiValueKind kind;
  final _ApiDeclaration? declaration;
  final List<int> dependencyIds;
  final String reason;
  final bool fatal;
  const _ApiBindingIssue(this.consumerOffset, this.kind, this.declaration,
      this.dependencyIds, this.reason, this.fatal);
  String get description => '$reason at $consumerOffset '
      'owner=${declaration?.owner.id} declaration=${declaration?.id} '
      'dependencies=$dependencyIds';
}

class _ApiResolvedValue {
  final List<String>? values;
  final String? reason;
  final bool knownApi;
  final List<int> dependencyIds;
  final _ApiDeclaration? blocked;
  const _ApiResolvedValue(this.values,
      {this.reason, this.knownApi = false,
      this.dependencyIds = const [], this.blocked});
  const _ApiResolvedValue.unknown(this.reason,
      {this.knownApi = false, this.dependencyIds = const [], this.blocked})
      : values = null;
  bool get known => values != null;
}

class _ApiOwner {
  final int id;
  final _ApiOwner? parent;
  final String kind;
  final bool staticContext;
  final String? boundary;
  final bool inheritedBoundary;
  final int originOffset;
  final Map<String, List<_ApiDeclaration>> names = {};
  _ApiOwner(this.id, this.parent, this.kind,
      {bool? staticContext, this.boundary, this.inheritedBoundary = false,
      int? originOffset})
      : staticContext = staticContext ?? parent?.staticContext ?? false,
        originOffset = originOffset ?? parent?.originOffset ?? 0;
}

class _ApiDeclaration {
  final int id;
  final String name;
  final _ApiOwner owner;
  final int nameOffset;
  final int declarationOffset;
  final int visibleAfter;
  final ast.Expression? initializer;
  final bool allowForward;
  final bool instanceField;
  final String? barrier;
  final String? explicitType;
  _ApiDeclaration(this.id, this.name, this.owner, this.nameOffset,
      this.declarationOffset, this.visibleAfter,
      {this.initializer, this.allowForward = false, this.instanceField = false,
      this.barrier, this.explicitType});
}

class _ApiWrite {
  final String name;
  final int offset;
  final _ApiOwner owner;
  final String kind;
  _ApiWrite(this.name, this.offset, this.owner, {this.kind = 'assignment'});
}

class _ApiScopeIndex {
  static const _fragmentPrefix = 'Future<void> __duoyi_scope_fixture_2104() async {\n';
  static const _fragmentSuffix = '\n}\n';
  final _ApiSourceContext context;
  final Map<ast.AstNode, _ApiOwner> _owners = Map.identity();
  final Map<int, ast.SimpleIdentifier> _references = {};
  final Map<int, ast.AstNode> _declarationNodes = {};
  final List<ast.MethodInvocation> _methodInvocations = [];
  final Map<(int, _ApiValueKind), _ApiResolvedValue> _memo = {};
  final Set<(int, _ApiValueKind)> _resolving = {};
  final List<_ApiWrite> _writes = [];
  final List<Map<String, Object?>> syntaxReceipts = [];
  late final ast.CompilationUnit unit;
  late final _ApiOwner root;
  int _ownerCounter = 0;
  int _declarationCounter = 0;
  int _prefixLength = 0;

  _ApiScopeIndex(this.context) {
    _admitSyntax();
    root = _ApiOwner(_ownerCounter++, null, 'unit', staticContext: true);
    if (context.policy == _ApiSyntaxPolicy.statementFragment) {
      final wrapper = unit.declarations.single as ast.FunctionDeclaration;
      // Wrapper-owned signature tokens cannot be registered as original names.
      _walk(wrapper.functionExpression.body,
          _child(root, 'executable', originOffset: 0));
    } else {
      _walk(unit, root);
    }
  }

  int originalOffset(int astOffset) => astOffset - _prefixLength;
  bool _inside(ast.AstNode node) => !node.isSynthetic &&
      node.offset >= _prefixLength &&
      node.end <= _prefixLength + context.source.length;

  void _admitSyntax() {
    final features = FeatureSet.fromEnableFlags2(
        sdkLanguageVersion: Version(3, 11, 0), flags: const []);
    var view = context.source;
    if (context.policy == _ApiSyntaxPolicy.statementFragment) {
      _prefixLength = _fragmentPrefix.length;
      view = _fragmentPrefix + view + _fragmentSuffix;
    }
    var parsed = parseString(content: view, path: context.filePath,
        featureSet: features, throwIfDiagnostics: false);
    syntaxReceipts.add({
      'policy': context.policy.name,
      'sdkLanguageVersion': '3.11.0', 'flags': <String>[],
      'source': context.source, 'sourceUtf16Length': context.source.length,
      'prefix': _prefixLength == 0 ? '' : _fragmentPrefix,
      'suffix': _prefixLength == 0 ? '' : _fragmentSuffix,
      'diagnostics': [for (final error in parsed.errors) {
        'code': error.diagnosticCode.lowerCaseName, 'offset': error.offset,
        'length': error.length, 'message': error.message,
      }],
      // parseString honors original scanner language overrides for real units.
      'languageVersion': parsed.unit.languageVersion.toString(),
    });
    if (context.policy == _ApiSyntaxPolicy.legacyLocalStaticText) {
      final matches = RegExp(r'\bstatic\b').allMatches(context.lex.code).toList();
      if (matches.length != 1) _syntaxFailure('legacyStaticTokenIdentity');
      final token = matches.single;
      if (context.source.substring(token.start, token.end) != 'static' ||
          parsed.errors.length != 1) {
        _syntaxFailure('legacyStaticDiagnosticCount');
      }
      final error = parsed.errors.single;
      if (error.diagnosticCode.lowerCaseName != 'extraneous_modifier' ||
          error.offset != token.start || error.length != 6) {
        _syntaxFailure('legacyStaticExactDiagnostic');
      }
      // No parser recovery tree from the original invalid view is indexed.
      view = context.source.replaceRange(token.start, token.end, '      ');
      parsed = parseString(content: view, path: context.filePath,
          featureSet: features, throwIfDiagnostics: false);
      syntaxReceipts.add({'adaptation': 'sixSpacesAtUniqueStatic',
        'offset': token.start, 'length': 6, 'view': view,
        'diagnostics': [for (final error in parsed.errors) {
          'code': error.diagnosticCode.lowerCaseName, 'offset': error.offset,
          'length': error.length, 'message': error.message,
        }]});
    }
    if (parsed.errors.isNotEmpty) _syntaxFailure('invalidSyntax');
    unit = parsed.unit;
    // Analyzer's normal zero-length EOF token is synthetic. Admit only the
    // actual terminal sentinel; all recovery nodes/tokens remain rejected.
    final eof = unit.endToken;
    bool terminalEof(Token token) => identical(token, eof) &&
        token.type == TokenType.EOF && token.offset == view.length &&
        token.length == 0 && identical(token.next, token);
    if (!terminalEof(eof)) {
      _syntaxFailure('invalidTerminalEof');
    }
    bool recoveryToken(Token token) => token.isSynthetic && !terminalEof(token);
    bool borrowedDocumentation(ast.AstNode node, ast.AstNode child) {
      // VariableDeclaration's public getter can borrow its grandparent's doc
      // comment. That shared reference retains its actual declaration parent.
      if (node is! ast.VariableDeclaration || child is! ast.Comment) {
        return false;
      }
      final list = node.parent;
      final owner = list?.parent;
      return list is ast.VariableDeclarationList && owner is ast.AnnotatedNode &&
          identical(node.documentationComment, child) &&
          identical(owner.documentationComment, child) &&
          identical(child.parent, owner) &&
          child.offset >= owner.offset && child.end <= owner.end;
    }
    bool emptyInterpolationSegment(ast.AstNode node) {
      if (node is! ast.InterpolationString || node.isSynthetic ||
          node.value.isNotEmpty) {
        return false;
      }
      final token = node.contents;
      if (!identical(node.beginToken, token) || !identical(node.endToken, token) ||
          token.type != TokenType.STRING || token.length != 0 ||
          token.lexeme.isNotEmpty) {
        return false;
      }
      final parent = node.parent;
      if (parent is! ast.StringInterpolation) return false;
      final matches = <int>[
        for (var i = 0; i < parent.elements.length; i++)
          if (identical(parent.elements[i], node)) i,
      ];
      if (matches.length != 1) return false;
      final index = matches.single;
      if (index == 0 || index + 1 >= parent.elements.length) return false;
      final previous = parent.elements[index - 1];
      final next = parent.elements[index + 1];
      return previous is ast.InterpolationExpression &&
          next is ast.InterpolationExpression &&
          identical(previous.parent, parent) && identical(next.parent, parent) &&
          previous.end == node.offset && node.offset == next.offset &&
          node.offset >= parent.offset && node.end <= parent.end &&
          identical(token.previous, previous.endToken) &&
          identical(token.next, next.beginToken);
    }
    void integrity(ast.AstNode node) {
      if (node.isSynthetic || (!emptyInterpolationSegment(node) &&
          (recoveryToken(node.beginToken) || recoveryToken(node.endToken)))) {
        _syntaxFailure('syntheticSyntax');
      }
      for (final child in node.childEntities.whereType<ast.AstNode>()) {
        if (!borrowedDocumentation(node, child) &&
            (!identical(child.parent, node) || child.offset < node.offset ||
             child.end > node.end)) {
          _syntaxFailure('invalidParentRange');
        }
        integrity(child);
      }
    }
    integrity(unit);
    if (context.policy == _ApiSyntaxPolicy.statementFragment) {
      if (unit.directives.isNotEmpty || unit.declarations.length != 1 ||
          unit.declarations.single is! ast.FunctionDeclaration) {
        _syntaxFailure('incompatibleFragmentUnit');
      }
      final wrapper = unit.declarations.single as ast.FunctionDeclaration;
      if (wrapper.name.lexeme != '__duoyi_scope_fixture_2104' ||
          wrapper.name.offset >= _prefixLength ||
          wrapper.functionExpression.body is! ast.BlockFunctionBody) {
        _syntaxFailure('fragmentWrapperIdentity');
      }
      void checkFragment(ast.AstNode node) {
        if (_inside(node) && (node is ast.FunctionDeclaration ||
            node is ast.ClassDeclaration || node is ast.Directive)) {
          _syntaxFailure('incompatibleFragmentDeclaration');
        }
        for (final child in node.childEntities.whereType<ast.AstNode>()) {
          checkFragment(child);
        }
      }
      checkFragment(wrapper.functionExpression.body);
    }
  }

  Never _syntaxFailure(String reason) {
    context.issues.add(_ApiBindingIssue(0, _ApiValueKind.string, null,
        const [], reason, true));
    throw FormatException('Required API syntax admission: $reason', context.source);
  }

  _ApiOwner _child(_ApiOwner parent, String kind,
      {bool? staticContext, String? boundary, bool inheritedBoundary = false,
      int? originOffset}) =>
      _ApiOwner(_ownerCounter++, parent, kind,
          staticContext: staticContext, boundary: boundary,
          inheritedBoundary: inheritedBoundary, originOffset: originOffset);

  void _declare(String name, int offset, int length, _ApiOwner owner,
      {int? declarationOffset, int? visibleAfter, ast.Expression? initializer,
      bool allowForward = false, bool instanceField = false,
      String? barrier, String? explicitType}) {
    if (offset < _prefixLength || offset + length >
        _prefixLength + context.source.length) {
      return;
    }
    final original = originalOffset(offset);
    if (context.source.substring(original, original + length) != name) {
      _syntaxFailure('nameTokenMapping');
    }
    final declaration = _ApiDeclaration(_declarationCounter++, name, owner,
        original, originalOffset(declarationOffset ?? offset),
        originalOffset(visibleAfter ?? offset + length),
        initializer: initializer, allowForward: allowForward,
        instanceField: instanceField, barrier: barrier, explicitType: explicitType);
    owner.names.putIfAbsent(name, () => []).add(declaration);
  }

  void _parameters(ast.FormalParameterList? parameters, _ApiOwner signature,
      _ApiOwner body) {
    if (parameters == null) return;
    for (final parameter in parameters.parameters) {
      final name = parameter.name;
      if (name != null) {
        _declare(name.lexeme, name.offset, name.length, body,
            allowForward: true, barrier: 'unknownParameter');
      }
      // Nested function-type parameter names belong to its type signature,
      // not to the outer executable's value scope.
      if (parameter is ast.DefaultFormalParameter && parameter.defaultValue != null) {
        _walk(parameter.defaultValue!, signature);
      }
    }
  }

  void _typeParameters(ast.TypeParameterList? parameters, _ApiOwner owner) {
    if (parameters == null) return;
    for (final parameter in parameters.typeParameters) {
      final name = parameter.name;
      _declare(name.lexeme, name.offset, name.length, owner,
          allowForward: true, barrier: 'typeParameter');
    }
  }

  void _executable(ast.FunctionBody body, ast.FormalParameterList? parameters,
      ast.TypeParameterList? types, _ApiOwner parent, {bool? staticContext,
      String? boundary, int? declarationOffset}) {
    final signature = _child(parent, 'signature', staticContext: staticContext,
        originOffset: declarationOffset ?? originalOffset(body.offset));
    _typeParameters(types, signature);
    final owner = _child(signature, 'executable', boundary: boundary);
    _parameters(parameters, signature, owner);
    _walk(body, owner);
  }

  bool _containsPatternBinding(ast.AstNode node) =>
      node is ast.VariablePattern ||
      node.childEntities.whereType<ast.AstNode>().any(_containsPatternBinding);

  void _walk(ast.AstNode node, _ApiOwner owner) {
    _owners[node] = owner;
    if (node is ast.ClassDeclaration) {
      final name = node.namePart.typeName;
      _declare(name.lexeme, name.offset, name.length, owner,
          allowForward: true, barrier: 'nonValueType');
      final classOwner = _child(owner, 'class', staticContext: false,
          originOffset: originalOffset(node.offset),
          inheritedBoundary: node.extendsClause != null || node.withClause != null,
          boundary: node.body is! ast.BlockClassBody ||
              node.namePart is ast.PrimaryConstructorDeclaration
              ? 'unsupportedClassShape' : null);
      _typeParameters(node.namePart.typeParameters, classOwner);
      if (node.body is ast.BlockClassBody) {
        for (final member in (node.body as ast.BlockClassBody).members) {
          _walk(member, classOwner);
        }
      }
      return;
    }
    if (node is ast.FunctionDeclaration) {
      final name = node.name;
      _declare(name.lexeme, name.offset, name.length, owner,
          allowForward: true, barrier: 'nonValueName');
      final function = node.functionExpression;
      _owners[function] = owner;
      _executable(function.body, function.parameters, function.typeParameters, owner,
          declarationOffset: originalOffset(node.offset));
      return;
    }
    if (node is ast.FunctionExpression) {
      _executable(node.body, node.parameters, node.typeParameters, owner,
          declarationOffset: originalOffset(node.offset));
      return;
    }
    if (node is ast.MethodDeclaration) {
      final name = node.name;
      _declarationNodes[originalOffset(name.offset)] = node;
      _declare(name.lexeme, name.offset, name.length, owner,
          allowForward: true, barrier: 'nonValueMethod');
      _executable(node.body, node.parameters, node.typeParameters, owner,
          staticContext: node.isStatic, declarationOffset: originalOffset(node.offset));
      return;
    }
    if (node is ast.ConstructorDeclaration) {
      final constructorOwner = _child(owner, 'constructor',
          boundary: 'unsupportedConstructorContext');
      _parameters(node.parameters, owner, constructorOwner);
      for (final initializer in node.initializers) {
        _walk(initializer, constructorOwner);
      }
      _walk(node.body, constructorOwner);
      return;
    }
    if (node is ast.Block) {
      final block = _child(owner, 'block');
      _owners[node] = block;
      for (final statement in node.statements) {
        _walk(statement, block);
      }
      return;
    }
    if (node is ast.VariableDeclarationList) {
      final parent = node.parent;
      final field = parent is ast.FieldDeclaration;
      final top = parent is ast.TopLevelVariableDeclaration;
      for (final variable in node.variables) {
        final name = variable.name;
        _declarationNodes[originalOffset(name.offset)] = variable;
        final expression = variable.initializer;
        if (expression != null && !_inside(expression)) _syntaxFailure('initializerMapping');
        _declare(name.lexeme, name.offset, name.length, owner,
            declarationOffset: node.offset,
            visibleAfter: expression?.end ?? variable.end,
            initializer: expression, allowForward: field || top,
            instanceField: field && !parent.isStatic,
            barrier: expression == null
                ? (field || top ? 'uninitializedValue' : 'uninitializedLocal') : null,
            explicitType: node.type?.toSource());
        if (expression != null) {
          final initializerOwner = field
              ? _child(owner, 'fieldInitializer',
                  staticContext: parent.isStatic)
              : owner;
          _walk(expression, initializerOwner);
        }
      }
      return;
    }
    if (node is ast.IfStatement && node.caseClause != null) {
      _walk(node.expression, owner);
      final branch = _child(owner, 'ifCase', boundary:
          _containsPatternBinding(node.caseClause!) ? 'unsupportedPatternContext' : null);
      _walk(node.caseClause!, branch);
      _walk(node.thenStatement, branch);
      if (node.elseStatement != null) _walk(node.elseStatement!, owner);
      return;
    }
    if (node is ast.IfElement && node.caseClause != null) {
      _walk(node.expression, owner);
      final branch = _child(owner, 'ifCaseElement', boundary:
          _containsPatternBinding(node.caseClause!) ? 'unsupportedPatternContext' : null);
      _walk(node.caseClause!, branch);
      _walk(node.thenElement, branch);
      if (node.elseElement != null) _walk(node.elseElement!, owner);
      return;
    }
    if (node is ast.SwitchPatternCase) {
      final branch = _child(owner, 'switchCase', boundary:
          _containsPatternBinding(node.guardedPattern) ? 'unsupportedPatternContext' : null);
      _walk(node.guardedPattern, branch);
      for (final statement in node.statements) {
        _walk(statement, branch);
      }
      return;
    }
    if (node is ast.SwitchExpressionCase) {
      final branch = _child(owner, 'switchExpressionCase', boundary:
          _containsPatternBinding(node.guardedPattern) ? 'unsupportedPatternContext' : null);
      _walk(node.guardedPattern, branch);
      _walk(node.expression, branch);
      return;
    }
    if (node is ast.ForStatement || node is ast.ForElement) {
      final parts = node is ast.ForStatement
          ? node.forLoopParts : (node as ast.ForElement).forLoopParts;
      final body = node is ast.ForStatement
          ? node.body : (node as ast.ForElement).body;
      final loop = _child(owner, 'loop', originOffset: originalOffset(node.offset));
      if (parts is ast.ForEachPartsWithDeclaration) {
        _walk(parts.iterable, owner);
        final name = parts.loopVariable.name;
        _declare(name.lexeme, name.offset, name.length, loop,
            allowForward: true, barrier: 'unknownLoopElement');
      } else if (parts is ast.ForEachPartsWithIdentifier) {
        _walk(parts.iterable, owner);
        final name = parts.identifier;
        _writes.add(_ApiWrite(name.name, originalOffset(name.offset), owner, kind: 'forIn'));
        _walk(name, loop);
      } else if (parts is ast.ForEachParts) {
        _walk(parts.iterable, owner);
        // Pattern visibility must never appear as an absent declaration list.
        final blockedLoop = _child(loop, 'patternLoop', boundary: 'unsupportedPattern');
        _walk(body, blockedLoop);
        return;
      } else {
        _walk(parts, loop);
      }
      _walk(body, loop);
      return;
    }
    if (node is ast.CatchClause) {
      final caught = _child(owner, 'catch', originOffset: originalOffset(node.offset));
      for (final parameter in [node.exceptionParameter, node.stackTraceParameter]) {
        if (parameter == null) continue;
        final name = parameter.name;
        _declare(name.lexeme, name.offset, name.length, caught,
            allowForward: true, barrier: 'unknownParameter');
      }
      _walk(node.body, caught);
      return;
    }
    if (node is ast.MethodInvocation && _inside(node)) {
      _methodInvocations.add(node);
    }
    if (node is ast.SimpleIdentifier && _inside(node)) {
      _references[originalOffset(node.offset)] = node;
    }
    if (node is ast.AssignmentExpression && node.leftHandSide is ast.SimpleIdentifier) {
      final name = node.leftHandSide as ast.SimpleIdentifier;
      _writes.add(_ApiWrite(name.name, originalOffset(name.offset), owner));
    }
    if (node is ast.PostfixExpression && node.operand is ast.SimpleIdentifier) {
      final name = node.operand as ast.SimpleIdentifier;
      _writes.add(_ApiWrite(name.name, originalOffset(name.offset), owner));
    }
    if (node is ast.PrefixExpression && node.operand is ast.SimpleIdentifier &&
        const {'++', '--'}.contains(node.operator.lexeme)) {
      final name = node.operand as ast.SimpleIdentifier;
      _writes.add(_ApiWrite(name.name, originalOffset(name.offset), owner));
    }
    if (node is ast.ImportDirective && node.prefix != null) {
      final name = node.prefix!;
      _declare(name.name, name.offset, name.length, owner,
          allowForward: true, barrier: 'importPrefix');
    }
    if (node is ast.TypeAlias) {
      final name = node.name;
      _declare(name.lexeme, name.offset, name.length, owner,
          allowForward: true, barrier: 'nonValueType');
      return;
    }
    // These declarations have semantics beyond this finite binding contract.
    // Register their own names, and make an explicit boundary around children.
    if (node is ast.MixinDeclaration || node is ast.EnumDeclaration ||
        node is ast.ExtensionDeclaration || node is ast.ExtensionTypeDeclaration) {
      final token = node is ast.MixinDeclaration ? node.name
          : node is ast.EnumDeclaration ? node.namePart.typeName
          : node is ast.ExtensionDeclaration ? node.name
          : (node as ast.ExtensionTypeDeclaration).primaryConstructor.typeName;
      if (token != null) {
        _declare(token.lexeme, token.offset, token.length, owner,
            allowForward: true, barrier: 'unsupportedType');
      }
      owner = _child(owner, 'unsupportedType', boundary: 'unsupportedTypeContext');
    }
    if (node is ast.PatternVariableDeclaration) {
      // The enclosing lexical owner must not overlook an unsupported shadow.
      owner.names.putIfAbsent('__unsupported_pattern_boundary__', () => []);
      _patternOwners.add(owner);
    }
    for (final child in node.childEntities.whereType<ast.AstNode>()) {
      _walk(child, owner);
    }
  }

  final Set<_ApiOwner> _patternOwners = Set.identity();

  _ApiResolvedValue _lookup(String name, int offset, _ApiOwner owner,
      _ApiValueKind kind) {
    final consumerStatic = owner.staticContext;
    for (_ApiOwner? current = owner; current != null; current = current.parent) {
      if (current.boundary != null || _patternOwners.contains(current)) {
        return _ApiResolvedValue.unknown(current.boundary ?? 'unsupportedPattern');
      }
      final matches = current.names[name];
      if (matches == null) {
        if (current.inheritedBoundary) {
          return const _ApiResolvedValue.unknown('externalInheritanceBoundary');
        }
        continue;
      }
      final knownApi = matches.any(_hasApiSource);
      if (matches.length != 1) {
        return _ApiResolvedValue.unknown('ambiguous', knownApi: knownApi,
            dependencyIds: matches.map((declaration) => declaration.id).toList(),
            blocked: matches.first);
      }
      final declaration = matches.single;
      _ApiResolvedValue blocked(String reason) => _ApiResolvedValue.unknown(reason,
          knownApi: knownApi, dependencyIds: [declaration.id], blocked: declaration);
      if (!declaration.allowForward && offset < declaration.visibleAfter) {
        return blocked('localForward');
      }
      if (declaration.instanceField && consumerStatic) return blocked('instanceMemberInStaticContext');
      if (declaration.barrier != null) return blocked(declaration.barrier!);
      for (final write in _writes) {
        if (write.name != name || write.offset >= offset) continue;
        final written = _nearestIdentity(name, write.owner);
        if (identical(written, declaration)) {
          // A write invalidates the initializer; its former API literal is
          // not evidence for the current unknown dynamic value.
          return _ApiResolvedValue.unknown(write.kind == 'forIn'
              ? 'writtenByForIn' : 'writtenValue',
              dependencyIds: [declaration.id], blocked: declaration);
        }
      }
      return _resolveDeclaration(declaration, kind);
    }
    return const _ApiResolvedValue.unknown('externalOrAbsent');
  }

  _ApiDeclaration? _nearestIdentity(String name, _ApiOwner owner) {
    for (_ApiOwner? current = owner; current != null; current = current.parent) {
      final matches = current.names[name];
      if (matches != null) return matches.length == 1 ? matches.single : null;
    }
    return null;
  }


  // Additive transport classification. The historical literal `http.*`
  // collectors keep their original fragment conventions. New receivers must
  // bind to an actual declared package:http Client type in this lexical scope.
  _ApiDeclaration? _visibleIdentity(String name, int offset, _ApiOwner owner) {
    for (_ApiOwner? current = owner; current != null; current = current.parent) {
      if (current.boundary != null || _patternOwners.contains(current)) return null;
      final matches = current.names[name];
      if (matches != null) {
        if (matches.length != 1) return null;
        final declaration = matches.single;
        if ((!declaration.allowForward && offset < declaration.visibleAfter) ||
            (declaration.instanceField && owner.staticContext)) {
          return null;
        }
        if (_writes.any((write) => write.name == name && write.offset < offset &&
            identical(_nearestIdentity(name, write.owner), declaration))) {
          return null;
        }
        return declaration;
      }
      if (current.inheritedBoundary) return null;
    }
    return null;
  }

  bool _isHttpClientInvocation(ast.MethodInvocation invocation) {
    if (!const {'get', 'post', 'patch', 'put', 'delete'}
        .contains(invocation.methodName.name) || invocation.isCascaded) {
      return false;
    }
    final receiver = invocation.target;
    if (receiver is! ast.SimpleIdentifier || !_inside(receiver)) return false;
    final owner = _owners[receiver];
    if (owner == null) return false;
    final declaration = _visibleIdentity(receiver.name,
        originalOffset(receiver.offset), owner);
    if (declaration == null) return false;
    final variable = _declarationNodes[declaration.nameOffset];
    if (variable is! ast.VariableDeclaration) return false;
    final list = variable.parent;
    if (list is! ast.VariableDeclarationList || list.type is! ast.NamedType) return false;
    final type = list.type! as ast.NamedType;
    final prefixReference = type.importPrefix;
    if (prefixReference == null || type.name.lexeme != 'Client' ||
        type.typeArguments != null || type.question != null ||
        !identical(prefixReference.parent, type) ||
        !identical(type.parent, list)) {
      return false;
    }
    final prefix = prefixReference.name.lexeme;
    final roots = root.names[prefix];
    if (roots?.length != 1 || roots!.single.barrier != 'importPrefix') return false;
    final binding = roots.single;
    // A type's import prefix is an explicit namespace reference. Preserve all
    // actual lexical shadows; unrelated inherited value members do not change
    // this unique unit import. Receiver value lookup remains unchanged.
    for (_ApiOwner? current = declaration.owner; current != null; current = current.parent) {
      if (current.boundary != null || _patternOwners.contains(current)) return false;
      final matches = current.names[prefix];
      if (matches != null && (matches.length != 1 ||
          !identical(matches.single, binding))) {
        return false;
      }
    }
    final imports = unit.directives.whereType<ast.ImportDirective>().where(
        (directive) => directive.prefix?.name == prefix &&
            originalOffset(directive.prefix!.offset) == binding.nameOffset).toList();
    if (imports.length != 1) return false;
    final directive = imports.single;
    if (directive.uri.stringValue != 'package:http/http.dart' ||
        directive.configurations.isNotEmpty || directive.deferredKeyword != null) {
      return false;
    }
    for (final combinator in directive.combinators) {
      if (combinator is ast.HideCombinator &&
          combinator.hiddenNames.any((name) => name.name == 'Client')) {
        return false;
      }
      if (combinator is ast.ShowCombinator &&
          !combinator.shownNames.any((name) => name.name == 'Client')) {
        return false;
      }
    }
    return true;
  }

  bool isHttpClientMethodAt(int methodOffset) {
    final name = _references[methodOffset];
    final invocation = name?.parent;
    return invocation is ast.MethodInvocation &&
        identical(invocation.methodName, name) && _isHttpClientInvocation(invocation);
  }

  Iterable<ast.MethodInvocation> get httpClientInvocations =>
      _methodInvocations.where(_isHttpClientInvocation);

  String _sourceDigest(ast.AstNode node) => sha256.convert(utf8.encode(
      context.source.substring(originalOffset(node.offset),
          originalOffset(node.end)))).toString();

  _ApiResolvedValue? _sourceVerifiedUriHelper(ast.MethodInvocation invocation) {
    // Pin the reviewed library and import environment as well as both methods.
    // A transplanted helper or an altered import must retain the unknown path.
    if (context.filePath != 'lib/services/api_client.dart' ||
        sha256.convert(utf8.encode(context.source)).toString() !=
            'c03974dad34c38eb1cb4f2cedc2ebf2cbf230e74d4fe886292331d3b00df2f9a') {
      return null;
    }
    if (invocation.target != null || invocation.isCascaded ||
        invocation.methodName.name != '_uriFor' ||
        invocation.argumentList.arguments.length != 1) {
      return null;
    }
    final owner = _owners[invocation.methodName];
    if (owner == null || owner.staticContext) return null;
    final methodBinding = _visibleIdentity('_uriFor',
        originalOffset(invocation.methodName.offset), owner);
    if (methodBinding == null || methodBinding.owner.kind != 'class') return null;
    final method = _declarationNodes[methodBinding.nameOffset];
    if (method is! ast.MethodDeclaration || method.isStatic ||
        _sourceDigest(method) != '36c0bfa36ed5419cf1d2a24a68f6421c6709eb7481996a5796710a17aec73808') {
      return null;
    }
    final classOwner = methodBinding.owner;
    final companionBindings = classOwner.names['_hasBackendApiPrefix'];
    final baseBindings = classOwner.names['baseUrl'];
    if (companionBindings?.length != 1 || baseBindings?.length != 1) return null;
    final companionBinding = companionBindings!.single;
    final companion = _declarationNodes[companionBinding.nameOffset];
    if (companion is! ast.MethodDeclaration || companion.isStatic ||
        _sourceDigest(companion) != 'fe226b50340c7e400810b3984749099fc765e22bda7232c68b2eecd427a98835') {
      return null;
    }
    final baseBinding = baseBindings!.single;
    final base = _declarationNodes[baseBinding.nameOffset];
    if (base is! ast.VariableDeclaration || !baseBinding.instanceField ||
        baseBinding.explicitType != 'String') {
      return null;
    }
    // These exact two source methods use implicit SDK classes. Refuse any
    // lexical declaration that substitutes those constructor/type identities.
    for (_ApiOwner? current = classOwner; current != null; current = current.parent) {
      if (current.boundary != null || current.inheritedBoundary ||
          _patternOwners.contains(current) ||
          const ['Uri', 'String', 'RegExp', 'bool']
              .any((name) => current!.names.containsKey(name))) {
        return null;
      }
    }
    final argument = invocation.argumentList.arguments.single;
    if (argument is ast.NamedExpression) return null;
    final value = _evaluate(argument, _ApiValueKind.string);
    final dependencies = [methodBinding.id, companionBinding.id, baseBinding.id,
      ...value.dependencyIds];
    if (!value.known) {
      return _ApiResolvedValue.unknown(value.reason,
          knownApi: value.knownApi, blocked: value.blocked,
          dependencyIds: dependencies);
    }
    final grammar = RegExp(r'^/api(?:/[A-Za-z0-9_{}.$%:+-]+)*$');
    for (final path in value.values!) {
      final match = grammar.firstMatch(path);
      if (match == null || match.start != 0 || match.end != path.length ||
          _pathFromBackendApiLiteral(path) == null) {
        return _ApiResolvedValue.unknown('unsupportedUriHelperProjection',
            knownApi: value.knownApi, blocked: value.blocked,
            dependencyIds: dependencies);
      }
    }
    // Finite source-bound API route projection only. These complete rooted
    // paths survive the reviewed path normalizer. The configured base URI is
    // external; this does not assert its actual host or full URI path.
    return _ApiResolvedValue(value.values, knownApi: value.knownApi,
        dependencyIds: dependencies);
  }

  bool _hasApiSource(_ApiDeclaration declaration, [Set<int>? seen]) {
    seen ??= <int>{};
    if (!seen.add(declaration.id)) return false;
    final expression = declaration.initializer;
    if (expression == null) return false;
    final start = originalOffset(expression.offset);
    final end = originalOffset(expression.end);
    if (context.lex.strings.values.any((token) => token.start >= start &&
        token.end <= end && _pathFromLiteral(token.value) != null)) {
      return true;
    }
    String? literalRun(ast.Expression node) {
      if (node is ast.ParenthesizedExpression) return literalRun(node.expression);
      if (node is ast.BinaryExpression && node.operator.lexeme == '+') {
        final left = literalRun(node.leftOperand), right = literalRun(node.rightOperand);
        return left != null && right != null ? left + right : null;
      }
      return context.lex.literal(_DartRouteArgument(
          originalOffset(node.offset), originalOffset(node.end)));
    }
    final assembled = literalRun(expression);
    if (assembled != null && _pathFromLiteral(assembled) != null) return true;
    bool dependencies(ast.AstNode node) {
      if (node is ast.FunctionExpression || node is ast.PropertyAccess ||
          node is ast.PrefixedIdentifier) {
        return false;
      }
      if (node is ast.SimpleIdentifier) {
        final parent = node.parent;
        if (parent is ast.Label || parent is ast.NamedType ||
            (parent is ast.MethodInvocation && identical(parent.methodName, node))) {
          return false;
        }
        final owner = _owners[node];
        if (owner == null) return false;
        final dependency = _nearestIdentity(node.name, owner);
        if (dependency != null) {
          final referenceOffset = originalOffset(node.offset);
          final written = _writes.any((write) => write.name == node.name &&
              write.offset < referenceOffset &&
              identical(_nearestIdentity(write.name, write.owner), dependency));
          if (!written && _hasApiSource(dependency, seen)) return true;
        }
      }
      return node.childEntities.whereType<ast.AstNode>().any(dependencies);
    }
    return dependencies(expression);
  }

  _ApiResolvedValue consume(String name, int offset, _ApiValueKind kind) {
    final reference = _references[offset];
    if (reference == null || reference.name != name || !_inside(reference)) {
      _syntaxFailure('consumerMapping');
    }
    final result = _lookup(name, offset, _owners[reference]!, kind);
    if (!result.known) {
      // Outer same-name API values are deliberately not provenance of this use.
      context.issues.add(_ApiBindingIssue(offset, kind, result.blocked,
          result.dependencyIds, result.reason ?? 'unknown', result.knownApi ||
              (result.reason?.startsWith('unsupported') ?? false)));
    }
    return result;
  }

  bool _isValueReference(ast.SimpleIdentifier reference) {
    final parent = reference.parent;
    return !reference.isQualified && parent is! ast.Label && parent is! ast.NamedType &&
        !(parent is ast.MethodInvocation && identical(parent.methodName, reference));
  }

  _ApiDeclaration? declarationAt(int offset) {
    final reference = _references[offset];
    if (reference == null || !_isValueReference(reference)) return null;
    for (_ApiOwner? current = _owners[reference]; current != null; current = current.parent) {
      if (current.boundary != null || _patternOwners.contains(current)) return null;
      final matches = current.names[reference.name];
      if (matches != null) return matches.length == 1 ? matches.single : null;
      if (current.inheritedBoundary) return null;
    }
    return null;
  }

  _ApiResolvedValue _resolveDeclaration(_ApiDeclaration declaration, _ApiValueKind kind) {
    final key = (declaration.id, kind);
    final cached = _memo[key];
    if (cached != null) return cached;
    final type = declaration.explicitType?.replaceAll(' ', '')
        .replaceFirst(RegExp(r'\?$'), '');
    final compatible = type == null || type == 'dynamic' ||
        (kind == _ApiValueKind.string && type == 'String') ||
        (kind == _ApiValueKind.uri && type == 'Uri') ||
        (kind == _ApiValueKind.stringList && type == 'List<String>');
    if (!compatible) {
      return _ApiResolvedValue.unknown('typeIncompatible',
          knownApi: _hasApiSource(declaration), blocked: declaration,
          dependencyIds: [declaration.id]);
    }
    if (!_resolving.add(key)) {
      return _ApiResolvedValue.unknown('cycle',
          knownApi: _hasApiSource(declaration), blocked: declaration,
          dependencyIds: [declaration.id]);
    }
    try {
      final expression = declaration.initializer;
      if (expression == null) return const _ApiResolvedValue.unknown('uninitialized');
      final result = _evaluate(expression, kind);
      final value = _ApiResolvedValue(result.values,
          reason: result.reason,
          knownApi: result.knownApi || _hasApiSource(declaration),
          dependencyIds: [declaration.id, ...result.dependencyIds],
          blocked: result.blocked ?? (!result.known ? declaration : null));
      _memo[key] = value;
      return value;
    } finally {
      _resolving.remove(key);
    }
  }

  _ApiResolvedValue _evaluateConcat(ast.BinaryExpression expression) {
    final operands = <ast.Expression>[];
    void flatten(ast.Expression node) {
      if (node is ast.BinaryExpression && node.operator.lexeme == '+') {
        flatten(node.leftOperand);
        flatten(node.rightOperand);
      } else {
        operands.add(node);
      }
    }
    flatten(expression);
    final resolved = [for (final operand in operands)
      _evaluate(operand, _ApiValueKind.string)];
    final dependencies = [for (final value in resolved) ...value.dependencyIds];
    final unknown = [for (var i = 0; i < resolved.length; i++)
      if (resolved[i].values?.length != 1) i];
    if (unknown.isEmpty) {
      final text = resolved.map((value) => value.values!.single).join();
      final api = _pathFromLiteral(text) != null;
      if (api && _pathFromBackendApiLiteral(text) == null) {
        return _ApiResolvedValue.unknown('outsideAuditableConcatGrammar',
            knownApi: true, dependencyIds: dependencies);
      }
      return _ApiResolvedValue([text], knownApi: api, dependencyIds: dependencies);
    }
    var knownApi = resolved.any((value) => value.knownApi);
    // Join contiguous known runs only: unknowns cannot assemble an API root.
    var run = '';
    for (final value in resolved) {
      if (value.values?.length == 1) {
        run += value.values!.single;
      } else {
        knownApi |= _pathFromLiteral(run) != null;
        run = '';
      }
    }
    knownApi |= _pathFromLiteral(run) != null;
    if (unknown.length == 1) {
      final index = unknown.single;
      final value = resolved[index];
      final operand = operands[index];
      final prefix = resolved.take(index).map((value) => value.values!.single).join();
      final suffix = resolved.skip(index + 1).map((value) => value.values!.single).join();
      final isBoundedDynamic = !value.knownApi &&
          const {'externalOrAbsent', 'unknownParameter'}.contains(value.reason) &&
          (value.blocked == null || value.blocked?.barrier == 'unknownParameter');
      if (index > 0 && operand is ast.SimpleIdentifier && isBoundedDynamic &&
          prefix.endsWith('/') && (suffix.isEmpty || suffix.startsWith('/')) &&
          _pathFromLiteral(prefix) != null) {
        final text = '$prefix{param}$suffix';
        if (_pathFromBackendApiLiteral(text) != null) {
          // Preserve decoded prefix/suffix; normalization happens at consumption.
          return _ApiResolvedValue([text], knownApi: true, dependencyIds: dependencies);
        }
      }
    }
    final failed = resolved.firstWhere((value) => !value.known);
    return _ApiResolvedValue.unknown(failed.reason ?? 'unsupportedConcat',
        knownApi: knownApi, blocked: failed.blocked, dependencyIds: dependencies);
  }

  _ApiResolvedValue _evaluate(ast.Expression expression, _ApiValueKind kind) {
    if (!_inside(expression)) _syntaxFailure('valueMapping');
    final argument = _DartRouteArgument(originalOffset(expression.offset),
        originalOffset(expression.end));
    if (expression is ast.ParenthesizedExpression) {
      return _evaluate(expression.expression, kind);
    }
    if (expression is ast.SimpleIdentifier) {
      return _lookup(expression.name, argument.start, _owners[expression]!, kind);
    }
    if (kind == _ApiValueKind.string) {
      final literal = context.lex.literal(argument);
      if (literal != null) {
        return _ApiResolvedValue([literal],
            knownApi: _pathFromLiteral(literal) != null);
      }
      if (expression is ast.BinaryExpression && expression.operator.lexeme == '+') {
        return _evaluateConcat(expression);
      }
    }
    if (kind == _ApiValueKind.stringList && expression is ast.ListLiteral) {
      final values = <String>[];
      final dependencies = <int>[];
      for (final element in expression.elements) {
        if (element is! ast.Expression) return const _ApiResolvedValue.unknown('unsupportedListElement');
        final value = _evaluate(element, _ApiValueKind.string);
        dependencies.addAll(value.dependencyIds);
        if (!value.known) {
          return _ApiResolvedValue.unknown(value.reason,
              knownApi: value.knownApi || values.any((text) => _pathFromLiteral(text) != null),
              blocked: value.blocked, dependencyIds: dependencies);
        }
        values.addAll(value.values!);
      }
      return _ApiResolvedValue(values, dependencyIds: dependencies,
          knownApi: values.any((text) => _pathFromLiteral(text) != null));
    }
    if (kind == _ApiValueKind.uri) {
      if (expression is ast.MethodInvocation) {
        final helperValue = _sourceVerifiedUriHelper(expression);
        if (helperValue != null) return helperValue;
      }
      if (expression is ast.ConditionalExpression) {
        final left = _evaluate(expression.thenExpression, kind);
        final right = _evaluate(expression.elseExpression, kind);
        if (!left.known || !right.known) {
          return _ApiResolvedValue.unknown(
              left.reason ?? right.reason, knownApi: left.knownApi || right.knownApi,
              blocked: left.blocked ?? right.blocked,
              dependencyIds: [...left.dependencyIds, ...right.dependencyIds]);
        }
        return _ApiResolvedValue([...{...left.values!, ...right.values!}],
            knownApi: left.knownApi || right.knownApi,
            dependencyIds: [...left.dependencyIds, ...right.dependencyIds]);
      }
      final prefix = RegExp(r'(Uri\.(?:parse|https|http)|Uri|_backendUri)\s*\(')
          .matchAsPrefix(context.lex.code, argument.start);
      if (prefix != null) {
        final arguments = context.lex.arguments(prefix.end - 1);
        final constructor = prefix.group(1)!;
        _DartRouteArgument? path;
        if (constructor == 'Uri.parse' && arguments.isNotEmpty) {
          path = arguments.first;
        } else if (constructor != 'Uri' && arguments.length >= 2) {
          path = arguments[1];
        } else if (constructor == 'Uri') {
          for (final item in arguments) {
            final label = RegExp(r'path\s*:\s*').matchAsPrefix(context.lex.code, item.start);
            if (label != null) path = _DartRouteArgument(context.lex.trivia(label.end), item.end);
          }
        }
        if (path != null) {
          final literal = context.lex.literal(path);
          if (literal != null) {
            return _ApiResolvedValue([literal],
                knownApi: _pathFromLiteral(literal) != null);
          }
          final reference = _references[path.start];
          if (reference != null && reference.end - _prefixLength == path.end) {
            return _lookup(reference.name, path.start, _owners[reference]!, _ApiValueKind.string);
          }
        }
      }
    }
    return const _ApiResolvedValue.unknown('opaqueDynamicValue');
  }
}

// NEW2121 prepared/unexecuted replacement for inspectApiScopeSource only.
// Append the private helper in the same library. No core index/collector/gate edit.
// Public IDs explicitly serialize actual integers as d:<id>/o:<id>;
// raw diagnostics retain the original integers. No fixture/identity invention.
Map<String, Object?> inspectApiScopeSource(String source, String filePath) {
  final context = _ApiSourceContext(source, filePath,
      policy: _ApiSyntaxPolicy.compilationUnit, enforceGate: false);
  // Original bounded lexer/collector exceptions escape before the forced gate.
  final calls = <_RouteContract>{
    ..._literalApiMethodCalls(source, filePath),
    ..._nestedPathApiMethodCalls(source, filePath),
    ..._getPageApiCalls(source, filePath),
    ..._httpUriParseApiCalls(source, filePath),
    ..._httpUriConstructorApiCalls(source, filePath),
    ..._httpUriAliasApiCalls(source, filePath, context: context),
    ..._localLiteralAliasApiCalls(source, filePath, context: context),
    ..._concatenatedApiMethodCalls(source, filePath),
    ..._firstAvailableApiCalls(source, filePath, context: context),
    ..._multipartApiCalls(source, filePath),
    ..._uriPathApiCalls(source, filePath),
    ..._genericRequestApiCalls(source, filePath),
  }.toList();
  final index = context.index; // Actual admission/integrity failures still escape.
  final projection = _ApiObserverProjection2121(context, index);
  final ordered = [for (var i = 0; i < calls.length; i++) (i, calls[i])];
  int callLine(_RouteContract call) => int.parse(
      RegExp(r':(\d+)(?: via |$)').firstMatch(call.location)!.group(1)!);
  ordered.sort((a, b) {
    final line = callLine(a.$2).compareTo(callLine(b.$2));
    return line != 0 ? line : a.$1.compareTo(b.$1);
  });

  // Deduplicate only identical observations; preserve the complete raw stream.
  final seen = <String>{};
  final unique = <(int, _ApiBindingIssue)>[];
  for (var i = 0; i < context.issues.length; i++) {
    final issue = context.issues[i];
    final key = '${issue.consumerOffset}:${issue.kind.name}:${issue.reason}:'
        '${issue.fatal}:${issue.declaration?.id}:${issue.dependencyIds}';
    if (seen.add(key)) unique.add((i, issue));
  }
  unique.sort((a, b) {
    final offset = a.$2.consumerOffset.compareTo(b.$2.consumerOffset);
    return offset != 0 ? offset : a.$1.compareTo(b.$1);
  });
  final issues = <Map<String, Object?>>[];
  final details = <Map<String, Object?>>[];
  final facts = <Map<String, Object?>>[];
  for (final entry in unique) {
    final issue = entry.$2;
    final selected = index.declarationAt(issue.consumerOffset);
    final reason = projection.reason(issue, selected);
    issues.add({
      'reason': reason, 'fatal': issue.fatal,
      'consumerLine': _lineOf(source, issue.consumerOffset),
      // Selected consumer declaration differs from the actual blocked leaf.
      'declaration': projection.declaration(selected ?? issue.declaration),
      'dependencyIds': [for (final id in issue.dependencyIds) 'd:$id'],
    });
    final methods = projection.methods(issue.consumerOffset);
    details.add({
      'method': methods.length == 1 ? methods.single : null,
      'kind': switch (issue.kind) {
        _ApiValueKind.string => 'String',
        _ApiValueKind.uri => 'URI',
        _ApiValueKind.stringList => 'List<String>',
      },
      'cause': projection.cause(issue, selected, reason),
      'writeLine': projection.writeLine(issue, selected),
      'sourceObligation': projection.obligation(issue, selected, reason),
    });
    facts.add(projection.consumerFacts(issue, selected, methods, entry.$1));
  }

  final references = index._references.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
  var gateRefused = false;
  Map<String, Object?>? gateError;
  try {
    context.requireNoFatalIssues(force: true);
  } on FormatException catch (error) {
    // Only the real forced binding gate is caught. No parse/token catch here.
    gateRefused = true;
    gateError = {'message': error.message, 'offset': error.offset};
  }
  final receipts = index.syntaxReceipts;
  final first = receipts.first;
  final configured = Version.parse(first['sdkLanguageVersion'] as String);
  final effective = index.unit.languageVersion.override ?? configured;
  final diagnostics = [for (final receipt in receipts)
    ...(receipt['diagnostics'] as List)];
  final syntaxAccepted = receipts.isNotEmpty && diagnostics.isEmpty &&
      first['policy'] == context.policy.name &&
      first['source'] == source && first['sourceUtf16Length'] == source.length &&
      first['prefix'] == '' && first['suffix'] == '';
  return {
    'routes': [for (final item in ordered) {
      'method': item.$2.method, 'path': item.$2.path, 'location': item.$2.location,
    }],
    'issues': issues, 'issueDetails': details,
    'declarations': [for (final value in projection.declarations.values)
      projection.declaration(value)],
    'ownerFacts': projection.ownerFacts(),
    'bindings': [for (final reference in references)
      {
        'name': reference.value.name,
        'referenceLine': _lineOf(source, reference.key),
        'declarationLine': index.declarationAt(reference.key) == null ? null : _lineOf(source,
            index.declarationAt(reference.key)!.declarationOffset),
        'ownerId': index.declarationAt(reference.key) == null ? null : 'o:${projection.semanticOwner(
            index.declarationAt(reference.key)!.owner).id}',
      }],
    'fatalGateRefused': gateRefused,
    'syntaxAdmission': {
      'policy': first['policy'], 'accepted': syntaxAccepted,
      'diagnostics': diagnostics,
      'languageVersion': '${effective.major}.${effective.minor}',
      // Declared dependency boundary, not an observed runtime package check.
      'analyzerVersion': '10.0.1', 'flags': first['flags'],
    },
    'sourceSHA256': sha256.convert(utf8.encode(source)).toString(),
    'sourceUtf16Length': source.length, 'gateError': gateError,
    'rawSyntaxReceipts': receipts,
    'languageConfigurationFacts': {
      'configuredSdkVersion': first['sdkLanguageVersion'],
      'scannerOverride': index.unit.languageVersion.override?.toString(),
      'libraryPackageVersion': index.unit.languageVersion.package.toString(),
      'libraryEffectiveVersion': index.unit.languageVersion.effective.toString(),
      'analyzerVersionOrigin': 'declared pinned dependency;not runtime verification',
    },
    'consumerFacts': facts, 'linkedReceipts': facts,
    'rawIssues': [for (var i = 0; i < context.issues.length; i++)
      projection.rawIssue(context.issues[i], i)],
    'rawDeclarations': [for (final value in projection.declarations.values)
      projection.rawDeclaration(value)],
    'rawOwnerFacts': projection.rawOwners(),
    'rawBindings': [for (final reference in references)
      projection.referenceFacts(reference.key, reference.value)],
    'factsOrigin': 'Reconstructed from admitted AST/index/lex/writes;'
        'not a recorded runtime lookup trace or inventory-collector result',
  };
}

class _ApiObserverProjection2121 {
  final _ApiSourceContext context;
  final _ApiScopeIndex index;
  final Map<int, _ApiDeclaration> declarations = {};
  final Map<int, _ApiOwner> owners = {};
  final List<ast.AstNode> nodes = [];
  _ApiObserverProjection2121(this.context, this.index) {
    void collect(ast.AstNode node) {
      if (index._inside(node)) nodes.add(node);
      for (final child in node.childEntities.whereType<ast.AstNode>()) {
        collect(child);
      }
    }
    collect(index.unit);
    for (final mapped in [index.root, ...index._owners.values]) {
      for (_ApiOwner? current = mapped; current != null; current = current.parent) {
        owners[current.id] = current;
        for (final named in current.names.values) {
          for (final value in named) {
            declarations[value.id] = value;
          }
        }
      }
    }
  }

  String get source => context.source;
  _ApiOwner semanticOwner(_ApiOwner owner) {
    var current = owner;
    while (current.parent != null &&
        !const {'unit', 'executable', 'class', 'loop', 'catch'}.contains(current.kind)) {
      current = current.parent!;
    }
    return current; // Actual semantic ancestor; lexical barriers remain in rawOwnerFacts/linkedReceipts.
  }

  bool isForIn(_ApiOwner owner) => owner.kind == 'loop' && nodes.any((node) {
    if (index.originalOffset(node.offset) != owner.originOffset) return false;
    if (node is ast.ForStatement) return node.forLoopParts is ast.ForEachParts;
    if (node is ast.ForElement) return node.forLoopParts is ast.ForEachParts;
    return false;
  });

  Map<String, Object?> ownerFacts() => {
    for (final owner in owners.values)
      if (identical(semanticOwner(owner), owner)) 'o:${owner.id}': {
        'kind': isForIn(owner) ? 'forIn' : owner.kind,
        'line': _lineOf(source, owner.originOffset),
      },
  };

  Map<String, Object?>? declaration(_ApiDeclaration? value) => value == null ? null : {
    'line': _lineOf(source, value.declarationOffset), 'name': value.name,
    'id': 'd:${value.id}', 'ownerId': 'o:${semanticOwner(value.owner).id}',
  };

  Map<String, Object?> range(ast.AstNode node) {
    if (!index._inside(node)) throw StateError('Observer requires original mapped range');
    final start = index.originalOffset(node.offset), end = index.originalOffset(node.end);
    return {'start': start, 'end': end, 'text': source.substring(start, end)};
  }

  Map<String, Object?> rawDeclaration(_ApiDeclaration value) => {
    'id': value.id, 'name': value.name, 'ownerId': value.owner.id,
    'semanticOwnerId': semanticOwner(value.owner).id,
    'nameRange': {'start': value.nameOffset, 'end': value.nameOffset + value.name.length},
    'declarationOffset': value.declarationOffset, 'visibleAfter': value.visibleAfter,
    'allowForward': value.allowForward, 'instanceField': value.instanceField,
    'barrier': value.barrier, 'explicitType': value.explicitType,
    'initializerRange': value.initializer == null ? null : range(value.initializer!),
  };

  Map<String, Object?> rawOwners() => {
    for (final owner in owners.values) '${owner.id}': {
      'id': owner.id, 'parentId': owner.parent?.id, 'kind': owner.kind,
      'originOffset': owner.originOffset, 'originLine': _lineOf(source, owner.originOffset),
      'staticContext': owner.staticContext, 'boundary': owner.boundary,
      'inheritedBoundary': owner.inheritedBoundary,
      'ownedNodeRanges': [for (final entry in index._owners.entries)
        if (identical(entry.value, owner) && index._inside(entry.key)) range(entry.key)],
      'rangeOrigin': 'Actual mapped owned nodes;not an invented continuous scope extent',
    },
  };

  Map<String, Object?> referenceFacts(int offset, ast.SimpleIdentifier reference) {
    final selected = index.declarationAt(offset);
    return {
      'name': reference.name, 'referenceLine': _lineOf(source, offset),
      'referenceRange': range(reference), 'referenceOwnerId': index._owners[reference]!.id,
      'selectedDeclarationId': selected?.id,
      'declaration': selected == null ? null : rawDeclaration(selected),
      'qualified': reference.isQualified,
      'valueReference': index._isValueReference(reference),
      'origin': 'AST/declarationAt reconstruction;not a runtime lookup observation',
    };
  }

  ast.MethodInvocation? invocation(int offset) {
    final reference = index._references[offset];
    for (ast.AstNode? node = reference; node != null; node = node.parent) {
      if (node is ast.MethodInvocation && reference != null &&
          node.argumentList.arguments.any((argument) => argument.offset <= reference.offset &&
              argument.end >= reference.end)) {
        return node;
      }
    }
    return null;
  }

  List<String> methods(int offset) {
    final call = invocation(offset);
    if (call == null) return const [];
    final name = call.methodName.name;
    if (const {'get', 'post', 'patch', 'put', 'delete', 'getList', 'getRaw',
        'getText', 'streamLines', 'uploadBytes'}.contains(name)) {
      return [_methodForClientCall(name)];
    }
    if (call.target != null) return const [];
    if (const {'_getFirstAvailable', '_getRawFirstAvailable', '_getPage'}.contains(name)) {
      return const ['GET'];
    }
    if (const {'_postFirstAvailable', '_postEmailCodeFirstAvailable'}.contains(name)) {
      return const ['POST'];
    }
    if (name == '_uploadFirstAvailable') return const ['POST', 'PATCH', 'PUT'];
    if (name == '_sendFirstAvailable' && call.argumentList.arguments.isNotEmpty) {
      final argument = call.argumentList.arguments.first;
      final literal = context.lex.stringList(_DartRouteArgument(
          index.originalOffset(argument.offset), index.originalOffset(argument.end)));
      if (literal != null) return literal.map((value) => value.toUpperCase()).toList();
      final selected = index.declarationAt(index.originalOffset(argument.offset));
      final actual = selected == null ? null : index._memo[(selected.id, _ApiValueKind.stringList)];
      return actual?.values?.map((value) => value.toUpperCase()).toList() ?? const [];
    }
    return const []; // Unknown/multiple method facts are not fabricated as GET.
  }

  bool blockedApiConcat(_ApiBindingIssue issue, _ApiDeclaration? selected) =>
      issue.fatal && issue.reason == 'unknownParameter' &&
      selected?.initializer is ast.BinaryExpression &&
      (selected!.initializer as ast.BinaryExpression).operator.lexeme == '+' &&
      index._hasApiSource(selected);

  String reason(_ApiBindingIssue issue, _ApiDeclaration? selected) =>
      blockedApiConcat(issue, selected) ? 'blockedKnownApiDependency' : issue.reason;

  String? cause(_ApiBindingIssue issue, _ApiDeclaration? selected, String normalized) {
    if (normalized != 'blockedKnownApiDependency') return null;
    ast.Expression first = selected!.initializer!;
    while (first is ast.BinaryExpression && first.operator.lexeme == '+') {
      first = first.leftOperand;
    }
    final leading = first is ast.SimpleIdentifier
        ? index.declarationAt(index.originalOffset(first.offset)) : null;
    return leading?.barrier == 'unknownParameter' &&
        leading?.id == issue.declaration?.id
        ? 'unknownParameter/dynamicLeadingApiConcat'
        : 'unknownParameter/unsupportedApiConcat';
  }

  int? writeLine(_ApiBindingIssue issue, _ApiDeclaration? selected) {
    if (issue.reason != 'writtenByForIn' || selected == null) return null;
    for (final write in index._writes) {
      if (write.kind == 'forIn' && write.name == selected.name &&
          write.offset < issue.consumerOffset &&
          identical(index._nearestIdentity(write.name, write.owner), selected)) {
        return _lineOf(source, write.offset); // Same first causative write as core lookup.
      }
    }
    return null;
  }

  Map<String, Object?>? obligation(_ApiBindingIssue issue,
      _ApiDeclaration? selected, String normalized) {
    if (!issue.fatal || selected?.initializer == null ||
        !const {'cycle', 'blockedKnownApiDependency'}.contains(normalized) ||
        !index._hasApiSource(selected!)) {
      return null;
    }
    final expression = selected.initializer!;
    final start = index.originalOffset(expression.offset), end = index.originalOffset(expression.end);
    final tokens = context.lex.strings.values.where((token) =>
        token.start >= start && token.end <= end).toList()
        ..sort((a, b) => a.start.compareTo(b.start));
    return {'line': _lineOf(source, start), 'expression': source.substring(start, end),
      'sourceTokens': [for (final token in tokens) token.value], 'failed': issue.fatal};
  }

  Map<String, Object?> rawIssue(_ApiBindingIssue issue, int ordinal) => {
    'ordinal': ordinal, 'reason': issue.reason, 'fatal': issue.fatal,
    'kind': issue.kind.name, 'consumerOffset': issue.consumerOffset,
    'blockedDeclaration': issue.declaration == null ? null : rawDeclaration(issue.declaration!),
    'dependencyIds': List<int>.from(issue.dependencyIds), 'description': issue.description,
  };

  Map<String, Object?>? blockingOwner(int offset) {
    final reference = index._references[offset];
    if (reference == null) return null;
    for (_ApiOwner? owner = index._owners[reference]; owner != null; owner = owner.parent) {
      if (owner.boundary == null && !index._patternOwners.contains(owner) &&
          !owner.inheritedBoundary) {
        continue;
      }
      ast.AstNode? extent;
      int? branchStart;
      for (ast.AstNode? node = reference; node != null; node = node.parent) {
        final actualBlock = identical(index._owners[node], owner) &&
            (node is ast.Block || node is ast.FunctionBody);
        final originNode = index.originalOffset(node.offset) == owner.originOffset &&
            (node is ast.ClassDeclaration || node is ast.ForStatement ||
             node is ast.ForElement || node is ast.CatchClause);
        final unsupportedTypeNode = owner.kind == 'unsupportedType' &&
            (node is ast.MixinDeclaration || node is ast.EnumDeclaration ||
             node is ast.ExtensionDeclaration || node is ast.ExtensionTypeDeclaration);
        final constructorNode = owner.kind == 'constructor' && node is ast.ConstructorDeclaration;
        // Pattern owners are introduced for a guarded branch; the surrounding
        // if/switch node itself is mapped to its enclosing owner. Link the
        // actual case/guard ownership to its supported AST branch extent.
        if (owner.kind == 'ifCase' && node is ast.IfStatement &&
            node.caseClause != null && identical(index._owners[node.caseClause!], owner)) {
          branchStart = index.originalOffset(node.caseClause!.offset);
          extent = node.thenStatement;
        } else if (owner.kind == 'ifCaseElement' && node is ast.IfElement &&
            node.caseClause != null && identical(index._owners[node.caseClause!], owner)) {
          branchStart = index.originalOffset(node.caseClause!.offset);
          extent = node.thenElement;
        } else if (owner.kind == 'switchCase' && node is ast.SwitchPatternCase &&
            identical(index._owners[node.guardedPattern], owner)) {
          extent = node;
        } else if (owner.kind == 'switchExpressionCase' && node is ast.SwitchExpressionCase &&
            identical(index._owners[node.guardedPattern], owner)) {
          extent = node;
        }
        if (extent != null) {
          if (!index._inside(extent)) throw StateError('Blocking owner extent mapping');
          break;
        }
        if (index._inside(node) && (actualBlock || originNode || unsupportedTypeNode || constructorNode)) {
          extent = node;
          break;
        }
      }
      return {
        'id': 'o:${owner.id}', 'kind': owner.kind,
        'boundary': owner.boundary ?? (index._patternOwners.contains(owner)
            ? 'unsupportedPattern' : 'externalInheritanceBoundary'),
        'sourceStart': extent == null ? null : branchStart ?? index.originalOffset(extent.offset),
        'sourceEnd': extent == null ? null : index.originalOffset(extent.end),
        'rangeOrigin': extent == null ? 'unavailable from current index;not fabricated'
            : branchStart == null ? 'reconstructedAST containing owner node'
            : 'reconstructedAST guarded case clause through then branch;else excluded',
      };
    }
    return null;
  }

  Map<String, Object?> consumerFacts(_ApiBindingIssue issue,
      _ApiDeclaration? selected, List<String> methods, int ordinal) {
    final reference = index._references[issue.consumerOffset];
    final call = invocation(issue.consumerOffset);
    ast.Expression? argument;
    if (call != null && reference != null) {
      for (final value in call.argumentList.arguments) {
        if (value.offset <= reference.offset && value.end >= reference.end) {
          argument = value;
          break;
        }
      }
    }
    final dependencies = [for (final id in issue.dependencyIds)
      if (declarations[id] != null) declarations[id]!];
    return {
      'ordinal': ordinal, 'name': reference?.name, 'methods': methods,
      'consumerName': reference?.name,
      'consumerMethod': methods.length == 1 ? methods.single : null,
      'consumerStart': call == null ? null : index.originalOffset(call.offset),
      'consumerEnd': call == null ? null : index.originalOffset(call.end),
      'argumentStart': argument == null ? null : index.originalOffset(argument.offset),
      'argumentEnd': argument == null ? null : index.originalOffset(argument.end),
      'blockingOwner': blockingOwner(issue.consumerOffset),
      'origin': 'reconstructedAST;rawIssues carry actual core lookup diagnostics',
      'consumerRange': reference == null ? null : range(reference),
      'callRange': call == null ? null : range(call),
      'argumentRange': argument == null ? null : range(argument),
      'calleeName': call?.methodName.name,
      'selectedDeclaration': selected == null ? null : rawDeclaration(selected),
      'blockedDeclaration': issue.declaration == null ? null : rawDeclaration(issue.declaration!),
      'blockedOwnerId': issue.declaration?.owner.id,
      'blockedOwnerNodeRanges': [for (final entry in index._owners.entries)
        if (identical(entry.value, issue.declaration?.owner) && index._inside(entry.key))
          range(entry.key)],
      'dependencies': [for (final value in dependencies) {
        ...rawDeclaration(value),
        'initializerReferences': [for (final entry in index._references.entries)
          if (value.initializer != null &&
              entry.key >= index.originalOffset(value.initializer!.offset) &&
              entry.key < index.originalOffset(value.initializer!.end))
            referenceFacts(entry.key, entry.value)],
      }],
      'sourceObligationOrigin': 'Reconstructed initializer extent linked to actual failed binding;'
          'not an inventory-collector receipt',
    };
  }
}
