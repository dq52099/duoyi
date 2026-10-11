/// Orders navigation at receipt time, before any hydration or validation await.
class WidgetNavigationRequests {
  int _latest = 0;

  WidgetNavigationRequest capture() =>
      WidgetNavigationRequest._(this, ++_latest);
}

class WidgetNavigationRequest {
  const WidgetNavigationRequest._(this._owner, this._sequence);

  final WidgetNavigationRequests _owner;
  final int _sequence;

  bool get isLatest => _owner._latest == _sequence;
}
