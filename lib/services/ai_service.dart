import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// OpenAI-compatible chat completions client. Defaults to the boxying gateway
/// pattern (base_url + bearer key). Used by:
/// - AI task breakdown ("分解一句话为子任务")
/// - AI weekly review ("根据本周数据生成一段总结")
class AiService extends ChangeNotifier {
  String _baseUrl = '';
  String _apiKey = '';
  String _model = 'gpt-4o-mini';
  bool _enabled = true;

  String get baseUrl => _baseUrl;
  String get apiKey => _apiKey;
  String get model => _model;
  bool get enabled => _enabled;
  bool get isConfigured => _baseUrl.isNotEmpty && _apiKey.isNotEmpty;

  static const String _kBase = 'ai_base_url';
  static const String _kKey = 'ai_api_key';
  static const String _kModel = 'ai_model';
  static const String _kEnabled = 'ai_enabled';

  Future<void> loadFromStorage() async {
    final p = await SharedPreferences.getInstance();
    _baseUrl = p.getString(_kBase) ?? 'https://image.6688667.xyz';
    _apiKey = p.getString(_kKey) ?? '';
    _model = p.getString(_kModel) ?? 'gpt-4o-mini';
    _enabled = p.getBool(_kEnabled) ?? true;
    notifyListeners();
  }

  Future<void> configure({String? baseUrl, String? apiKey, String? model, bool? enabled}) async {
    final p = await SharedPreferences.getInstance();
    if (baseUrl != null) {
      _baseUrl = baseUrl.trim();
      await p.setString(_kBase, _baseUrl);
    }
    if (apiKey != null) {
      _apiKey = apiKey.trim();
      await p.setString(_kKey, _apiKey);
    }
    if (model != null) {
      _model = model.trim();
      await p.setString(_kModel, _model);
    }
    if (enabled != null) {
      _enabled = enabled;
      await p.setBool(_kEnabled, _enabled);
    }
    notifyListeners();
  }

  /// Generic chat completion. Returns the assistant message text.
  Future<String> _chat(String systemPrompt, String userPrompt, {double temperature = 0.4}) async {
    if (!isConfigured) throw const AiException('未配置 AI 服务，请在我的→AI 助手中填写 base_url 与 key');
    final uri = Uri.parse('${_baseUrl.replaceAll(RegExp(r'/+$'), '')}/v1/chat/completions');
    final client = HttpClient();
    try {
      final req = await client.postUrl(uri);
      req.headers.set('Content-Type', 'application/json');
      req.headers.set('Authorization', 'Bearer $_apiKey');
      req.write(json.encode({
        'model': _model,
        'temperature': temperature,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
      }));
      final resp = await req.close();
      final raw = await resp.transform(utf8.decoder).join();
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw AiException('${resp.statusCode}: $raw');
      }
      final data = json.decode(raw);
      final choices = data['choices'];
      if (choices is List && choices.isNotEmpty) {
        final msg = choices.first['message'];
        if (msg is Map && msg['content'] is String) return msg['content'] as String;
      }
      return '';
    } finally {
      client.close();
    }
  }

  /// Break one short user goal into 3-7 subtasks. Returns plain string list.
  Future<List<String>> breakDownTask(String goal) async {
    final out = await _chat(
      '你是一个高效任务分解助手，将用户的目标拆成 3 到 7 条具体可执行的子任务。'
      '只输出子任务，每条一行，不要编号、解释、客套话。',
      goal,
      temperature: 0.3,
    );
    return out
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim().replaceFirst(RegExp(r'^[\-\*\d\.\s]+'), '').trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  /// Generate a short Chinese weekly review from raw stats.
  Future<String> weeklyReview({
    required int completedTodos,
    required int totalTodos,
    required int weeklyFocusMinutes,
    required int habitStreak,
  }) async {
    final summary =
        '本周数据：完成 $completedTodos / $totalTodos 项待办，专注 $weeklyFocusMinutes 分钟，习惯连续打卡 $habitStreak 天。';
    return _chat(
      '你是一个温柔且实用的效率教练。基于本周完成情况写一段 80-150 字的中文回顾，'
      '语气积极不空洞，先肯定 1-2 点亮点，再提 1-2 个具体可执行的下周建议。',
      summary,
      temperature: 0.6,
    );
  }
}

class AiException implements Exception {
  final String message;
  const AiException(this.message);
  @override
  String toString() => message;
}
