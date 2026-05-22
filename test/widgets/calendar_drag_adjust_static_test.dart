import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('日视图事件支持拖动调整时间', () {
    final agenda = File(
      'lib/widgets/calendar_day_agenda.dart',
    ).readAsStringSync();

    expect(agenda, contains('_DraggableEventCard'));
    expect(agenda, contains('onVerticalDragUpdate'));
    expect(agenda, contains('onVerticalDragEnd'));
    expect(agenda, contains('_adjustTodo'));
    expect(agenda, contains('_adjustTimeEntry'));
    expect(agenda, contains('Duration(minutes: steps * 15)'));
    expect(agenda, contains('Icons.drag_indicator'));
  });
}
