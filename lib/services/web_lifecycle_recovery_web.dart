import 'dart:js_interop';

import 'package:web/web.dart' as web;

void Function()? installWebResumeListener(void Function() onResume) {
  final web.EventListener listener = ((web.Event _) {
    onResume();
  }).toJS;
  web.window.addEventListener('duoyi:web-resume', listener);
  return () {
    web.window.removeEventListener('duoyi:web-resume', listener);
  };
}
