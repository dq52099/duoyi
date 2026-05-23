import 'package:test/test.dart';

import 'package:duoyi/models/course_schedule.dart';

void main() {
  test('CourseItem JSON roundtrip keeps updatedAt for sync merge', () {
    final updatedAt = DateTime(2026, 5, 20, 8, 30);
    final original = CourseItem(
      id: 'course-sync',
      name: '高等数学',
      teacher: '王老师',
      location: 'A101',
      weekday: 1,
      startSection: 1,
      sectionCount: 2,
      weeks: const [1, 2, 3],
      updatedAt: updatedAt,
    );

    final decoded = CourseItem.fromJson(original.toJson());

    expect(decoded.id, original.id);
    expect(decoded.name, original.name);
    expect(decoded.teacher, original.teacher);
    expect(decoded.location, original.location);
    expect(decoded.weekday, original.weekday);
    expect(decoded.startSection, original.startSection);
    expect(decoded.sectionCount, original.sectionCount);
    expect(decoded.weeks, original.weeks);
    expect(decoded.updatedAt, updatedAt);
  });

  test('CourseItem accepts legacy snake_case updated_at', () {
    final decoded = CourseItem.fromJson({
      'id': 'course-legacy',
      'name': '英语',
      'weekday': 2,
      'startSection': 3,
      'updated_at': '2026-05-20T09:00:00.000',
    });

    expect(decoded.updatedAt, DateTime(2026, 5, 20, 9));
  });
}
