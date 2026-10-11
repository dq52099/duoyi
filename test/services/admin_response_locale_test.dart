import 'dart:convert';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/services/admin_api.dart';
import 'package:duoyi/services/admin_response_error.dart';
import 'package:duoyi/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'explicit API error locale overrides global locale without mutation',
    () {
      const diagnostics = <Object>[
        AdminResponseException(AdminResponseFailure.invalidPage),
        ApiException('无法连接服务器：private diagnostic'),
        ApiException('连接服务器超时：private diagnostic'),
        ApiException('500: private diagnostic'),
      ];
      for (final error in [...diagnostics, StateError('private diagnostic')]) {
        final zh = userVisibleApiError(error, locale: AppLocale.zh);
        final en = userVisibleApiError(error, locale: AppLocale.en);
        expect(en, isNot(zh));
        expect(en, isNot(matches(RegExp(r'[\u3400-\u9fff]'))));
        expect(en, isNot(contains('private diagnostic')));
        expect(I18n.current, AppLocale.zh);
      }
      expect(
        userVisibleApiError(
          StateError('private'),
          locale: AppLocale.en,
          fallbackMessage: 'Supplied 用户',
        ),
        'Supplied 用户',
      );
      for (final locale in AppLocale.values) {
        expect(
          userVisibleApiError(
            const ApiException('409: 用户编写内容'),
            locale: locale,
          ),
          '用户编写内容',
        );
      }
    },
  );

  setUp(() => I18n.setLocale(AppLocale.zh));
  tearDown(() => I18n.setLocale(AppLocale.zh));

  test(
    'typed admin diagnostics and safe messages follow live locale changes',
    () {
      for (final failure in AdminResponseFailure.values) {
        final error = AdminResponseException(
          failure,
          endpoint: '/api/admin/users',
        );
        final zh = error.message;
        final safeZh = userVisibleApiError(error);
        I18n.setLocale(AppLocale.en);
        expect(error, isA<ApiException>());
        expect(error.toString(), error.message);
        expect(error.message, isNot(zh));
        expect(error.message, isNot(matches(RegExp(r'[\u3400-\u9fff]'))));
        expect(userVisibleApiError(error), isNot(safeZh));
        expect(userVisibleApiError(error), isNot(contains('/api/')));
        expect(userVisibleApiError(error), isNot(contains('items')));
        I18n.setLocale(AppLocale.zh);
        expect(error.message, zh);
        expect(userVisibleApiError(error), safeZh);
      }
    },
  );

  test('malformed page items retain typed API errors', () {
    for (final entry in {
      'not a list': AdminResponseFailure.itemsNotList,
      <Object>[1]: AdminResponseFailure.itemNotObject,
    }.entries) {
      expect(
        () => AdminPage.fromJson(
          {'items': entry.key},
          fallbackLimit: 20,
          fallbackOffset: 0,
        ),
        throwsA(
          isA<AdminResponseException>().having(
            (error) => error.failure,
            'failure',
            entry.value,
          ),
        ),
      );
    }
  });

  final cases =
      <
        (
          String,
          Object,
          AdminResponseFailure,
          Future<Object?> Function(AdminApi),
        )
      >[
        (
          'missing page items',
          <String, Object>{},
          AdminResponseFailure.missingItems,
          (api) => api.listUsersPage(),
        ),
        (
          'invalid page',
          true,
          AdminResponseFailure.invalidPage,
          (api) => api.listUsersPage(),
        ),
        (
          'missing coin balance',
          <String, Object>{},
          AdminResponseFailure.missingCoinBalance,
          (api) => api.adjustUserCoins('synthetic-user', delta: 1),
        ),
        (
          'invalid groups',
          <String, Object>{},
          AdminResponseFailure.groupsNotList,
          (api) => api.listGroups(),
        ),
        (
          'invalid roles',
          <String, Object>{},
          AdminResponseFailure.rolesNotList,
          (api) => api.listRoles(),
        ),
        (
          'invalid group member',
          <Object>[1],
          AdminResponseFailure.groupNotObject,
          (api) => api.listGroups(),
        ),
        (
          'invalid role member',
          <Object>['not an object'],
          AdminResponseFailure.roleNotObject,
          (api) => api.listRoles(),
        ),
      ];
  for (final (name, body, failure, invoke) in cases) {
    test(
      'AdminApi emits typed $name failure without altering transport',
      () async {
        final requests = <http.Request>[];
        final httpClient = MockClient((request) async {
          requests.add(request);
          return http.Response(jsonEncode(body), 200);
        });
        addTearDown(httpClient.close);
        final api = AdminApi(
          ApiClient(baseUrl: 'https://duoyi.test', httpClient: httpClient),
        );
        await expectLater(
          invoke(api),
          throwsA(
            isA<AdminResponseException>().having(
              (error) => error.failure,
              'failure',
              failure,
            ),
          ),
        );
        expect(requests, hasLength(1));
      },
    );
  }

  test('generic and network errors use the selected locale safely', () {
    I18n.setLocale(AppLocale.en);
    expect(
      userVisibleApiError(StateError('internal diagnostic')),
      'Service unavailable. Please try again later or contact an administrator.',
    );
    expect(
      userVisibleApiError(const ApiException('无法连接服务器：internal diagnostic')),
      'Could not connect to the server. Check your network and try again.',
    );
    expect(
      userVisibleApiError(const ApiException('连接服务器超时：internal diagnostic')),
      'Connection timed out. Please try again.',
    );
    expect(
      userVisibleApiError(
        StateError('internal'),
        fallbackMessage: 'Custom text 用户',
      ),
      'Custom text 用户',
    );
  });

  test(
    'untyped server messages and administrator-authored values stay literal',
    () {
      const serverText = '400: 项目 Aurora 不允许此操作';
      for (final locale in AppLocale.values) {
        I18n.setLocale(locale);
        expect(
          userVisibleApiError(const ApiException(serverText)),
          '项目 Aurora 不允许此操作',
        );
        final page = AdminPage.fromJson(
          {
            'items': [
              {'name': '管理员定义的组', 'description': '保持此文本'},
            ],
          },
          fallbackLimit: 20,
          fallbackOffset: 0,
        );
        expect(page.items.single['name'], '管理员定义的组');
        expect(page.items.single['description'], '保持此文本');
      }
    },
  );

  test('unconfirmed coin adjustment warns against blind retry', () {
    const error = AdminResponseException(
      AdminResponseFailure.missingCoinBalance,
    );
    I18n.setLocale(AppLocale.en);
    expect(userVisibleApiError(error), contains('Refresh to check'));
    expect(userVisibleApiError(error), contains('before adjusting again'));
  });
}
