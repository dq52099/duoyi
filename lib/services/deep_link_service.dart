import 'package:flutter/services.dart';

class DeepLinkService {
  DeepLinkService._();

  static const MethodChannel _channel = MethodChannel('duoyi/deep_links');

  static void Function(Uri uri)? onLink;
  static void Function(String text)? onSharedText;

  static Future<void> init() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'onLink' && call.method != 'onSharedText') {
        return null;
      }
      if (call.method == 'onLink') {
        final raw = call.arguments?.toString();
        final uri = raw == null ? null : Uri.tryParse(raw);
        if (_isDuoyiDeepLink(uri)) onLink?.call(uri!);
      } else if (call.method == 'onSharedText') {
        final text = call.arguments?.toString().trim();
        if (text != null && text.isNotEmpty) onSharedText?.call(text);
      }
      return null;
    });
  }

  static Future<Uri?> takeInitialLink() async {
    final raw = await _channel.invokeMethod<String>('takeInitialLink');
    final uri = raw == null ? null : Uri.tryParse(raw);
    return _isDuoyiDeepLink(uri) ? uri : null;
  }

  static Future<Uri?> takeInitialOAuthLink() async {
    final raw = await _channel.invokeMethod<String>('takeInitialOAuthLink');
    final uri = raw == null ? null : Uri.tryParse(raw);
    return _isOAuthDeepLink(uri) ? uri : null;
  }

  static Future<String?> takeInitialSharedText() async {
    final raw = await _channel.invokeMethod<String>('takeInitialSharedText');
    final text = raw?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  static bool _isOAuthDeepLink(Uri? uri) {
    return uri != null && uri.scheme == 'duoyi' && uri.host == 'oauth';
  }

  static bool _isDuoyiDeepLink(Uri? uri) {
    return uri != null && uri.scheme == 'duoyi';
  }
}
