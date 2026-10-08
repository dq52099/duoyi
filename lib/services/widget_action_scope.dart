import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;

import 'account_local_data_cleaner.dart';

/// Retains the originating account through awaits and deferred frame delivery.
class WidgetActionScope {
  WidgetActionScope({bool Function()? isCallerAvailable})
    : _generation = AccountLocalDataCleaner.accountDataGeneration,
      _isCallerAvailable = isCallerAvailable;

  final int _generation;
  final bool Function()? _isCallerAvailable;

  bool get isCurrent =>
      AccountLocalDataCleaner.isCurrentAccountDataGeneration(_generation) &&
      (_isCallerAvailable?.call() ?? true);

  void afterFrame(VoidCallback callback) {
    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback((_) {
      if (isCurrent) callback();
    });
    // An async permission failure need not trigger another rebuild. Request a
    // frame so its feedback does not wait for the user's next screen touch.
    binding.ensureVisualUpdate();
  }
}
