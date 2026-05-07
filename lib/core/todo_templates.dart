import 'package:flutter/material.dart';

class TodoListTemplate {
  final String name;
  final IconData icon;
  final Color color;

  TodoListTemplate({
    required this.name,
    required this.icon,
    required this.color,
  });
}

class TodoListTemplates {
  static final List<TodoListTemplate> all = [
    TodoListTemplate(name: '工作', icon: Icons.work_outline, color: Colors.blue),
    TodoListTemplate(
      name: '个人',
      icon: Icons.person_outline,
      color: Colors.green,
    ),
    TodoListTemplate(
      name: '学习',
      icon: Icons.school_outlined,
      color: Colors.purple,
    ),
    TodoListTemplate(
      name: '购物',
      icon: Icons.shopping_bag_outlined,
      color: Colors.orange,
    ),
    TodoListTemplate(
      name: '阅读清单',
      icon: Icons.book_outlined,
      color: Colors.teal,
    ),
    TodoListTemplate(name: '健身', icon: Icons.fitness_center, color: Colors.red),
  ];
}
