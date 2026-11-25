import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../core/smart_date_parser.dart';
import '../core/smart_todo_draft.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/diary_deep_review.dart';
import '../models/diary_entry.dart';
import '../models/goal.dart'
    show
        ReminderConfig,
        ReminderKind,
        ReminderPlan,
        ReminderRule,
        ReminderRuleType;
import '../models/todo.dart';
import 'api_client.dart';
import 'account_local_data_cleaner.dart';
import '../core/i18n.dart';
import '../core/weekly_review_summary.dart';
import '../core/weekly_review_generation.dart';

/// AI 客户端：**不再持有任何 key/base_url**，所有调用通过 `/api/ai/chat`
/// 由已登录用户的 token 代理到管理员在服务端配置好的上游。
///
/// `enabled` 状态来自 `/api/config`。
class AiService extends ChangeNotifier {
  ApiClient _client = ApiClient();
  bool _enabled = false;
  String _model = '';
  List<AiReviewEntry> _reviewHistory = [];
  final Set<AiReviewEntry> _pendingOwnedEntries = {};
  int _storageGeneration = 0;
  int _historyRevision = 0;
  bool _historyNeedsPersistence = false;
  bool _disposed = false;
  int _historyAccountGeneration = AccountLocalDataCleaner.accountDataGeneration;
  Future<void> _historyWriteQueue = Future<void>.value();
  Object? _historyWriteFailure;
  StackTrace? _historyWriteFailureStack;

  /// The app closes history access during authentication/cleanup transitions.
  bool Function()? historyAccessAllowed;

  AiService() {
    AccountLocalDataCleaner.accountDataGenerationListenable.addListener(
      _accountHistoryInvalidated,
    );
  }

  bool get _canAccessHistory =>
      !_disposed && (historyAccessAllowed?.call() ?? true);

  void _accountHistoryInvalidated() {
    if (_disposed) return;
    _pendingOwnedEntries.clear();
    _storageGeneration++;
    _historyAccountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    _reviewHistory = [];
    _historyRevision++;
    _historyNeedsPersistence = false;
    notifyListeners();
  }

  _AiHistoryOperation _captureHistoryOperation({
    bool Function()? ownerIsCurrent,
  }) {
    if (!_canAccessHistory) throw const AiReviewDiscardedException();
    return _AiHistoryOperation(
      storage: _storageGeneration,
      account: AccountLocalDataCleaner.accountDataGeneration,
      client: _client,
      token: _client.token,
      baseUrl: _client.baseUrl,
      model: _model,
      ownerIsCurrent: ownerIsCurrent,
    );
  }

  bool _sameHistoryOwner(_AiHistoryOperation operation) =>
      !_disposed &&
      operation.storage == _storageGeneration &&
      operation.account == _historyAccountGeneration &&
      AccountLocalDataCleaner.isCurrentAccountDataGeneration(
        operation.account,
      ) &&
      identical(operation.client, _client) &&
      operation.token == _client.token &&
      operation.baseUrl == _client.baseUrl;

  bool _isHistoryOperationCurrent(_AiHistoryOperation operation) =>
      _canAccessHistory &&
      _sameHistoryOwner(operation) &&
      (operation.ownerIsCurrent?.call() ?? true);

  void _requireHistoryOperation(_AiHistoryOperation operation) {
    if (!_isHistoryOperationCurrent(operation)) {
      throw const AiReviewDiscardedException();
    }
  }

  Future<String> _reviewChat(
    _AiHistoryOperation operation,
    String systemPrompt,
    String userPrompt, {
    double temperature = 0.4,
    int maxTokens = 512,
  }) async {
    _requireHistoryOperation(operation);
    try {
      final result = await _chat(
        systemPrompt,
        userPrompt,
        temperature: temperature,
        maxTokens: maxTokens,
      );
      _requireHistoryOperation(operation);
      return result;
    } catch (_) {
      _requireHistoryOperation(operation);
      rethrow;
    }
  }

  Future<void> _appendReview(
    _AiHistoryOperation operation,
    AiReviewEntry entry,
  ) async {
    _requireHistoryOperation(operation);
    if (operation.ownerIsCurrent != null) _pendingOwnedEntries.add(entry);
    _reviewHistory.insert(0, entry);
    _historyRevision++;
    _historyNeedsPersistence = true;
    _trimReviewHistory();
    try {
      await _saveHistory(operation);
      _requireHistoryOperation(operation);
      notifyListeners();
      _requireHistoryOperation(operation);
    } on AiReviewDiscardedException {
      _pendingOwnedEntries.remove(entry);
      // A page/session cancellation can leave the service itself current.
      // Undo only this provisional row and repair any already-issued write.
      if (operation.ownerIsCurrent != null && _sameHistoryOwner(operation)) {
        final length = _reviewHistory.length;
        _reviewHistory.removeWhere((item) => identical(item, entry));
        if (_reviewHistory.length != length) {
          _trimReviewHistory();
          _historyRevision++;
          _historyNeedsPersistence = true;
          notifyListeners();
          final cleanup = operation.withoutOwner();
          if (_isHistoryOperationCurrent(cleanup)) {
            try {
              await _saveHistory(cleanup);
              if (_isHistoryOperationCurrent(cleanup)) notifyListeners();
            } catch (_) {
              // Keep dirty history and the existing drain failure receipt.
            }
          }
        }
      }
      rethrow;
    } finally {
      _pendingOwnedEntries.remove(entry);
      _trimReviewHistory();
    }
  }

  void _trimReviewHistory() {
    // Retain the tail until owned appends settle so a cancelled 51st row
    // cannot evict a previously saved review. Persist at most 50 rows.
    if (_pendingOwnedEntries.isEmpty && _reviewHistory.length > 50) {
      _reviewHistory = _reviewHistory.sublist(0, 50);
    }
  }

  /// Wait for issued platform writes before account preferences are removed.
  Future<void> drainPendingHistoryWrites() async {
    while (true) {
      final pending = _historyWriteQueue;
      await pending;
      if (identical(pending, _historyWriteQueue)) break;
    }
    final failure = _historyWriteFailure;
    final stack = _historyWriteFailureStack;
    _historyWriteFailure = null;
    _historyWriteFailureStack = null;
    if (failure != null) Error.throwWithStackTrace(failure, stack!);
  }

  @override
  void dispose() {
    _disposed = true;
    _pendingOwnedEntries.clear();
    _storageGeneration++;
    AccountLocalDataCleaner.accountDataGenerationListenable.removeListener(
      _accountHistoryInvalidated,
    );
    super.dispose();
  }

  bool get enabled => _enabled;
  bool get isConfigured => _enabled;
  String get model => _model;

  /// Changes when the owner of local review history is reset.
  int get historyGeneration => _storageGeneration;
  List<AiReviewEntry> get reviewHistory =>
      _canAccessHistory &&
          _historyAccountGeneration ==
              AccountLocalDataCleaner.accountDataGeneration
      ? List.unmodifiable(_reviewHistory)
      : const [];

  static const _kReviewHistory = 'ai_review_history';
  static const weeklyReviewKind = 'weekly_review';

  void attachClient(ApiClient client) {
    if (_disposed) return;
    _client = client;
  }

  void updateFromServerConfig(Map<String, dynamic> cfg) {
    if (_disposed) return;
    _enabled = cfg['ai_enabled'] == true;
    _model = (cfg['ai_model'] ?? '').toString();
    notifyListeners();
  }

  Future<void> loadFromStorage() async {
    if (!_canAccessHistory) return;
    final operation = _captureHistoryOperation();
    final revision = _historyRevision;
    await _historyWriteQueue;
    if (!_isHistoryOperationCurrent(operation) ||
        revision != _historyRevision ||
        _historyNeedsPersistence) {
      return;
    }
    final p = await SharedPreferences.getInstance();
    if (!_isHistoryOperationCurrent(operation) ||
        revision != _historyRevision ||
        _historyNeedsPersistence) {
      return;
    }
    // Legacy preferences setters update their cache even when writing fails.
    await p.reload();
    if (!_isHistoryOperationCurrent(operation) ||
        revision != _historyRevision ||
        _historyNeedsPersistence) {
      return;
    }
    final raw = p.getStringList(_kReviewHistory) ?? [];
    _reviewHistory = raw
        .map((e) {
          try {
            return AiReviewEntry.fromJson(jsonDecode(e));
          } catch (_) {
            return null;
          }
        })
        .whereType<AiReviewEntry>()
        .toList();
    _historyRevision++;
    notifyListeners();
  }

  void resetLocalState() {
    if (_disposed) return;
    _pendingOwnedEntries.clear();
    _historyAccountGeneration = AccountLocalDataCleaner.accountDataGeneration;
    _storageGeneration++;
    _reviewHistory = [];
    _historyRevision++;
    _historyNeedsPersistence = false;
    notifyListeners();
  }

  Future<void> _saveHistory(_AiHistoryOperation operation) async {
    _requireHistoryOperation(operation);
    final revision = _historyRevision;
    final snapshot = List<String>.unmodifiable(
      _reviewHistory.take(50).map((entry) => jsonEncode(entry.toJson())),
    );
    final write = _historyWriteQueue.then((_) async {
      _requireHistoryOperation(operation);
      final prefs = await SharedPreferences.getInstance();
      _requireHistoryOperation(operation);
      try {
        final written = await prefs.setStringList(_kReviewHistory, snapshot);
        if (!written) {
          throw const AiReviewHistoryWriteException();
        }
      } catch (error, stack) {
        _historyWriteFailure = error;
        _historyWriteFailureStack = stack;
        rethrow;
      }
      _requireHistoryOperation(operation);
      if (revision == _historyRevision) _historyNeedsPersistence = false;
    });
    _historyWriteQueue = write.catchError((Object error, StackTrace stack) {
      if (error is! AiReviewDiscardedException) {
        debugPrint('[AiService] history write failed: $error\n$stack');
      }
    });
    try {
      await write;
      _requireHistoryOperation(operation);
    } catch (_) {
      _requireHistoryOperation(operation);
      rethrow;
    }
  }

  Future<void> deleteReview(String id) async {
    final operation = _captureHistoryOperation();
    _reviewHistory.removeWhere((entry) => entry.id == id);
    _historyRevision++;
    _historyNeedsPersistence = true;
    notifyListeners();
    await _saveHistory(operation);
  }

  Future<void> clearReviewHistory() async {
    final operation = _captureHistoryOperation();
    _reviewHistory.clear();
    _historyRevision++;
    _historyNeedsPersistence = true;
    notifyListeners();
    await _saveHistory(operation);
  }

  Future<String> _chat(
    String systemPrompt,
    String userPrompt, {
    double temperature = 0.4,
    int maxTokens = 512,
  }) async {
    if (!_enabled) throw const AiException('AI 功能未启用，请联系管理员');
    try {
      final res = await _client.post('/api/ai/chat', {
        'system': systemPrompt,
        'user': userPrompt,
        'temperature': temperature,
        'max_tokens': maxTokens,
      }, const Duration(seconds: 75));
      final content = (res['content'] ?? '').toString();
      return content;
    } on ApiException catch (e) {
      throw AiException(_friendlyAiError(e.message));
    }
  }

  Future<AiScheduleDraft> createScheduleDraft(
    String input, {
    DateTime? now,
  }) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const AiException('请输入要创建的日程或待办内容');
    }
    final _AiHistoryOperation operation;
    try {
      operation = _captureHistoryOperation();
    } on AiReviewDiscardedException {
      throw const AiScheduleDiscardedException();
    }
    final localNow = now ?? DateTime.now();
    final baseDraft = _fallbackScheduleDraft(trimmed, now: localNow);
    if (!_enabled) return baseDraft.withSource(AiScheduleSource.localParser);

    final prompt = [
      '当前本地时间：${localNow.toIso8601String()}',
      '用户输入：$trimmed',
      '',
      '请识别用户想创建的是 calendar（日程）还是 todo（待办）。',
      '只返回 JSON，不要 Markdown。字段：',
      '{"type":"calendar|todo","title":"标题","start_at":"ISO8601 或空",'
          '"end_at":"ISO8601 或空","all_day":false,"reminder":true,'
          '"notes":"补充说明","subtasks":["子任务"]}',
      '规则：有明确开始时间/会议/日程/安排，优先 calendar；只表达要完成的任务，优先 todo。',
      '没有结束时间时，calendar 默认 60 分钟；todo 没有时间也可以创建。',
    ].join('\n');
    try {
      final raw = await _reviewChat(
        operation,
        '你是多仪的日程创建助手。你必须把自然语言转成可确认的结构化草稿。'
        '不要编造用户没有提到的地点、人名或重复规则。输出必须是严格 JSON。',
        prompt,
        temperature: 0.1,
        maxTokens: 420,
      );
      final parsed = _parseScheduleDraft(raw, trimmed, localNow);
      return parsed ??
          baseDraft.withSource(
            AiScheduleSource.aiWithLocalFallback,
            warningKind: AiScheduleWarningKind.noUsableDraft,
            warning: 'AI 没有返回可用草稿，已用本地时间解析生成草稿。',
          );
    } on AiReviewDiscardedException {
      throw const AiScheduleDiscardedException();
    } on AiException catch (e) {
      return baseDraft.withSource(
        AiScheduleSource.localParser,
        warningKind: AiScheduleWarningKind.unavailable,
        warning: 'AI 识别失败，已用本地时间解析生成草稿：${e.message}',
      );
    } catch (e) {
      return baseDraft.withSource(
        AiScheduleSource.aiWithLocalFallback,
        warningKind: AiScheduleWarningKind.invalidResponse,
        warning: 'AI 返回内容无法解析，已用本地时间解析生成草稿：$e',
      );
    }
  }

  Future<List<String>> breakDownTask(String goal) async {
    final out = await _chat(
      '你是一个高效任务分解助手，将用户的目标拆成 3 到 7 条具体可执行的子任务。'
      '只输出子任务，每条一行，不要编号、解释、客套话。',
      goal,
      temperature: 0.3,
    );
    return out
        .split(RegExp(r'\r?\n'))
        .map(
          (line) =>
              line.trim().replaceFirst(RegExp(r'^[\-\*\d\.\s]+'), '').trim(),
        )
        .where((line) => line.isNotEmpty)
        .toList();
  }

  Future<String> testConnection() {
    return _chat(
      '你是多仪的 AI 连通性测试助手。只回复 ok。',
      '请回复 ok，用于验证 /api/ai/chat 代理链路可用。',
      temperature: 0,
      maxTokens: 16,
    );
  }

  Future<String> weeklyReview({
    required int completedTodos,
    required int totalTodos,
    required int weeklyFocusMinutes,
    required int habitStreak,
    String? periodLabel,
    WeeklyReviewPeriod? period,
    AppLocale? locale,
    bool Function()? ownerIsCurrent,
    DateTime? now,
  }) async {
    final operation = _captureHistoryOperation(ownerIsCurrent: ownerIsCurrent);
    _requireHistoryOperation(operation);
    final generationLocale = locale ?? I18n.current;
    final createdAt = now ?? DateTime.now();
    final cached = _findWeeklyReviewForDay(createdAt);
    if (cached != null) {
      if (_historyNeedsPersistence) await _saveHistory(operation);
      _requireHistoryOperation(operation);
      return cached.content;
    }
    final stats = WeeklyReviewStats(
      completedTodos: completedTodos,
      totalTodos: totalTodos,
      focusMinutes: weeklyFocusMinutes,
      habitStreak: habitStreak,
      period:
          period ??
          (periodLabel == null
              ? WeeklyReviewPeriod.thisWeek
              : WeeklyReviewPeriod.custom),
      customPeriodLabel: periodLabel ?? '',
    );
    final generation = WeeklyReviewGeneration(
      stats: stats,
      isEnglish: generationLocale == AppLocale.en,
    );
    final summary = stats.format(isEnglish: generation.isEnglish);
    final out = await _reviewChat(
      operation,
      generation.systemPrompt,
      generation.userPrompt,
      temperature: 0.45,
      maxTokens: 400,
    );
    final review = generation.normalize(out);
    final entry = AiReviewEntry(
      id: createdAt.millisecondsSinceEpoch.toString(),
      createdAt: createdAt,
      content: review,
      summary: summary,
      model: operation.model,
      kind: weeklyReviewKind,
      weeklyStats: stats,
    );
    await _appendReview(operation, entry);
    _requireHistoryOperation(operation);
    return review;
  }

  /// 基于 ReportEngine 的 PeriodReport 生成自然语言周/月/年报。
  Future<String> reviewFromReport({
    required int completedTodos,
    required int totalTodos,
    required int focusMinutes,
    required int habitStreak,
    required int habitCheckIns,
    required int timeEntryMinutes,
    required String periodLabel,
    AppLocale? locale,
  }) async {
    final generationLocale = locale ?? I18n.current;
    final summary = generationLocale == AppLocale.en
        ? '$periodLabel summary: tasks done $completedTodos / $totalTodos, '
              'focus $focusMinutes min, habit check-ins $habitCheckIns '
              '(longest streak $habitStreak days), time logged $timeEntryMinutes min.'
        : '$periodLabel数据：完成 $completedTodos / $totalTodos 项待办，'
              '专注 $focusMinutes 分钟，习惯打卡 $habitCheckIns 次（最长连续 $habitStreak 天），'
              '记录时间 $timeEntryMinutes 分钟。';
    return _runReview(summary, periodLabel, locale: generationLocale);
  }

  Future<String> personalizedReportReview({
    required String periodLabel,
    required String reportMarkdown,
    AppLocale? locale,
  }) async {
    final isEnglish = (locale ?? I18n.current) == AppLocale.en;
    final operation = _captureHistoryOperation();
    final out = await _reviewChat(
      operation,
      isEnglish
          ? 'You are Duoyi’s productivity report analyst. Write a structured personalized review in English based on the user’s period report. '
                'Start with one overall assessment; identify what to retain and adjust in tasks, focus, habits and time logs; '
                'suggest three practical actions for the next seven days. Avoid generic encouragement and repeating raw data.'
          : '你是多仪的云端效率报告分析师。基于用户的周期统计报告，输出一段结构化中文个性化解读。'
                '要求：1) 先给一句总判断；2) 分析待办、专注、习惯、时间足迹中最值得保留和最需要调整的点；'
                '3) 给出未来 7 天 3 条可执行动作；4) 不要泛泛鼓励，不要重复原始数据堆砌。',
      '${isEnglish ? 'Period' : '周期'}：$periodLabel\n\n$reportMarkdown',
      temperature: 0.5,
      maxTokens: 900,
    );
    final entry = AiReviewEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      createdAt: DateTime.now(),
      content: out,
      summary: isEnglish
          ? 'Report AI review: $periodLabel'
          : '统计报告 AI 解读：$periodLabel',
      model: operation.model,
    );
    await _appendReview(operation, entry);
    _requireHistoryOperation(operation);
    return out;
  }

  Future<String> deepDiaryReview({
    required Iterable<DiaryEntry> entries,
    DateTime? today,
    AppLocale? locale,
  }) async {
    final generationLocale = locale ?? I18n.current;
    final operation = _captureHistoryOperation();
    final prompt = DiaryDeepReviewBuilder.build(
      entries: entries,
      today: today,
      locale: generationLocale,
    );
    final out = await _reviewChat(
      operation,
      prompt.systemPrompt,
      prompt.userPrompt,
      temperature: 0.55,
      maxTokens: 900,
    );
    final entry = AiReviewEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      createdAt: DateTime.now(),
      content: out,
      summary: generationLocale == AppLocale.en
          ? 'Diary deep review: ${prompt.summary}'
          : '日记深度复盘：${prompt.summary}',
      model: operation.model,
    );
    await _appendReview(operation, entry);
    _requireHistoryOperation(operation);
    return out;
  }

  AiReviewEntry? weeklyReviewForDay(DateTime day) {
    if (!_canAccessHistory ||
        _historyNeedsPersistence ||
        _historyAccountGeneration !=
            AccountLocalDataCleaner.accountDataGeneration) {
      return null;
    }
    return _findWeeklyReviewForDay(day);
  }

  AiReviewEntry? _findWeeklyReviewForDay(DateTime day) {
    for (final entry in _reviewHistory) {
      if (_looksLikeWeeklyReview(entry) && _sameDay(entry.createdAt, day)) {
        return entry;
      }
    }
    return null;
  }

  Future<String> _runReview(
    String summary,
    String periodLabel, {
    required AppLocale locale,
    String kind = '',
    DateTime? createdAt,
  }) async {
    final operation = _captureHistoryOperation();
    final out = await _reviewChat(
      operation,
      locale == AppLocale.en
          ? 'You are a kind and practical productivity coach. Based on the supplied $periodLabel facts, '
                'write a concise review in English (about 60–100 words). Start with "$periodLabel review:". '
                'Recognize one or two useful practices, then suggest one or two practical actions for next week. '
                'Do not invent facts or use Markdown, tables, emoji, bold or separators.'
          : '你是一个温柔且实用的效率教练。基于$periodLabel完成情况写一段 80-150 字的中文回顾，'
                '开头必须明确写“$periodLabel回顾：”。语气积极不空洞，先肯定 1-2 点亮点，'
                '再提 1-2 个具体可执行的下周建议。不要使用 Markdown、表格、emoji、加粗或分隔线。',
      summary,
      temperature: 0.6,
      maxTokens: 400,
    );
    final entryTime = createdAt ?? DateTime.now();
    final entry = AiReviewEntry(
      id: entryTime.millisecondsSinceEpoch.toString(),
      createdAt: entryTime,
      content: out,
      summary: summary,
      model: operation.model,
      kind: kind,
    );
    await _appendReview(operation, entry);
    _requireHistoryOperation(operation);
    return out;
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _looksLikeWeeklyReview(AiReviewEntry entry) {
    if (entry.kind == weeklyReviewKind) return true;
    return RegExp(r'^(本周|上周)数据：').hasMatch(entry.summary);
  }
}

enum AiScheduleType { calendar, todo }

enum AiScheduleSource { ai, aiWithLocalFallback, localParser }

/// Stable fallback reasons for localized presentation without raw diagnostics.
enum AiScheduleWarningKind {
  unavailable,
  noUsableDraft,
  invalidResponse,
  missingReminderTime,
}

class AiScheduleDraft {
  final AiScheduleType type;
  final String title;
  final DateTime startAt;
  final DateTime? endAt;
  final bool allDay;
  final bool reminderEnabled;
  final String notes;
  final List<String> subtasks;
  final AiScheduleSource source;
  final String? warning;
  final AiScheduleWarningKind? warningKind;

  const AiScheduleDraft({
    required this.type,
    required this.title,
    required this.startAt,
    this.endAt,
    this.allDay = false,
    this.reminderEnabled = false,
    this.notes = '',
    this.subtasks = const <String>[],
    this.source = AiScheduleSource.ai,
    this.warning,
    this.warningKind,
  });

  bool get isCalendar => type == AiScheduleType.calendar;
  bool get hasTime => !allDay;

  AiScheduleDraft withSource(
    AiScheduleSource next, {
    String? warning,
    AiScheduleWarningKind? warningKind,
  }) {
    return AiScheduleDraft(
      type: type,
      title: title,
      startAt: startAt,
      endAt: endAt,
      allDay: allDay,
      reminderEnabled: reminderEnabled,
      notes: notes,
      subtasks: subtasks,
      source: next,
      warning: warning ?? this.warning,
      warningKind: warningKind ?? this.warningKind,
    );
  }

  TodoItem toTodo() {
    final dueDate = allDay ? null : startAt;
    final reminder = reminderEnabled
        ? ReminderConfig(
            enabled: true,
            kind: ReminderKind.push,
            hour: startAt.hour,
            minute: startAt.minute,
            vibrate: true,
          )
        : const ReminderConfig.disabled();
    final plan = reminderEnabled
        ? ReminderPlan(
            enabled: true,
            rules: [
              ReminderRule(
                id: 'ai-schedule-${startAt.millisecondsSinceEpoch}',
                enabled: true,
                type: ReminderRuleType.absolute,
                kind: ReminderKind.push,
                hour: startAt.hour,
                minute: startAt.minute,
                vibrate: true,
              ),
            ],
          )
        : const ReminderPlan.disabled();
    return TodoItem(
      title: title,
      notes: notes,
      date: startAt,
      dueDate: dueDate,
      hasReminder: reminderEnabled,
      reminderAt: reminderEnabled ? startAt : null,
      reminder: reminder,
      reminderPlan: plan,
      subtasks: subtasks.map((title) => Subtask(title: title)).toList(),
    );
  }
}

AiScheduleDraft _fallbackScheduleDraft(String input, {DateTime? now}) {
  final localNow = now ?? DateTime.now();
  final draft = SmartTodoDraftBuilder.fromText(input, now: localNow);
  final parsed = SmartDateParser.parse(input, now: localNow);
  final hasExplicitTime = parsed.isSuccess && parsed.hasTimeOfDay;
  final type = _inferScheduleType(input, hasExplicitTime: hasExplicitTime);
  final title = _cleanScheduleTitle(
    draft.title.trim().isEmpty ? input.trim() : draft.title.trim(),
    input,
  );
  final startAt = parsed.isSuccess
      ? draft.date
      : DateTime(localNow.year, localNow.month, localNow.day);
  final reminder = draft.hasReminder && !_hasNoReminderIntent(input);
  return AiScheduleDraft(
    type: type,
    title: title,
    startAt: startAt,
    endAt: type == AiScheduleType.calendar && hasExplicitTime
        ? startAt.add(const Duration(hours: 1))
        : null,
    allDay: !hasExplicitTime,
    reminderEnabled: reminder,
    notes: input,
    source: AiScheduleSource.localParser,
  );
}

AiScheduleDraft? _parseScheduleDraft(
  String raw,
  String original,
  DateTime now,
) {
  final jsonText = _extractJsonObject(raw);
  if (jsonText == null) return null;
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map) return null;
  final fallback = _fallbackScheduleDraft(original, now: now);
  final data = _scheduleDataFromJson(Map<String, dynamic>.from(decoded));
  final rawTitle = _firstString(data, const [
    'title',
    'name',
    'summary',
    'content',
    '标题',
    '主题',
    '内容',
  ]);
  final title = _cleanScheduleTitle(
    rawTitle.isEmpty ? fallback.title : rawTitle,
    original,
  );
  if (title.isEmpty) return null;

  final parsedStart = _parseScheduleTime(
    _firstValue(data, const [
      'start_at',
      'startAt',
      'start',
      'date',
      'time',
      'due_at',
      'dueAt',
      'reminder_at',
      'reminderAt',
      '开始时间',
      '开始',
      '时间',
      '日期',
    ]),
    now,
  );
  final parsedEnd = _parseScheduleTime(
    _firstValue(data, const ['end_at', 'endAt', 'end', '结束时间', '结束']),
    now,
  );
  final start = parsedStart?.dateTime ?? fallback.startAt;
  final hasTime = parsedStart?.hasTimeOfDay ?? fallback.hasTime;
  final type = _typeFromAiData(data, original, hasExplicitTime: hasTime);
  var end = parsedEnd?.dateTime;
  if (end != null && !end.isAfter(start)) {
    end = null;
  }
  if (type == AiScheduleType.calendar && end == null && hasTime) {
    end = start.add(const Duration(hours: 1));
  }
  final allDay =
      _parseBoolValue(
        _firstValue(data, const ['all_day', 'allDay', '全天', '是否全天']),
      ) ??
      !hasTime;
  final reminderRequested =
      _parseBoolValue(
        _firstValue(data, const [
          'reminder',
          'has_reminder',
          'reminder_enabled',
          'reminderEnabled',
          '提醒',
          '是否提醒',
        ]),
      ) ??
      fallback.reminderEnabled;
  final reminder =
      reminderRequested && hasTime && !_hasNoReminderIntent(original);
  final warning = reminderRequested && !hasTime ? '未识别到具体提醒时间，提醒已关闭。' : null;
  final subtasks = _parseSubtasks(
    _firstValue(data, const ['subtasks', 'tasks', 'checklist', '子任务', '清单']),
  );
  return AiScheduleDraft(
    type: type,
    title: title,
    startAt: start,
    endAt: end,
    allDay: allDay,
    reminderEnabled: reminder,
    notes: _firstString(data, const [
      'notes',
      'note',
      'description',
      '备注',
      '说明',
    ]),
    subtasks: subtasks,
    warning: warning,
    warningKind: warning == null
        ? null
        : AiScheduleWarningKind.missingReminderTime,
  );
}

String? _extractJsonObject(String raw) {
  var text = raw.trim();
  final fence = RegExp(
    r'```(?:json)?\s*([\s\S]*?)```',
    caseSensitive: false,
  ).firstMatch(text);
  if (fence != null) {
    text = fence.group(1)!.trim();
  }
  var depth = 0;
  var start = -1;
  var inString = false;
  var escaping = false;
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (inString) {
      if (escaping) {
        escaping = false;
      } else if (char == '\\') {
        escaping = true;
      } else if (char == '"') {
        inString = false;
      }
      continue;
    }
    if (char == '"') {
      inString = true;
      continue;
    }
    if (char == '{') {
      if (depth == 0) start = i;
      depth++;
    } else if (char == '}') {
      if (depth == 0) continue;
      depth--;
      if (depth == 0 && start >= 0) return text.substring(start, i + 1);
    }
  }
  return null;
}

Map<String, dynamic> _scheduleDataFromJson(Map<String, dynamic> data) {
  for (final key in const [
    'draft',
    'schedule',
    'event',
    'todo',
    'task',
    'data',
    'result',
  ]) {
    final nested = data[key];
    if (nested is Map) {
      final next = Map<String, dynamic>.from(nested);
      if (!next.containsKey('type') && data['type'] != null) {
        next['type'] = data['type'];
      }
      return next;
    }
  }
  return data;
}

Object? _firstValue(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    if (data.containsKey(key)) return data[key];
  }
  return null;
}

String _firstString(Map<String, dynamic> data, List<String> keys) {
  final value = _firstValue(data, keys);
  if (value == null) return '';
  final text = value.toString().trim();
  if (_isBlankAiValue(text)) return '';
  return text;
}

bool _isBlankAiValue(String text) {
  final normalized = text.trim().toLowerCase();
  return normalized.isEmpty ||
      normalized == 'null' ||
      normalized == 'none' ||
      normalized == 'n/a' ||
      normalized == '[]' ||
      normalized == '无' ||
      normalized == '空';
}

AiScheduleType _typeFromAiData(
  Map<String, dynamic> data,
  String original, {
  required bool hasExplicitTime,
}) {
  final raw = _firstString(data, const ['type', 'kind', '类别', '类型']);
  final typeText = raw.toLowerCase();
  if (RegExp(r'(calendar|event|schedule|日程|会议|活动|行程|课程)').hasMatch(typeText)) {
    return AiScheduleType.calendar;
  }
  if (RegExp(r'(todo|task|reminder|待办|任务|提醒)').hasMatch(typeText)) {
    return AiScheduleType.todo;
  }
  return _inferScheduleType(original, hasExplicitTime: hasExplicitTime);
}

AiScheduleType _inferScheduleType(
  String input, {
  required bool hasExplicitTime,
}) {
  final text = input.trim();
  final looksCalendar = RegExp(
    r'(日程|会议|开会|会面|安排|约|预约|行程|面试|上课|课程|课|活动|团建|体检|复诊|看诊|拜访|出差|航班|火车|电影|演出|calendar|meeting|appointment|event|class|interview|flight)',
    caseSensitive: false,
  ).hasMatch(text);
  if (looksCalendar) return AiScheduleType.calendar;
  final looksTodo = RegExp(
    r'(待办|任务|提醒我|记得|完成|提交|购买|买|写|整理|处理|缴|交|打卡|复习|学习|阅读|看书|发送|发给|寄|取|拿|还|做|todo|task|remind)',
    caseSensitive: false,
  ).hasMatch(text);
  if (looksTodo) return AiScheduleType.todo;
  return hasExplicitTime ? AiScheduleType.calendar : AiScheduleType.todo;
}

bool _hasNoReminderIntent(String input) {
  return RegExp(
    r'(不提醒|不用提醒|无需提醒|不要提醒|无提醒|no reminder)',
    caseSensitive: false,
  ).hasMatch(input);
}

String _cleanScheduleTitle(String value, String original) {
  var title = value.trim();
  if (title.isEmpty) title = original.trim();
  title = title.replaceAll(RegExp(r'\s+'), ' ');
  title = title.replaceFirst(RegExp(r'^[，,。；;\s]+'), '');
  title = title.replaceFirst(RegExp(r'^(请|麻烦|帮我|请帮我|给我|为我|我要|我想|我需要)\s*'), '');
  title = title.replaceFirst(
    RegExp(r'^(创建|新建|添加|安排|设置|设|加)(一个|一条)?(日程|待办|任务|提醒)?\s*'),
    '',
  );
  title = title.replaceFirst(
    RegExp(r'^(和|跟|与)(?=[\u4e00-\u9fa5A-Za-z0-9])'),
    '',
  );
  title = title.replaceAll(
    RegExp(r'(提前\s*\d*\s*(分钟|小时)?\s*提醒我|提前提醒我|到时候提醒我|记得提醒我|提醒我|记得)$'),
    '',
  );
  title = title.replaceAll(RegExp(r'[，,。；;\s]+$'), '').trim();
  return title.isEmpty ? original.trim() : title;
}

_ParsedScheduleTime? _parseScheduleTime(Object? value, DateTime now) {
  if (value == null) return null;
  if (value is num) {
    final millis = value > 1000000000000 ? value.toInt() : value.toInt() * 1000;
    return _ParsedScheduleTime(
      DateTime.fromMillisecondsSinceEpoch(millis).toLocal(),
      hasTimeOfDay: true,
    );
  }
  final text = value.toString().trim();
  if (_isBlankAiValue(text)) return null;
  final normalized = text.replaceAll('/', '-').replaceFirst(' ', 'T');
  final iso = DateTime.tryParse(normalized) ?? DateTime.tryParse(text);
  if (iso != null) {
    return _ParsedScheduleTime(
      iso.toLocal(),
      hasTimeOfDay:
          RegExp(r'(T|\s)\d{1,2}[:：]\d{1,2}').hasMatch(text) ||
          RegExp(r'\d{1,2}[:：]\d{1,2}').hasMatch(text),
    );
  }
  final parsed = SmartDateParser.parse(text, now: now);
  if (!parsed.isSuccess) return null;
  return _ParsedScheduleTime(
    parsed.dateTime!,
    hasTimeOfDay: parsed.hasTimeOfDay,
  );
}

bool? _parseBoolValue(Object? value) {
  if (value == null) return null;
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value.toString().trim().toLowerCase();
  if (_isBlankAiValue(text)) return null;
  if (const {
    'true',
    'yes',
    'y',
    '1',
    '是',
    '需要',
    '开启',
    '开',
    '有',
  }.contains(text)) {
    return true;
  }
  if (const {
    'false',
    'no',
    'n',
    '0',
    '否',
    '不需要',
    '关闭',
    '关',
    '无',
  }.contains(text)) {
    return false;
  }
  return null;
}

List<String> _parseSubtasks(Object? value) {
  final rawItems = <Object?>[];
  if (value is List) {
    rawItems.addAll(value);
  } else if (value is String && !_isBlankAiValue(value)) {
    rawItems.addAll(value.split(RegExp(r'[\n；;]+')));
  }
  return rawItems
      .map((item) => item.toString().trim())
      .map((item) => item.replaceFirst(RegExp(r'^[\-\*\d\.\s]+'), '').trim())
      .where((item) => item.isNotEmpty)
      .take(8)
      .toList(growable: false);
}

class _ParsedScheduleTime {
  final DateTime dateTime;
  final bool hasTimeOfDay;

  const _ParsedScheduleTime(this.dateTime, {required this.hasTimeOfDay});
}

String _friendlyAiError(String raw) {
  final text = raw.trim();
  final lower = text.toLowerCase();
  if (text.isEmpty) return 'AI 服务没有返回有效内容';
  if (text.contains('AI 功能未启用')) return 'AI 功能未启用，请先在管理后台开启';
  if (text.contains('API Key')) return '管理员尚未配置 AI API Key';
  if (text.contains('额度') || text.contains('429')) return '今日 AI 额度已用尽';
  if (text.contains('超时')) return 'AI 服务响应超时，请稍后重试';
  if (text.contains('404') || lower.contains('not found')) {
    return 'AI 代理或上游模型不可用，请检查后端 /api/ai/chat、Base URL 和模型名称';
  }
  if (text.contains('503')) return 'AI 服务暂不可用，请检查管理后台配置';
  if (text.contains('上游不可达') || text.contains('502')) {
    return 'AI 上游服务不可达，请检查 Base URL、网络或模型配置';
  }
  if (text.contains('401') || text.contains('403')) return 'AI 密钥无效或没有模型权限';
  return text;
}

/// 持久化的 AI 周报条目。
class AiReviewEntry {
  final String id;
  final DateTime createdAt;
  final String content;
  final String summary;
  final String model;
  final String kind;
  final WeeklyReviewStats? weeklyStats;

  const AiReviewEntry({
    required this.id,
    required this.createdAt,
    required this.content,
    required this.summary,
    this.model = '',
    this.kind = '',
    this.weeklyStats,
  });

  String get displaySummary {
    if (kind.isNotEmpty && kind != AiService.weeklyReviewKind) return summary;
    final stats = weeklyStats ?? WeeklyReviewStats.fromLegacy(summary);
    return stats?.format(isEnglish: I18n.current == AppLocale.en) ?? summary;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'content': content,
    'summary': summary,
    'model': model,
    'kind': kind,
    if (weeklyStats != null) 'weeklyStats': weeklyStats!.toJson(),
  };

  factory AiReviewEntry.fromJson(Map<String, dynamic> j) => AiReviewEntry(
    id: j['id'].toString(),
    createdAt: DateTime.parse(j['createdAt']),
    content: (j['content'] ?? '').toString(),
    summary: (j['summary'] ?? '').toString(),
    model: (j['model'] ?? '').toString(),
    kind: (j['kind'] ?? '').toString(),
    weeklyStats: WeeklyReviewStats.fromJson(j['weeklyStats']),
  );
}

class AiException implements Exception {
  final String message;
  const AiException(this.message);
  @override
  String toString() => message;
}

/// Stable cancellation signal; callers should discard it without showing an error.
class AiReviewDiscardedException extends AiException {
  const AiReviewDiscardedException() : super('AI review request was canceled.');

  static const code = 'review_discarded';

  @override
  String get message => I18n.current == AppLocale.zh
      ? '账号或本地数据已变化，本次 AI 回顾已取消。'
      : 'The account or local data changed. This AI review was canceled.';
}

/// Schedule results and local fallbacks belong to the requesting account.
class AiScheduleDiscardedException extends AiException {
  const AiScheduleDiscardedException()
    : super('AI schedule request was canceled.');

  static const code = 'schedule_discarded';

  @override
  String get message => I18n.current == AppLocale.zh
      ? '账号或本地数据已变化，本次日程识别已取消。'
      : 'The account or local data changed. This schedule request was canceled.';
}

class AiReviewHistoryWriteException extends AiException {
  const AiReviewHistoryWriteException()
    : super('AI review history could not be saved.');

  static const code = 'review_history_write_failed';

  @override
  String get message => I18n.current == AppLocale.zh
      ? 'AI 回顾历史未能保存，请重试。'
      : 'AI review history could not be saved. Try again.';
}

final class _AiHistoryOperation {
  const _AiHistoryOperation({
    required this.storage,
    required this.account,
    required this.client,
    required this.token,
    required this.baseUrl,
    required this.model,
    this.ownerIsCurrent,
  });
  final int storage;
  final int account;
  final ApiClient client;
  final String? token;
  final String baseUrl;
  final String model;
  final bool Function()? ownerIsCurrent;

  _AiHistoryOperation withoutOwner() => _AiHistoryOperation(
    storage: storage,
    account: account,
    client: client,
    token: token,
    baseUrl: baseUrl,
    model: model,
  );
}
