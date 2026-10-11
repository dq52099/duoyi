import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _between(String source, String start, String end) {
  final first = source.indexOf(start);
  final last = source.indexOf(end, first);
  expect(first, greaterThanOrEqualTo(0));
  expect(last, greaterThan(first));
  return source.substring(first, last);
}

void main() {
  final main = File('lib/main.dart').readAsStringSync();

  test('receipt order survives shell retries, queuing and hydration', () {
    expect(main, contains('WidgetNavigationRequest request}'));
    final handle = _between(
      main,
      'void _handleWidgetUri(',
      'void _routeHydratedWidgetUri(',
    );
    final capture = handle.indexOf('_widgetNavigationRequests.capture()');
    final retry = handle.indexOf('if (state == null && retry < 8)');
    expect(capture, greaterThanOrEqualTo(0));
    expect(retry, greaterThan(capture));
    expect(handle, contains('navigationRequest: request'));
    expect(handle, contains('allowQueue: allowQueue'));
    expect(handle, contains('dataReady: dataReady'));
    expect(
      handle,
      contains('_dispatchWidgetUriAfterHydration(uri, pomodoro, request)'),
    );
    expect(main, contains('navigationRequest: launch.request'));
    expect(
      main,
      contains(
        '_pendingWidgetUris[existingIndex] = (uri: uri, request: request)',
      ),
    );
  });

  test(
    'dated routing uses a separate CalendarScreen and keeps the shell key',
    () {
      final branch = _between(
        main,
        "} else if (uri.host == 'calendar') {",
        "} else if (uri.host == 'focus') {",
      );
      expect(branch, contains('state.navigateTo(3, allowHidden: true)'));
      expect(branch, contains('WidgetCalendarLink.dateFromUri(uri)'));
      expect(
        branch,
        contains('_openWidgetCalendarDate(ctx, date, navigationRequest)'),
      );
      expect(
        branch,
        contains('_widgetCalendarRoutes.showSection(Navigator.of(ctx))'),
      );
      expect(
        main,
        contains(
          '3 => CalendarScreen(key: calendarKey, useShellBackground: true)',
        ),
      );
      expect(main, contains('child: CalendarScreen(initialDate: date)'));
    },
  );

  test('deferred route retains account, caller and latest-request guards', () {
    final open = _between(
      main,
      'void _openWidgetCalendarDate(',
      'void _pushHiddenWidgetFallbackRoute(',
    );
    final capture = open.indexOf('final auth = context.read<AuthProvider>()');
    final scope = open.indexOf('final scope = WidgetActionScope(');
    final frame = open.indexOf('scope.afterFrame(');
    expect(capture, greaterThanOrEqualTo(0));
    expect(scope, greaterThan(capture));
    expect(frame, greaterThan(scope));
    expect(open, contains('context.mounted'));
    expect(open, contains('!_widgetAccountUnavailable(auth)'));
    expect(open, contains('request.isLatest'));
    expect(open, contains("RouteSettings(name: 'widget/calendar/date')"));
    expect(open, contains('_widgetCalendarRoutes.open(navigator, route)'));
  });

  test('section entries reveal the target beneath an owned date route', () {
    final section = _between(
      main,
      'void _navigateWidgetSection(',
      'void _routeHydratedWidgetUri(',
    );
    expect(section, contains('state.navigateTo(index, allowHidden: true)'));
    expect(section, contains('context.mounted'));
    expect(
      section,
      contains('_widgetCalendarRoutes.showSection(Navigator.of(context))'),
    );
    final route = _between(
      main,
      'void _routeHydratedWidgetUri(',
      'void _openWidgetCalendarDate(',
    );
    expect(route, contains('_navigateWidgetSection(state, ctx, idx)'));
    expect(route, contains('_navigateWidgetSection(state, ctx, 4)'));
    expect(route, contains('_navigateWidgetSection(state, ctx, 5)'));
    // A dated Calendar entry keeps its current route for replacement.
    expect(RegExp(r'state\.navigateTo\(').allMatches(route), hasLength(1));
    final fallback = _between(
      main,
      'void _pushHiddenWidgetFallbackRoute(',
      'void _showWidgetActionFeedback(',
    );
    expect(
      fallback,
      contains('_widgetCalendarRoutes.showSection(Navigator.of(context))'),
    );
  });

  test(
    'outer hydration continuation rechecks scope before routing or feedback',
    () {
      final dispatch = _between(
        main,
        'Future<void> _dispatchWidgetUriAfterHydration(',
        'Future<void> _refreshWidgetsFromAction(',
      );
      final resolve = dispatch.indexOf('await WidgetLinkDispatch.resolve(');
      final outerCheck = dispatch.indexOf('if (!scope.isCurrent) {', resolve);
      final feedback = dispatch.indexOf('if (result.stale) {', resolve);
      final route = dispatch.indexOf('_handleWidgetUri(', resolve);
      expect(resolve, greaterThanOrEqualTo(0));
      expect(outerCheck, greaterThan(resolve));
      expect(feedback, greaterThan(outerCheck));
      expect(route, greaterThan(outerCheck));
      expect(dispatch, contains('navigationRequest: navigationRequest'));
      expect(
        dispatch,
        contains(
          '!_isCalendarNavigationUri(uri) || navigationRequest.isLatest',
        ),
      );
      expect(dispatch, contains('HomeWidgetService.isReceivedLaunch(uri)'));
      expect(
        dispatch,
        contains('!HomeWidgetService.isReceivedLaunch(result.uri!)'),
      );
      expect(
        dispatch,
        contains('await HomeWidgetService.acknowledgeLaunch(uri)'),
      );
    },
  );
}
