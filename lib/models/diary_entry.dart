import 'package:uuid/uuid.dart';

import '../core/diary_note_ui_copy.dart';
import '../core/i18n.dart';

const _uuid = Uuid();

/// 心情
enum Mood {
  awesome, // 超棒
  good, // 开心
  okay, // 平静
  bad, // 郁闷
  terrible, // 糟糕
}

extension MoodX on Mood {
  String get label => labelFor(I18n.current);

  String labelFor(AppLocale locale) => switch (this) {
    Mood.awesome => locale == AppLocale.en ? 'Great' : '超棒',
    Mood.good => locale == AppLocale.en ? 'Good' : '开心',
    Mood.okay => locale == AppLocale.en ? 'Calm' : '平静',
    Mood.bad => locale == AppLocale.en ? 'Low' : '郁闷',
    Mood.terrible => locale == AppLocale.en ? 'Terrible' : '糟糕',
  };

  String get emoji => switch (this) {
    Mood.awesome => '😄',
    Mood.good => '🙂',
    Mood.okay => '😐',
    Mood.bad => '😔',
    Mood.terrible => '😢',
  };
}

/// 天气
enum Weather { sunny, cloudy, overcast, rain, snow, wind, fog, thunder }

extension WeatherX on Weather {
  String get label => labelFor(I18n.current);

  String labelFor(AppLocale locale) => switch (this) {
    Weather.sunny => locale == AppLocale.en ? 'Sunny' : '晴',
    Weather.cloudy => locale == AppLocale.en ? 'Cloudy' : '多云',
    Weather.overcast => locale == AppLocale.en ? 'Overcast' : '阴',
    Weather.rain => locale == AppLocale.en ? 'Rain' : '雨',
    Weather.snow => locale == AppLocale.en ? 'Snow' : '雪',
    Weather.wind => locale == AppLocale.en ? 'Wind' : '风',
    Weather.fog => locale == AppLocale.en ? 'Fog' : '雾',
    Weather.thunder => locale == AppLocale.en ? 'Thunder' : '雷',
  };

  String get emoji => switch (this) {
    Weather.sunny => '☀️',
    Weather.cloudy => '⛅',
    Weather.overcast => '☁️',
    Weather.rain => '🌧️',
    Weather.snow => '❄️',
    Weather.wind => '💨',
    Weather.fog => '🌫️',
    Weather.thunder => '⚡',
  };
}

/// 日记条目：按天记录，支持心情/天气/图片路径/标签
class DiaryEntry {
  final String id;
  DateTime date; // 日记归属日期(只看年月日)
  String content;
  Mood? mood;
  Weather? weather;
  List<String> tags;
  List<String> imagePaths; // 本地图片相对路径(可选)
  String? location;
  DateTime createdAt;
  DateTime updatedAt;

  DiaryEntry({
    String? id,
    required this.date,
    this.content = '',
    this.mood,
    this.weather,
    List<String>? tags,
    List<String>? imagePaths,
    this.location,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : id = id ?? _uuid.v4(),
       tags = tags ?? [],
       imagePaths = imagePaths ?? [],
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  String get dateKey =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String get title => titleFor(I18n.current);

  String titleFor(AppLocale locale) {
    final lines = content.trim().split('\n');
    return lines.isNotEmpty && lines.first.isNotEmpty
        ? lines.first
        : DiaryNoteUiCopy(locale).diaryTitle(date);
  }

  String get preview {
    final text = content.trim();
    if (text.isEmpty) return '';
    return text.length > 80 ? '${text.substring(0, 80)}…' : text;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date.toIso8601String(),
    'content': content,
    'mood': mood?.index,
    'weather': weather?.index,
    'tags': tags,
    'imagePaths': imagePaths,
    'location': location,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory DiaryEntry.fromJson(Map<String, dynamic> json) => DiaryEntry(
    id: json['id'],
    date: DateTime.parse(json['date']),
    content: json['content'] ?? '',
    mood: json['mood'] != null ? Mood.values[json['mood']] : null,
    weather: json['weather'] != null ? Weather.values[json['weather']] : null,
    tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
    imagePaths: (json['imagePaths'] as List<dynamic>?)?.cast<String>() ?? [],
    location: json['location'],
    createdAt: DateTime.parse(json['createdAt']),
    updatedAt: DateTime.parse(json['updatedAt']),
  );
}
