import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/diary_deep_review.dart';
import '../models/diary_entry.dart';
import 'api_client.dart';

/// AI 客户端：**不再持有任何 key/base_url**，所有调用通过 `/api/ai/chat`
/// 由已登录用户的 token 代理到管理员在服务端配置好的上游。
///
/// `enabled` 状态来自 `/api/config`。
class AiService extends ChangeNotifier {
  ApiClient _client = ApiClient();
  bool _enabled = false;
  String _model = '';
  List<AiReviewEntry> _reviewHistory = [];

  bool get enabled => _enabled;
  bool get isConfigured => _enabled;
  String get model => _model;
  List<AiReviewEntry> get reviewHistory => List.unmodifiable(_reviewHistory);

  static const _kReviewHistory = 'ai_review_history';
  static const weeklyReviewKind = 'weekly_review';

  void attachClient(ApiClient client) {
    _client = client;
  }

  void updateFromServerConfig(Map<String, dynamic> cfg) {
    _enabled = cfg['ai_enabled'] == true;
    _model = (cfg['ai_model'] ?? '').toString();
    notifyListeners();
  }

  Future<void> loadFromStorage() async {
    final p = await SharedPreferences.getInstance();
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
    notifyListeners();
  }

  Future<void> _saveHistory() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(
      _kReviewHistory,
      _reviewHistory.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  Future<void> deleteReview(String id) async {
    _reviewHistory.removeWhere((e) => e.id == id);
    notifyListeners();
    await _saveHistory();
  }

  Future<void> clearReviewHistory() async {
    _reviewHistory.clear();
    notifyListeners();
    await _saveHistory();
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
      throw AiException(e.message);
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

  Future<String> weeklyReview({
    required int completedTodos,
    required int totalTodos,
    required int weeklyFocusMinutes,
    required int habitStreak,
    String periodLabel = '本周',
  }) async {
    final summary =
        '$periodLabel数据：完成 $completedTodos / $totalTodos 项待办，专注 $weeklyFocusMinutes 分钟，习惯连续打卡 $habitStreak 天。';
    return _runReview(summary, periodLabel, kind: weeklyReviewKind);
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
  }) async {
    final summary =
        '$periodLabel数据：完成 $completedTodos / $totalTodos 项待办，'
        '专注 $focusMinutes 分钟，习惯打卡 $habitCheckIns 次（最长连续 $habitStreak 天），'
        '记录时间 $timeEntryMinutes 分钟。';
    return _runReview(summary, periodLabel);
  }

  Future<String> personalizedReportReview({
    required String periodLabel,
    required String reportMarkdown,
  }) async {
    final out = await _chat(
      '你是多仪的云端效率报告分析师。基于用户的周期统计报告，输出一段结构化中文个性化解读。'
          '要求：1) 先给一句总判断；2) 分析待办、专注、习惯、时间足迹中最值得保留和最需要调整的点；'
          '3) 给出未来 7 天 3 条可执行动作；4) 不要泛泛鼓励，不要重复原始数据堆砌。',
      '周期：$periodLabel\n\n$reportMarkdown',
      temperature: 0.5,
      maxTokens: 900,
    );
    final entry = AiReviewEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      createdAt: DateTime.now(),
      content: out,
      summary: '统计报告 AI 解读：$periodLabel',
      model: _model,
    );
    _reviewHistory.insert(0, entry);
    if (_reviewHistory.length > 50) {
      _reviewHistory = _reviewHistory.sublist(0, 50);
    }
    await _saveHistory();
    notifyListeners();
    return out;
  }

  Future<String> deepDiaryReview({
    required Iterable<DiaryEntry> entries,
    DateTime? today,
  }) async {
    final prompt = DiaryDeepReviewBuilder.build(entries: entries, today: today);
    final out = await _chat(
      prompt.systemPrompt,
      prompt.userPrompt,
      temperature: 0.55,
      maxTokens: 900,
    );
    final entry = AiReviewEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      createdAt: DateTime.now(),
      content: out,
      summary: '日记深度复盘：${prompt.summary}',
      model: _model,
    );
    _reviewHistory.insert(0, entry);
    if (_reviewHistory.length > 50) {
      _reviewHistory = _reviewHistory.sublist(0, 50);
    }
    await _saveHistory();
    notifyListeners();
    return out;
  }

  AiReviewEntry? weeklyReviewForDay(DateTime day) {
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
    String kind = '',
  }) async {
    final out = await _chat(
      '你是一个温柔且实用的效率教练。基于$periodLabel完成情况写一段 80-150 字的中文回顾，'
      '语气积极不空洞，先肯定 1-2 点亮点，再提 1-2 个具体可执行的下周建议。',
      summary,
      temperature: 0.6,
      maxTokens: 400,
    );
    final entry = AiReviewEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      createdAt: DateTime.now(),
      content: out,
      summary: summary,
      model: _model,
      kind: kind,
    );
    _reviewHistory.insert(0, entry);
    if (_reviewHistory.length > 50) {
      _reviewHistory = _reviewHistory.sublist(0, 50);
    }
    await _saveHistory();
    notifyListeners();
    return out;
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _looksLikeWeeklyReview(AiReviewEntry entry) {
    if (entry.kind == weeklyReviewKind) return true;
    return RegExp(r'^(本周|上周)数据：').hasMatch(entry.summary);
  }
}

/// 持久化的 AI 周报条目。
class AiReviewEntry {
  final String id;
  final DateTime createdAt;
  final String content;
  final String summary;
  final String model;
  final String kind;

  const AiReviewEntry({
    required this.id,
    required this.createdAt,
    required this.content,
    required this.summary,
    this.model = '',
    this.kind = '',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'content': content,
    'summary': summary,
    'model': model,
    'kind': kind,
  };

  factory AiReviewEntry.fromJson(Map<String, dynamic> j) => AiReviewEntry(
    id: j['id'].toString(),
    createdAt: DateTime.parse(j['createdAt']),
    content: (j['content'] ?? '').toString(),
    summary: (j['summary'] ?? '').toString(),
    model: (j['model'] ?? '').toString(),
    kind: (j['kind'] ?? '').toString(),
  );
}

class AiException implements Exception {
  final String message;
  const AiException(this.message);
  @override
  String toString() => message;
}
