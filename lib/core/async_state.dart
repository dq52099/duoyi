/// 统一的异步三态封装。
///
/// Provider 层用 `AsyncState<T>` 暴露状态；UI 层按 `switch` 分支渲染
/// `LoadingState / ErrorState / EmptyState / 正常内容`。
///
/// 这是 `Requirement 10.3` 的实现骨架，[AsyncLoading] / [AsyncData] / [AsyncError]
/// 通过 `sealed class` 保证穷尽匹配。
sealed class AsyncState<T> {
  const AsyncState();

  /// 当前是否正在加载。
  bool get isLoading => this is AsyncLoading<T>;

  /// 当前是否是错误态。
  bool get hasError => this is AsyncError<T>;

  /// 当前是否拿到数据（成功态）。
  bool get hasData => this is AsyncData<T>;

  /// 若 [AsyncData]，返回 data，否则 null。
  T? get dataOrNull => switch (this) {
    AsyncData<T>(:final data) => data,
    _ => null,
  };

  /// 若 [AsyncError]，返回 error，否则 null。
  Object? get errorOrNull => switch (this) {
    AsyncError<T>(:final error) => error,
    _ => null,
  };

  /// 通用映射器：为三态提供统一的分支处理。
  R when<R>({
    required R Function() loading,
    required R Function(T data) data,
    required R Function(Object error, StackTrace? stack) error,
  }) {
    final self = this;
    if (self is AsyncLoading<T>) return loading();
    if (self is AsyncData<T>) return data(self.data);
    if (self is AsyncError<T>) return error(self.error, self.stackTrace);
    // 不会走到（sealed class 已穷尽），但保留编译通过。
    throw StateError('Unknown AsyncState subtype: $self');
  }
}

/// 正在加载 / 初始尚未返回。
final class AsyncLoading<T> extends AsyncState<T> {
  const AsyncLoading();

  @override
  bool operator ==(Object other) => other is AsyncLoading<T>;

  @override
  int get hashCode => (AsyncLoading<T>).hashCode;

  @override
  String toString() => 'AsyncLoading<$T>()';
}

/// 已拿到数据。`data` 允许为空集合 / 空字符串，UI 侧再决定展示 EmptyState。
final class AsyncData<T> extends AsyncState<T> {
  const AsyncData(this.data);

  final T data;

  @override
  bool operator ==(Object other) => other is AsyncData<T> && other.data == data;

  @override
  int get hashCode => Object.hash(AsyncData<T>, data);

  @override
  String toString() => 'AsyncData<$T>($data)';
}

/// 加载失败 / 抛出异常。带上 [stackTrace] 便于上报。
final class AsyncError<T> extends AsyncState<T> {
  const AsyncError(this.error, [this.stackTrace]);

  final Object error;
  final StackTrace? stackTrace;

  @override
  bool operator ==(Object other) =>
      other is AsyncError<T> &&
      other.error == error &&
      other.stackTrace == stackTrace;

  @override
  int get hashCode => Object.hash(AsyncError<T>, error, stackTrace);

  @override
  String toString() => 'AsyncError<$T>($error)';
}
