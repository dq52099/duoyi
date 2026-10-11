/// Resolves widget links after data hydration and account binding validation.
/// Plain reminder/external deep links retain their existing behavior.
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
  };

  static bool requiresHydration(Uri uri) =>
      entityHosts.contains(uri.host) ||
      uri.host == 'calendar' ||
      uri.host == 'action';

  static bool requiresBinding(Uri uri) {
    if (uri.queryParameters['source'] != 'widget') return false;
    if (uri.host == 'action') {
      final action = uri.pathSegments.firstOrNull;
      // These recover a stale widget or open a new draft for the active
      // account. A quick todo carrying text writes data and stays bound.
      if (action == 'refresh_widgets') return false;
      if (action == 'quick_todo' &&
          (uri.queryParameters['text']?.trim().isEmpty ?? true)) {
        return false;
      }
      return true;
    }
    return entityHosts.contains(uri.host) && uri.pathSegments.isNotEmpty;
  }

  static Future<WidgetLinkDispatch> resolve(
    Uri uri, {
    required Future<void> Function() hydrate,
    required Future<bool> Function(Uri) validate,
    required bool Function() isCurrent,
  }) async {
    await hydrate();
    if (!isCurrent()) return const WidgetLinkDispatch(null);
    if (!requiresBinding(uri)) return WidgetLinkDispatch(uri);
    final valid = await validate(uri);
    if (!isCurrent()) return const WidgetLinkDispatch(null);
    if (!valid) {
      return WidgetLinkDispatch(
        entityHosts.contains(uri.host)
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
