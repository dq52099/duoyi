import 'package:flutter/widgets.dart';

class DesktopEmbeddedHostScope extends InheritedWidget {
  const DesktopEmbeddedHostScope({super.key, required super.child});

  static bool isHosted(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DesktopEmbeddedHostScope>() !=
      null;

  @override
  bool updateShouldNotify(DesktopEmbeddedHostScope oldWidget) => false;
}
