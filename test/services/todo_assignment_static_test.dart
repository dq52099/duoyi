import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('共享任务支持负责人选择和列表展示', () {
    final todoModel = File('lib/models/todo.dart').readAsStringSync();
    final detail = File(
      'lib/screens/todo_detail_screen.dart',
    ).readAsStringSync();
    final todoScreen = File('lib/screens/todo_screen.dart').readAsStringSync();

    expect(todoModel, contains('String? assigneeId'));
    expect(todoModel, contains("'assigneeId': assigneeId"));
    expect(detail, contains('_AssignmentEditor'));
    expect(detail, contains('_TaskCommentsPanel'));
    expect(detail, contains('labelText: \'负责人\''));
    expect(detail, contains('assigneeId: value'));
    expect(detail, contains('targetId: widget.todoId'));
    expect(todoScreen, contains('Icons.assignment_ind_outlined'));
    expect(todoScreen, contains(r'@$assigneeName'));
  });
}
