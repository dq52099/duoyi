import '../core/i18n.dart';
import 'api_client.dart';

enum CloudSyncNoticeKind {
  failure,
  retryIncomplete,
  switchUploadTimedOut,
  switchUnsyncedLocal,
  realtimePollingFallback,
  remoteEventRetry,
  remoteCheckRetry,
  baselineRetry,
  remotePullRetry,
  featureDisabled,
  accountTransition,
  signedOut,
  serverDisabled,
  automaticSyncOff,
  queuedWaitingLocalChanges,
  queuedWaitingSync,
  queuedRemotePull,
}

/// Frozen sync facts, with generated copy selected only when displayed.
/// Raw errors always pass through the safe API formatter; authored API text
/// remains literal and never needs to be parsed back into a notice kind.
final class CloudSyncNotice {
  const CloudSyncNotice(this.kind, {this.error});

  final CloudSyncNoticeKind kind;
  final Object? error;

  CloudSyncNotice withKind(CloudSyncNoticeKind next) =>
      CloudSyncNotice(next, error: error);

  String render({AppLocale? locale}) {
    final effectiveLocale = locale ?? I18n.current;
    final isEn = effectiveLocale == AppLocale.en;
    String pick(String zh, String en) => isEn ? en : zh;
    final fallback = pick(
      '云同步暂不可用，请稍后重试或联系管理员',
      'Cloud sync is unavailable. Please try again later or contact an administrator.',
    );
    final context = switch (kind) {
      CloudSyncNoticeKind.failure => fallback,
      CloudSyncNoticeKind.retryIncomplete => pick(
        '云同步上次未完成，稍后会自动重试。',
        'Cloud sync is incomplete and will retry automatically.',
      ),
      CloudSyncNoticeKind.switchUploadTimedOut => pick(
        '本机改动上传超时，已暂停切换账号以避免未上传内容被清空。',
        'Uploading local changes timed out. Account switching is paused to protect changes that have not been uploaded.',
      ),
      CloudSyncNoticeKind.switchUnsyncedLocal => pick(
        '本机还有未上传服务器的改动，已暂停切换账号以避免本地内容被清空。',
        'Local changes have not been uploaded. Account switching is paused to protect them.',
      ),
      CloudSyncNoticeKind.realtimePollingFallback => pick(
        '实时同步连接中断，已切换到轮询兜底',
        'The live sync connection was interrupted. Periodic checks are now active',
      ),
      CloudSyncNoticeKind.remoteEventRetry => pick(
        '远端更新事件处理失败，稍后会自动重试',
        'The remote update event could not be processed. It will retry automatically',
      ),
      CloudSyncNoticeKind.remoteCheckRetry => pick(
        '远端更新检查失败，稍后会自动重试',
        'Checking for remote updates failed. It will retry automatically',
      ),
      CloudSyncNoticeKind.baselineRetry => pick(
        '同步基线建立失败，稍后会自动重试',
        'Initial sync could not be established. It will retry automatically',
      ),
      CloudSyncNoticeKind.remotePullRetry => pick(
        '远端更新拉取失败，稍后会自动重试',
        'Downloading remote updates failed. It will retry automatically',
      ),
      CloudSyncNoticeKind.featureDisabled => pick(
        '当前版本未启用云同步。',
        'Cloud sync is not enabled in this version.',
      ),
      CloudSyncNoticeKind.accountTransition => pick(
        '账号切换处理中，云同步已暂停。',
        'Cloud sync is paused while the account changes.',
      ),
      CloudSyncNoticeKind.signedOut => pick(
        '未登录云同步账号。',
        'Sign in to use cloud sync.',
      ),
      CloudSyncNoticeKind.serverDisabled => pick(
        '管理员已关闭云端备份。',
        'Cloud backup has been disabled by the administrator.',
      ),
      CloudSyncNoticeKind.automaticSyncOff => pick(
        '自动同步已关闭，尚未上传服务器。重新开启后会继续同步。',
        'Automatic sync is off. Changes have not been uploaded; sync will resume when enabled.',
      ),
      CloudSyncNoticeKind.queuedWaitingLocalChanges => pick(
        '远端有更新，正在等待本机待上传改动同步成功后再拉取，避免覆盖本机编辑。',
        'Remote updates are waiting for local changes to upload, so your edits are protected.',
      ),
      CloudSyncNoticeKind.queuedWaitingSync => pick(
        '远端有更新，当前同步完成后会继续拉取。',
        'Remote updates will download after the current sync completes.',
      ),
      CloudSyncNoticeKind.queuedRemotePull => pick(
        '远端有更新，正在排队拉取。',
        'Remote updates are queued for download.',
      ),
    };
    final cause = error;
    if (cause == null) return context;
    final detail = userVisibleApiError(
      cause,
      fallbackMessage: fallback,
      locale: effectiveLocale,
    );
    if (kind == CloudSyncNoticeKind.failure) return detail;
    return '$context${isEn ? ': ' : '：'}$detail';
  }
}
