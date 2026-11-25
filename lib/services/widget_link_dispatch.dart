import 'widget_calendar_link.dart';

/// Set by the delivery callback, never by a caller-controlled URI parameter.
enum WidgetLinkOrigin { external, internalNotification }

/// Resolves widget links after data hydration and account binding validation.
/// Internal reminder callbacks may use unbound actions; external actions may not.
class WidgetLinkDispatch {
  const WidgetLinkDispatch(this.uri, {this.stale = false});

  final Uri? uri;
  final bool stale;

  static const entityHosts = {
    'todo',
    'habit',
    'course',
    'note',
    'diary',
    'goal',
    'anniversary',
    'countdown',
    'time-entry',
    'event',
    'pomodoro',
  };

  static bool requiresHydration(Uri uri) =>
      entityHosts.contains(uri.host) ||
      uri.host == 'calendar' ||
      uri.host == 'action';

  static bool requiresBinding(
    Uri uri, {
    WidgetLinkOrigin origin = WidgetLinkOrigin.external,
  }) {
    if (uri.host == 'action') {
      final action = uri.pathSegments.firstOrNull;
      // These recover a stale widget or open a new draft for the active
      // account. A quick todo carrying text writes data and stays bound.
      if (action == 'refresh_widgets') return false;
      if (action == 'quick_todo' &&
          (uri.queryParameters['text']?.trim().isEmpty ?? true)) {
        return false;
      }
      return uri.queryParameters['source'] == 'widget' ||
          origin != WidgetLinkOrigin.internalNotification;
    }
    if (uri.queryParameters['source'] != 'widget') return false;
    return (entityHosts.contains(uri.host) && uri.pathSegments.isNotEmpty) ||
        WidgetCalendarLink.hasDateRequest(uri);
  }

  static Future<WidgetLinkDispatch> resolve(
    Uri uri, {
    required Future<void> Function() hydrate,
    required Future<bool> Function(Uri) validate,
    required bool Function() isCurrent,
    WidgetLinkOrigin origin = WidgetLinkOrigin.external,
  }) async {
    await hydrate();
    if (!isCurrent()) return const WidgetLinkDispatch(null);
    if (WidgetCalendarLink.hasDateRequest(uri) &&
        WidgetCalendarLink.dateFromUri(uri) == null) {
      return WidgetLinkDispatch(Uri(scheme: 'duoyi', host: 'calendar'));
    }
    if (!requiresBinding(uri, origin: origin)) return WidgetLinkDispatch(uri);
    // The widget validator accepts plain reminder URIs. Reject an external
    // unbound action here rather than letting that compatibility path bless it.
    if (uri.host == 'action' && uri.queryParameters['source'] != 'widget') {
      return const WidgetLinkDispatch(null, stale: true);
    }
    final valid = await validate(uri);
    if (!isCurrent()) return const WidgetLinkDispatch(null);
    if (!valid) {
      if (uri.host == 'event' || uri.host == 'pomodoro') {
        return WidgetLinkDispatch(
          Uri(
            scheme: 'duoyi',
            host: uri.host == 'event' ? 'calendar' : 'focus',
          ),
          stale: true,
        );
      }
      return WidgetLinkDispatch(
        entityHosts.contains(uri.host) || WidgetCalendarLink.isCalendarUri(uri)
            ? Uri(scheme: 'duoyi', host: uri.host)
            : null,
        stale: true,
      );
    }
    // Only validated dispatch loses its origin marker. Preserve the received
    // delivery ID so deliberately repeated count-habit taps stay distinct.
    final parameters = Map<String, String>.from(uri.queryParameters)
      ..remove('source');
    return WidgetLinkDispatch(uri.replace(queryParameters: parameters));
  }
}
