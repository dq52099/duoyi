// 跨端平台判断。web/io 通过条件导入切换实现。
export 'platform_info_stub.dart' if (dart.library.io) 'platform_info_io.dart';
