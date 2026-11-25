import 'i18n.dart';
import '../services/api_client.dart';

/// 共享空间（Shared Space）模块文案与异常本地化格式化工具。
///
/// 遵循全局文案设计原则：
/// - 每次 getter / function 调用动态读取 [I18n.current]，或接收显式 [locale]。
/// - 禁止在 static 顶层缓存翻译结果。
/// - 用户自定义内容（如空间名称、成员名称、评论内容、邀请码、协议 targetId）保留原始字符，仅翻译应用层文案。
/// - 杜绝向用户暴露底层异常类名、堆栈、HTTP 状态码及未经验证的后端诊断字符串。
class ShareUiCopy {
  ShareUiCopy._();

  static bool isEn([AppLocale? locale]) =>
      (locale ?? I18n.current) == AppLocale.en;

  // ---------------------------------------------------------------------------
  // 异常与错误本地化（Host / Provider / UI 集成）
  // ---------------------------------------------------------------------------

  /// 共享空间服务通用安全回退文案。
  static String serviceUnavailable([AppLocale? locale]) {
    return isEn(locale)
        ? 'Shared space service is temporarily unavailable. Please try again later or contact an administrator.'
        : '共享空间服务暂不可用，请稍后重试或联系管理员';
  }

  /// 将任意异常（ApiException、Local Exception、网络异常）格式化为语义明确的用户友好文案。
  ///
  /// - 坚决杜绝 e.toString()、HTTP 状态码、技术栈与类名泄露。
  /// - 翻译已验证的后端业务错误（如 No workspace access、Workspace name required 等）。
  /// - 未知诊断信息与底层异常统一使用安全的 localized service fallback。
  static String error(Object error, [AppLocale? locale]) {
    final effectiveLocale = locale ?? I18n.current;
    final en = isEn(effectiveLocale);

    if (error is LocalizedUserVisibleApiException) {
      return error.userVisibleMessageForLocale(effectiveLocale);
    }
    if (error is UserVisibleApiException) {
      return error.userVisibleMessage;
    }

    // 通过 userVisibleApiError 过滤 HTML 错误页及前后端兼容性内部诊断
    final raw = userVisibleApiError(
      error,
      fallbackMessage: '',
      locale: effectiveLocale,
    ).trim();

    if (raw.isEmpty) {
      return serviceUnavailable(effectiveLocale);
    }

    final lower = raw.toLowerCase();

    // 1. 无空间访问权限 (No workspace access)
    if (lower.contains('no workspace access') ||
        lower.contains('没有共享空间访问权限') ||
        lower.contains('无空间访问权限')) {
      return en ? 'No workspace access.' : '没有共享空间访问权限';
    }

    // 2. 空间名称必填 (Workspace name required)
    if (lower.contains('workspace name required') ||
        lower.contains('workspace name is required') ||
        lower.contains('空间名称不能为空') ||
        lower.contains('请输入空间名称')) {
      return en ? 'Workspace name is required.' : '空间名称不能为空';
    }

    // 3. 私有空间无法邀请 (Private workspace cannot invite)
    if (lower.contains('private workspace cannot invite') ||
        lower.contains('私有空间无法邀请成员') ||
        lower.contains('私有空间不能邀请')) {
      return en ? 'Private workspace cannot invite members.' : '私有空间无法邀请成员';
    }

    // 4. 邀请码不存在 / 已过期 (Invite not found / expired)
    if (lower.contains('invite not found') ||
        lower.contains('邀请码不存在') ||
        lower.contains('邀请码未找到')) {
      return en ? 'Invite code not found.' : '邀请码不存在';
    }
    if (lower.contains('invite expired') || lower.contains('邀请码已过期')) {
      return en ? 'Invite code has expired.' : '邀请码已过期';
    }

    // 5. 无效角色 (Invalid role)
    if (lower.contains('invalid role') ||
        lower.contains('无效的角色') ||
        lower.contains('无效的成员角色')) {
      return en ? 'Invalid member role.' : '无效的成员角色';
    }

    // 6. 评论内容必填 / 过长 (Comment body required / too long)
    if (lower.contains('comment body required') ||
        lower.contains('comment body is required') ||
        lower.contains('评论内容不能为空') ||
        lower.contains('请输入评论内容')) {
      return en ? 'Comment body is required.' : '评论内容不能为空';
    }
    if (lower.contains('comment body too long') ||
        lower.contains('comment is too long') ||
        lower.contains('评论内容过长')) {
      return en ? 'Comment is too long.' : '评论内容过长';
    }

    // 7. 登录要求 (Login required)
    if (lower.contains('login required') ||
        lower.contains('authentication required') ||
        lower.contains('not authenticated') ||
        lower.contains('unauthorized') ||
        lower.contains('请先登录') ||
        lower.contains('登录后')) {
      return en ? 'Please log in to continue.' : '请先登录后再操作';
    }

    // 8. 角色权限校验 (Editor/Owner role required/immutable)
    if (lower.contains('editor role required') || lower.contains('需要编辑者权限')) {
      return en ? 'Editor role required.' : '需要编辑者权限';
    }
    if (lower.contains('owner role required') || lower.contains('需要所有者权限')) {
      return en ? 'Owner role required.' : '需要所有者权限';
    }
    if (lower.contains('owner role cannot change') ||
        lower.contains('拥有者角色不能变更')) {
      return en ? 'Owner role cannot be changed.' : '拥有者角色不能变更';
    }
    if (lower.contains('owner cannot be removed') ||
        lower.contains('不能移除空间拥有者')) {
      return en ? 'Owner cannot be removed.' : '不能移除空间拥有者';
    }

    // 9. 提及通知未找到 (Mention not found)
    if (lower.contains('mention not found') || lower.contains('提及通知不存在')) {
      return en ? 'Mention not found.' : '提及通知不存在';
    }

    // 10. 私有空间限制 (Private workspace immutable / no leaderboard)
    if (lower.contains('private workspace is immutable') ||
        lower.contains('私有空间不可修改')) {
      return en ? 'Private workspace is immutable.' : '私有空间不可修改';
    }
    if (lower.contains('private workspace has no leaderboard') ||
        lower.contains('私有空间暂无排行榜')) {
      return en ? 'Private workspace has no leaderboard.' : '私有空间暂无排行榜';
    }

    // 11. 账号切换与会话租约冲突
    if (lower.contains('账号已发生变化') ||
        lower.contains('account has changed') ||
        lower.contains('account changed')) {
      return en
          ? 'Account changed. Reopen this page before trying again.'
          : '账号已切换，请重新打开页面后再操作';
    }
    if (lower.contains('账号正在切换') || lower.contains('account is switching')) {
      return en
          ? 'Account is switching. Please wait and try again.'
          : '账号正在切换，请稍候再试';
    }

    // 12. 网络与连接超时
    if (raw.contains('无法连接服务器') ||
        lower.contains('could not connect to the server')) {
      return en
          ? 'Could not connect to the server. Check your network and try again.'
          : '无法连接服务器，请检查网络后重试';
    }
    if (raw.contains('连接超时') || lower.contains('connection timed out')) {
      return en ? 'Connection timed out. Please try again.' : '连接超时，请稍后重试';
    }

    // 未知服务器诊断或格式错误统一安全回退
    return serviceUnavailable(effectiveLocale);
  }

  // ---------------------------------------------------------------------------
  // 主页面与导航文案
  // ---------------------------------------------------------------------------

  static String screenTitle([AppLocale? locale]) =>
      isEn(locale) ? 'Shared Spaces' : '共享空间';

  static String loggedOutMessage([AppLocale? locale]) => isEn(locale)
      ? 'Log in to create shared spaces and invite members.'
      : '登录后可以创建共享空间并邀请成员';

  static String heroDescription([AppLocale? locale]) => isEn(locale)
      ? 'Create a space to share to-dos with family, friends, or teammates.'
      : '创建空间后，把待办清单共享给家人、朋友或团队成员。';

  static String myWorkspacesTitle([AppLocale? locale]) =>
      isEn(locale) ? 'My Spaces' : '我的空间';

  static String myWorkspacesSubtitle([AppLocale? locale]) => isEn(locale)
      ? 'Owners can invite members. Viewers are read-only; editors can edit.'
      : '拥有者可邀请成员，只读成员仅查看，可编辑成员可编辑';

  static String emptyWorkspacesMessage([AppLocale? locale]) =>
      isEn(locale) ? 'No shared spaces yet' : '还没有共享空间';

  static String emptyWorkspacesAction([AppLocale? locale]) =>
      isEn(locale) ? 'Create Space' : '创建空间';

  static String membersCount(
    int count,
    String roleLabel, [
    AppLocale? locale,
  ]) => isEn(locale)
      ? '$count ${count == 1 ? 'member' : 'members'} · $roleLabel'
      : '$count 位成员 · $roleLabel';

  // ---------------------------------------------------------------------------
  // 操作按钮与 Tooltip 文案
  // ---------------------------------------------------------------------------

  static String actionLogin([AppLocale? locale]) =>
      isEn(locale) ? 'Log In' : '登录';

  static String actionNew([AppLocale? locale]) => isEn(locale) ? 'New' : '新建';

  static String actionCancel([AppLocale? locale]) =>
      isEn(locale) ? 'Cancel' : '取消';

  static String actionCreate([AppLocale? locale]) =>
      isEn(locale) ? 'Create' : '创建';

  static String actionJoin([AppLocale? locale]) => isEn(locale) ? 'Join' : '加入';

  static String actionGenerate([AppLocale? locale]) =>
      isEn(locale) ? 'Generate' : '生成';

  static String actionDone([AppLocale? locale]) => isEn(locale) ? 'Done' : '完成';

  static String actionSend([AppLocale? locale]) => isEn(locale) ? 'Send' : '发送';

  static String actionView([AppLocale? locale]) => isEn(locale) ? 'View' : '查看';

  static String actionRefreshTooltip([AppLocale? locale]) =>
      isEn(locale) ? 'Refresh' : '刷新';

  static String actionJoinTooltip([AppLocale? locale]) =>
      isEn(locale) ? 'Join Space' : '加入空间';

  static String collaborationTooltip([AppLocale? locale]) =>
      isEn(locale) ? 'Activities' : '协作动态';

  static String createInviteTooltip([AppLocale? locale]) =>
      isEn(locale) ? 'Create Invite Code' : '生成邀请码';

  static String defaultMemberName([AppLocale? locale]) =>
      isEn(locale) ? 'Member' : '成员';

  // ---------------------------------------------------------------------------
  // 提及收件箱 (@ Mentions)
  // ---------------------------------------------------------------------------

  static String mentionInboxTooltip(int unreadCount, [AppLocale? locale]) {
    if (unreadCount > 0) {
      return isEn(locale)
          ? '$unreadCount unread mentions'
          : '$unreadCount 条未读提及';
    }
    return isEn(locale) ? '@ Mentions' : '@ 提及';
  }

  static String mentionInboxTitle([AppLocale? locale]) =>
      isEn(locale) ? '@ Mentions' : '@ 提及';

  static String mentionInboxEmpty([AppLocale? locale]) =>
      isEn(locale) ? 'No members have mentioned you yet.' : '还没有成员提及你';

  // ---------------------------------------------------------------------------
  // 弹窗与表单 (Dialogs & Forms)
  // ---------------------------------------------------------------------------

  static String createWorkspaceTitle([AppLocale? locale]) =>
      isEn(locale) ? 'Create Shared Space' : '新建共享空间';

  static String workspaceNameLabel([AppLocale? locale]) =>
      isEn(locale) ? 'Space name' : '空间名称';

  static String joinWorkspaceTitle([AppLocale? locale]) =>
      isEn(locale) ? 'Join Shared Space' : '加入共享空间';

  static String inviteCodeLabel([AppLocale? locale]) =>
      isEn(locale) ? 'Invite code' : '邀请码';

  static String joinedWorkspaceSuccess([AppLocale? locale]) =>
      isEn(locale) ? 'Joined shared space' : '已加入共享空间';

  static String createInviteTitle([AppLocale? locale]) =>
      isEn(locale) ? 'Create Invite Code' : '生成邀请码';

  static String roleReadOnlyTitle([AppLocale? locale]) =>
      isEn(locale) ? 'Read-only member' : '只读成员';

  static String roleCanEditTitle([AppLocale? locale]) =>
      isEn(locale) ? 'Can-edit member' : '可编辑成员';

  static String inviteCopiedTitle([AppLocale? locale]) =>
      isEn(locale) ? 'Invite Code Copied' : '邀请码已复制';

  static String roleLabelPrefix(String roleLabel, [AppLocale? locale]) =>
      isEn(locale) ? 'Role: $roleLabel' : '角色：$roleLabel';

  // ---------------------------------------------------------------------------
  // 协作抽屉 (Collaboration Sheet)
  // ---------------------------------------------------------------------------

  static String collaborationSheetTitle(
    String workspaceName, [
    AppLocale? locale,
  ]) => isEn(locale) ? '$workspaceName · Collaboration' : '$workspaceName · 协作';

  static String commentInputHint([AppLocale? locale]) => isEn(locale)
      ? 'Write a comment, @username to notify members'
      : '写评论，@用户名/邮箱/昵称 可提醒成员';

  static String mentionContextTitle([AppLocale? locale]) =>
      isEn(locale) ? 'Mention Context' : '提及上下文';

  static String mentionContextEmpty(String targetId, [AppLocale? locale]) =>
      isEn(locale)
      ? 'This mention is linked to $targetId, but comments could not be loaded.'
      : '这条提及关联到 $targetId，当前页未加载到对应评论。';

  static String memberLeaderboardTitle([AppLocale? locale]) =>
      isEn(locale) ? 'Leaderboard' : '成员排行榜';

  static String memberLeaderboardEmpty([AppLocale? locale]) =>
      isEn(locale) ? 'No assigned tasks for ranking yet' : '还没有可排行的分配任务';

  static String leaderboardSubtitle(
    String roleLabel,
    int assigned,
    int completed, [
    AppLocale? locale,
  ]) => isEn(locale)
      ? '$roleLabel · Assigned $assigned · Completed $completed'
      : '$roleLabel · 分配 $assigned · 完成 $completed';

  static String latestCommentsTitle([AppLocale? locale]) =>
      isEn(locale) ? 'Latest Comments' : '最新评论';

  static String latestCommentsEmpty([AppLocale? locale]) =>
      isEn(locale) ? 'No comments yet' : '还没有评论';

  static String activitiesTitle([AppLocale? locale]) =>
      isEn(locale) ? 'Activity Stream' : '动态流';

  static String collaborationActivitiesTitle([AppLocale? locale]) =>
      isEn(locale) ? 'Activities' : '协作动态';

  static String activitiesEmpty([AppLocale? locale]) =>
      isEn(locale) ? 'No activity yet' : '还没有协作动态';

  // ---------------------------------------------------------------------------
  // 操作失败反馈提示
  // ---------------------------------------------------------------------------

  static String openMentionFailed(String error, [AppLocale? locale]) =>
      isEn(locale) ? 'Failed to open mention: $error' : '打开提及失败: $error';

  static String createWorkspaceFailed(String error, [AppLocale? locale]) =>
      isEn(locale) ? 'Failed to create space: $error' : '创建失败: $error';

  static String joinWorkspaceFailed(String error, [AppLocale? locale]) =>
      isEn(locale) ? 'Failed to join space: $error' : '加入失败: $error';

  static String createInviteFailed(String error, [AppLocale? locale]) =>
      isEn(locale) ? 'Failed to generate invite code: $error' : '生成失败: $error';

  static String sendCommentFailed(String error, [AppLocale? locale]) =>
      isEn(locale) ? 'Failed to send comment: $error' : '发送失败: $error';
}
