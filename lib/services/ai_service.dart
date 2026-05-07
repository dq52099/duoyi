import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
      });
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
  }) async {
    final summary =
        '本周数据：完成 $completedTodos / $totalTodos 项待办，专注 $weeklyFocusMinutes 分钟，习惯连续打卡 $habitStreak 天。';
    final out = await _chat(
      '你是一个温柔且实用的效率教练。基于本周完成情况写一段 80-150 字的中文回顾，'
      '语气积极不空洞，先肯定 1-2 点亮点，再提 1-2 个具体可执行的下周建议。',
      summary,
      temperature: 0.6,
      maxTokens: 400,
    );
    // 存入历史
    final entry = AiReviewEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      createdAt: DateTime.now(),
      content: out,
      summary: summary,
      model: _model,
    );
    _reviewHistory.insert(0, entry);
    // 最多保留 50 条
    if (_reviewHistory.length > 50) {
      _reviewHistory = _reviewHistory.sublist(0, 50);
    }
    await _saveHistory();
    notifyListeners();
    return out;
  }
}

/// 持久化的 AI 周报条目。
class AiReviewEntry {
  final String id;
  final DateTime createdAt;
  final String content;
  final String summary;
  final String model;

  const AiReviewEntry({
    required this.id,
    required this.createdAt,
    required this.content,
    required this.summary,
    this.model = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'content': content,
        'summary': summary,
        'model': model,
      };

  factory AiReviewEntry.fromJson(Map<String, dynamic> j) => AiReviewEntry(
        id: j['id'].toString(),
        createdAt: DateTime.parse(j['createdAt']),
        content: (j['content'] ?? '').toString(),
        summary: (j['summary'] ?? '').toString(),
        model: (j['model'] ?? '').toString(),
      );
}

class AiException implements Exception {
  final String message;
  const AiException(this.message);
  @override
  String toString() => message;
}
