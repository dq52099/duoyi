import 'i18n.dart';
import '../services/api_client.dart';

/// 许愿与反馈页面专用文案字典与异常本地化格式化工具。
///
/// 遵循设计规范：
/// 1. 不暴露底层技术细节（无 HTTP 状态码、协议、堆栈、异常类名、e.toString()）。
/// 2. 支持中英双语，实时响应 [I18n.current] 或可选显式 [AppLocale]。
/// 3. 支持动态数值（分页、总条数、分类标签插值）。
/// 4. 服务端原始数据（反馈正文、回复内容、时间戳）原样展示，不强行翻译。
class FeedbackUiCopy {
  FeedbackUiCopy._();

  static bool isEn([AppLocale? locale]) =>
      (locale ?? I18n.current) == AppLocale.en;

  // --- 导航与页面标题 ---
  static String screenTitle([AppLocale? locale]) =>
      isEn(locale) ? 'Feedback & Wishes' : '许愿与反馈';

  static String submitTitle([AppLocale? locale]) =>
      isEn(locale) ? 'Submit Feedback' : '提交许愿与反馈';

  static String submitHeaderTitle([AppLocale? locale]) =>
      isEn(locale) ? 'Submit Feedback' : '提交许愿与反馈';

  static String submitHeaderSubtitle([AppLocale? locale]) => isEn(locale)
      ? 'Choose a feedback category and submit; updates will appear in your feedback history'
      : '选择反馈类型后提交，处理进度会回到记录列表';

  static String historySectionTitle([AppLocale? locale]) =>
      isEn(locale) ? 'Feedback History' : '反馈记录';

  static String historySummary({
    required int total,
    required int page,
    required int totalPages,
    required bool loggedIn,
    AppLocale? locale,
  }) {
    if (!loggedIn) return loginRecordsRequired(locale);
    return isEn(locale)
        ? '$total items · Page $page/$totalPages'
        : '共 $total 条，当前第 $page/$totalPages 页';
  }

  // --- 分类与状态 ---
  static String normalizeCategory(String value) {
    return switch (value) {
      'bug' => 'bug',
      'wish' => 'wish',
      'other' => 'other',
      _ => 'feature',
    };
  }

  static String categoryLabel(String category, [AppLocale? locale]) {
    return switch (normalizeCategory(category)) {
      'bug' => isEn(locale) ? 'Bug report' : '问题反馈',
      'wish' => isEn(locale) ? 'Wish list' : '许愿池',
      'other' => isEn(locale) ? 'Other' : '其他',
      _ => isEn(locale) ? 'Feature request' : '功能建议',
    };
  }

  static String categoryHelp(String category, [AppLocale? locale]) {
    return switch (normalizeCategory(category)) {
      'bug' => isEn(locale)
          ? 'Describe reproduction steps, current behavior, and expected behavior'
          : '说明复现路径、当前表现和期望表现',
      'wish' => isEn(locale)
          ? 'Describe the scenario or capability you want added'
          : '写下你希望增加的场景或能力',
      'other' => isEn(locale)
          ? 'Add anything else you want the team to know'
          : '补充其他想让团队知道的信息',
      _ => isEn(locale)
          ? 'Describe the feature you want to add or improve'
          : '描述你想新增或优化的功能',
    };
  }

  static String statusLabel(String status, [AppLocale? locale]) {
    return switch (status) {
      'resolved' => isEn(locale) ? 'Resolved' : '已处理',
      'closed' => isEn(locale) ? 'Closed' : '已关闭',
      'in_progress' => isEn(locale) ? 'In progress' : '处理中',
      _ => isEn(locale) ? 'Open' : '待处理',
    };
  }

  static String categoryMenuLabel([AppLocale? locale]) =>
      isEn(locale) ? 'Type' : '类型';

  static String categoryLabelTooltip([AppLocale? locale]) =>
      isEn(locale) ? 'Category' : '分类';

  static String contentLabel(String category, [AppLocale? locale]) =>
      isEn(locale)
          ? 'Describe your ${categoryLabel(category, locale)}'
          : '描述一下你的${categoryLabel(category, locale)}';

  // --- 详情弹窗 ---
  static String detailTitle([AppLocale? locale]) =>
      isEn(locale) ? 'Feedback Detail' : '反馈详情';

  static String detailSubmittedAt([AppLocale? locale]) =>
      isEn(locale) ? 'Submitted' : '提交';

  static String detailUpdatedAt([AppLocale? locale]) =>
      isEn(locale) ? 'Updated' : '更新';

  static String detailContent([AppLocale? locale]) =>
      isEn(locale) ? 'Content' : '内容';

  static String detailReply([AppLocale? locale]) =>
      isEn(locale) ? 'Admin reply' : '管理员回复';

  static String detailEmptyContent([AppLocale? locale]) =>
      isEn(locale) ? 'No content' : '暂无内容';

  static String detailTooltip([AppLocale? locale]) =>
      isEn(locale) ? 'View feedback details' : '查看反馈详情';

  static String actionClose([AppLocale? locale]) =>
      isEn(locale) ? 'Close' : '关闭';

  // --- 分页 ---
  static String paginationPage(int page, int totalPages, [AppLocale? locale]) =>
      isEn(locale) ? 'Page $page/$totalPages' : '第 $page/$totalPages 页';

  static String paginationPrevious([AppLocale? locale]) =>
      isEn(locale) ? 'Previous' : '上一页';

  static String paginationNext([AppLocale? locale]) =>
      isEn(locale) ? 'Next' : '下一页';

  // --- 操作与提示 ---
  static String submitButton([AppLocale? locale]) =>
      isEn(locale) ? 'Submit feedback' : '提交反馈';

  static String submitting([AppLocale? locale]) =>
      isEn(locale) ? 'Submitting' : '提交中';

  static String submitted([AppLocale? locale]) =>
      isEn(locale) ? 'Feedback submitted. Thank you!' : '反馈已提交，感谢！';

  static String refresh([AppLocale? locale]) =>
      isEn(locale) ? 'Refresh' : '刷新';

  static String emptyHistory([AppLocale? locale]) =>
      isEn(locale) ? 'No feedback yet' : '还没有反馈记录';

  static String loginRecordsRequired([AppLocale? locale]) =>
      isEn(locale) ? 'Sign in to view feedback history' : '登录后可查看反馈记录';

  static String loginSubmitRequired([AppLocale? locale]) =>
      isEn(locale) ? 'Sign in before submitting feedback' : '请先登录后再提交反馈';

  static String loginSubmitPrefix(String category, [AppLocale? locale]) =>
      isEn(locale)
          ? 'Sign in to submit ${categoryLabel(category, locale)}'
          : '登录后提交${categoryLabel(category, locale)}';

  static String contentEmpty([AppLocale? locale]) =>
      isEn(locale) ? 'Feedback content cannot be empty' : '反馈内容不能为空';

  static String accountChangedReopen([AppLocale? locale]) => isEn(locale)
      ? 'Account changed. Reopen this page before trying again.'
      : '账号已发生变化，请在当前账号重试操作。';

  static String accountTransitionInProgress([AppLocale? locale]) => isEn(locale)
      ? 'Account is switching. Please wait and try again.'
      : '账号正在切换，请稍候再试';

  static String loginRequiredReopen([AppLocale? locale]) => isEn(locale)
      ? 'Please sign in and reopen the feedback page.'
      : '请先登录后再操作。';

  static String defaultError([AppLocale? locale]) =>
      isEn(locale) ? 'Operation failed. Please try again.' : '操作未成功，请稍后重试';

  // --- 错误提示格式化 ---
  static String formatError(
    Object? error, {
    String? defaultAction,
    AppLocale? locale,
  }) {
    final effectiveLocale = locale ?? I18n.current;
    final en = isEn(effectiveLocale);
    final genericFallback = en
        ? (defaultAction ?? 'Failed to process feedback. Please try again.')
        : (defaultAction ?? '操作未能完成，请稍后重试');

    if (error == null) {
      return en
          ? (defaultAction ?? 'Operation failed. Please try again.')
          : (defaultAction ?? '操作未成功，请稍后重试');
    }

    if (error is! ApiException && error is! String) {
      return genericFallback;
    }

    if (error is LocalizedUserVisibleApiException) {
      return error.userVisibleMessageForLocale(effectiveLocale);
    }
    if (error is UserVisibleApiException) {
      return error.userVisibleMessage;
    }

    final rawMsg = error is ApiException ? error.message : error as String;
    final lower = rawMsg.toLowerCase();

    // 1. 账号切换/过期业务校验
    if (lower.contains('账号已发生变化') ||
        lower.contains('account has changed') ||
        lower.contains('account changed')) {
      return accountChangedReopen(effectiveLocale);
    }
    if (lower.contains('账号正在切换') ||
        lower.contains('account is switching')) {
      return accountTransitionInProgress(effectiveLocale);
    }
    if (lower.contains('请先登录') ||
        lower.contains('please log in') ||
        lower.contains('please sign in') ||
        lower.contains('unauthorized') ||
        (error is ApiException && error.message.startsWith('401:'))) {
      return loginRequiredReopen(effectiveLocale);
    }

    // 2. 频率与速率限制业务校验
    if (lower.contains('次数过多') ||
        lower.contains('too many requests') ||
        lower.contains('rate limit') ||
        lower.contains('频繁') ||
        (error is ApiException && error.message.startsWith('429:'))) {
      return en
          ? 'Too many requests. Please wait a moment and try again.'
          : '操作过于频繁，请稍候片刻再试';
    }

    // 3. 反馈表单内容业务校验
    if (lower.contains('不能为空') ||
        lower.contains('cannot be empty') ||
        lower.contains('content is empty') ||
        lower.contains('empty content')) {
      return contentEmpty(effectiveLocale);
    }

    // 4. 网络传输异常
    if (lower.contains('network') ||
        lower.contains('socket') ||
        lower.contains('failed host lookup') ||
        lower.contains('connection') ||
        lower.contains('timeout') ||
        rawMsg.startsWith('无法连接服务器') ||
        rawMsg.startsWith('连接服务器超时')) {
      return en
          ? 'Network connection error. Please check your network and retry.'
          : '网络连接失败，请检查网络后重试';
    }

    // 5. 未知 4xx/5xx 或包含技术诊断信息（SQL、表结构、Internal 路径、令牌、协议异常等）
    // 屏蔽技术细节泄露，返回稳定双语通用提示。
    if (RegExp(r'^\d{3}:').hasMatch(rawMsg) ||
        lower.contains('sql') ||
        lower.contains('token=') ||
        (lower.contains('token') && lower.contains('synthetic')) ||
        lower.contains('/api/') ||
        lower.contains('internal') ||
        lower.contains('table') ||
        lower.contains('constraint') ||
        lower.contains('not found') ||
        lower.contains('exception') ||
        lower.contains('syntax') ||
        lower.contains('database') ||
        isBackendCompatibilityDiagnosticMessage(rawMsg)) {
      return genericFallback;
    }

    // 6. 普通文本错误兜底
    if (en) {
      if (RegExp(r'[\u3400-\u9fff]').hasMatch(rawMsg)) {
        return genericFallback;
      }
      return rawMsg.isNotEmpty ? rawMsg : genericFallback;
    } else {
      return rawMsg.isNotEmpty ? rawMsg : genericFallback;
    }
  }
}
