/// Orders navigation at receipt time, before any hydration or validation await.
class WidgetNavigationRequests {
  WidgetNavigationRequests({int Function()? accountGeneration})
    : _accountGeneration = accountGeneration;

  final int Function()? _accountGeneration;
  int _latest = 0;

  WidgetNavigationRequest capture() =>
      WidgetNavigationRequest._(this, ++_latest, _accountGeneration?.call());
}

class WidgetNavigationRequest {
  const WidgetNavigationRequest._(
    this._owner,
    this._sequence,
    this._accountGeneration,
  );

  final WidgetNavigationRequests _owner;
  final int _sequence;
  final int? _accountGeneration;

  bool get isLatest => _owner._latest == _sequence;
  bool get isCurrentAccount =>
      _owner._accountGeneration?.call() == _accountGeneration;
}
