import 'i18n.dart';
import '../services/api_client.dart';

/// 账号相关页面（登录、我的、个人资料）专用文案字典与异常本地化格式化工具。
///
/// 遵循设计规范：
/// 1. 不暴露实现细节与底层技术栈（无 HTTP 状态码、协议、堆栈、异常类名）。
/// 2. 错误文案具备明确可操作性，指导用户下一步操作。
/// 3. 支持中英双语，实时响应 [I18n.current]。
/// 4. 成功反馈简短明确。
class AccountUiCopy {
  AccountUiCopy._();

  static bool get isEn => I18n.current == AppLocale.en;

  // --- 状态标识 ---
  static String get statusNotLoggedIn => isEn ? 'Not Logged In' : '未登录';
  static String get statusLoggedIn => isEn ? 'Logged In' : '已登录';
  static String get statusSyncing => isEn ? 'Syncing...' : '同步中...';
  static String get statusSyncFailed => isEn ? 'Sync Failed' : '同步失败';
  static String get statusNoData => isEn ? 'No Data' : '暂无数据';
  static String get noDataPlaceholder => '—';
  static String get statusLocalMode => isEn ? 'Local Mode' : '本地使用';
  static String get statusVerified => isEn ? 'Verified' : '已验证';
  static String get statusUnverified => isEn ? 'Unverified' : '待验证';

  // --- 操作反馈 ---
  static String get feedbackSaved => isEn ? 'Saved' : '已保存';
  static String get feedbackUpdated => isEn ? 'Updated' : '已更新';
  static String get feedbackAvatarSaved => isEn ? 'Avatar updated' : '头像已更新';
  static String get feedbackPasswordChanged =>
      isEn ? 'Password changed' : '密码已修改';
  static String get feedbackLoggedOut => isEn ? 'Logged out' : '已退出登录';
  static String get feedbackCodeSent => isEn ? 'Code sent' : '验证码已发送';

  static String get tooltipShowPassword => isEn ? 'Show password' : '显示密码';
  static String get tooltipHidePassword => isEn ? 'Hide password' : '隐藏密码';

  // --- 页面文本与提示 ---
  static String get loginHeaderHint => isEn
      ? 'Log in to sync your habits, todos and data.'
      : '登录后可跨设备同步习惯、待办与专注数据';
  static String get registerHeaderHint =>
      isEn ? 'Create your account to start cloud sync.' : '注册多仪账号，开启多端数据自动同步';
  static String get emailLoginHeaderHint => isEn
      ? 'Quick log in with your email verification code.'
      : '使用已绑定的邮箱验证码快捷安全登录';

  static String get profileLocalHint =>
      isEn ? 'Profile stored locally on this device.' : '当前为本地资料，登录账号后可同步至云端';
  static String get profileAccountSecuritySubtitle =>
      isEn ? 'Manage password and account protection' : '密码保护与身份安全设置';
  static String get profileEmailBindingSubtitle =>
      isEn ? 'Used for login, verification and recovery' : '用于验证码登录、安全校验与密码找回';

  // --- 错误提示格式化 ---
  /// 将任意异常（ApiException、网络异常、本地异常）格式化为语义明确、可操作的用户友好文案。
  /// 坚决杜绝 e.toString()、HTTP 状态码、技术栈与类名泄露。
  static String formatError(Object? error, {String? defaultAction}) {
    if (error == null) {
      return isEn ? 'Operation failed, please try again.' : '操作未成功，请稍后重试';
    }

    if (error is! ApiException && error is! String) {
      return isEn
          ? (defaultAction ?? 'Operation failed. Please try again.')
          : (defaultAction ?? '操作未能完成，请重试');
    }

    final String rawMessage = error is ApiException
        ? userVisibleApiError(error)
        : error as String;
    final lower = rawMessage.toLowerCase();

    if (lower.contains('当前密码不正确') ||
        lower.contains('current password is incorrect')) {
      return isEn
          ? 'Current password is incorrect. Please check and retry.'
          : '当前密码不正确，请核对后重试';
    }

    // 凭据错误
    if (lower.contains('invalid credentials') ||
        lower.contains('invalid username or password') ||
        lower.contains('incorrect username or password') ||
        lower.contains('密码错误') ||
        lower.contains('账号或密码') ||
        lower.contains('用户名或密码')) {
      return I18n.tr('auth.error.invalid_credentials');
    }

    // 频率与尝试次数限制（必须排在验证码错误前，优先匹配“验证码错误次数过多”与“次数过多”）
    if (lower.contains('验证码错误次数过多') ||
        lower.contains('次数过多') ||
        lower.contains('too many requests') ||
        lower.contains('too many attempts') ||
        lower.contains('rate limit') ||
        lower.contains('频繁') ||
        (error is ApiException && error.message.startsWith('429:'))) {
      if (lower.contains('验证码') || lower.contains('code')) {
        return isEn
            ? 'Too many failed code attempts. Please try again later.'
            : '验证码错误次数过多，请稍后再试';
      }
      return isEn
          ? 'Too many attempts. Please wait a moment and try again.'
          : '操作过于频繁，请稍候片刻再试';
    }

    // 验证码错误或过期
    if (lower.contains('invalid email code') ||
        lower.contains('invalid code') ||
        lower.contains('code expired') ||
        lower.contains('验证码错误') ||
        lower.contains('验证码已过期') ||
        lower.contains('验证码不正确') ||
        lower.contains('验证码无效')) {
      return isEn
          ? 'Verification code is invalid or expired. Please request a new one.'
          : '验证码不正确或已失效，请重新获取后输入';
    }

    // 邀请码无效
    if (lower.contains('invalid invite code') ||
        lower.contains('invalid invitation code') ||
        lower.contains('邀请码无效') ||
        lower.contains('邀请码错误')) {
      return isEn
          ? 'Invitation code is invalid. Please check and retry.'
          : '邀请码无效或已失效，请核对后重试';
    }

    // 注册关闭
    if (lower.contains('registration disabled') ||
        lower.contains('registration is disabled') ||
        lower.contains('registration closed') ||
        lower.contains('暂未开放注册') ||
        lower.contains('注册已关闭')) {
      return isEn ? 'Registration is currently closed.' : '系统暂未开放注册，请联系管理员';
    }

    // 账号被停用
    if (lower.contains('account disabled') ||
        lower.contains('account is disabled') ||
        lower.contains('账号已停用') ||
        lower.contains('账号已被停用') ||
        lower.contains('账号被禁用')) {
      return isEn
          ? 'Account has been disabled. Please contact administrator.'
          : '该账号已被停用，请联系管理员';
    }

    // 认证凭据与 Token 失效
    if (lower.contains('invalid or expired token') ||
        lower.contains('invalid token') ||
        lower.contains('token expired') ||
        lower.contains('unauthorized') ||
        lower.contains('登录已过期') ||
        lower.contains('未登录') ||
        lower.contains('请先登录')) {
      return isEn ? 'Session expired. Please log in again.' : '登录状态已失效，请重新登录';
    }

    // 用户名或邮箱冲突（聚合及独立匹配）
    if (lower.contains('用户名或邮箱已被使用') ||
        lower.contains('username or email already in use') ||
        lower.contains('username or email already registered')) {
      return isEn
          ? 'Username or email is already in use. Please choose another.'
          : '用户名或邮箱已被使用，请更换后重试';
    }

    // 用户已存在
    if (lower.contains('user already exists') ||
        lower.contains('username already taken') ||
        lower.contains('用户已存在') ||
        lower.contains('用户名已被注册') ||
        lower.contains('该用户名已被占用')) {
      return isEn
          ? 'Username is already taken. Please choose another.'
          : '该用户名已被占用，请尝试其他名称';
    }

    // 邮箱冲突
    if (lower.contains('email already registered') ||
        lower.contains('email already in use') ||
        lower.contains('邮箱已被绑定') ||
        lower.contains('邮箱已被注册')) {
      return isEn
          ? 'This email is already associated with another account.'
          : '该邮箱已被其他账号绑定，请使用其他邮箱';
    }

    // 权限不足
    if (lower.contains('forbidden') ||
        lower.contains('permission denied') ||
        lower.contains('无权限') ||
        lower.contains('权限不足')) {
      return isEn
          ? 'You do not have permission to perform this action.'
          : '暂无当前操作权限，请联系管理员';
    }

    // 网络连接与解析
    if (lower.contains('failed host lookup') ||
        lower.contains('connection refused') ||
        lower.contains('no route to host') ||
        lower.contains('socketexception') ||
        lower.contains('network') ||
        lower.contains('网络') ||
        lower.contains('无法连接')) {
      return isEn
          ? 'Network connection failed. Please check your network and retry.'
          : '网络连接失败，请检查网络设置后重试';
    }

    // 超时
    if (lower.contains('timeout') ||
        lower.contains('timed out') ||
        lower.contains('超时')) {
      return isEn
          ? 'Connection timed out. Please check your network and retry.'
          : '请求超时，请检查网络连接后重试';
    }

    // 头像相关
    if (lower.contains('file_empty') || lower.contains('文件为空')) {
      return isEn
          ? 'Selected image is empty. Please choose another.'
          : '所选图片文件为空，请重新选择';
    }
    if (lower.contains('too_large') ||
        lower.contains('过大') ||
        lower.contains('3mb')) {
      return isEn
          ? 'Image is too large. Please select an image under 3MB.'
          : '图片大小超过限制，请选择 3MB 以内的图片';
    }

    // 服务端异常（500/502/503）
    if (rawMessage == defaultUserVisibleBackendErrorMessage ||
        lower.contains('internal server error') ||
        lower.contains('服务暂不可用')) {
      return isEn
          ? 'Service is temporarily unavailable. Please try again later.'
          : '服务暂不可用，请稍后重试或联系管理员';
    }

    // 包含技术实现细节、格式异常、堆栈特征的兜底
    if (lower.contains('exception') ||
        lower.contains('error:') ||
        lower.contains('http') ||
        lower.contains('{') ||
        lower.contains('format') ||
        lower.contains('type')) {
      return isEn
          ? (defaultAction ?? 'Operation failed. Please try again.')
          : (defaultAction ?? '操作未能完成，请重试');
    }

    // 如果清洗后的文本依然具备良好可读性（纯中文/英文日常文案），直接返回
    return rawMessage.trim();
  }
}
