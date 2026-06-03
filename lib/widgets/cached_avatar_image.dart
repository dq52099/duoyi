import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class CachedAvatarImage extends StatefulWidget {
  final String url;
  final double width;
  final double height;
  final BoxFit fit;
  final Widget Function(BuildContext context) fallbackBuilder;

  const CachedAvatarImage({
    super.key,
    required this.url,
    required this.width,
    required this.height,
    required this.fallbackBuilder,
    this.fit = BoxFit.cover,
  });

  @override
  State<CachedAvatarImage> createState() => _CachedAvatarImageState();
}

class _CachedAvatarImageState extends State<CachedAvatarImage> {
  File? _cachedFile;
  bool _networkFailed = false;
  Object? _lastCachedUrl;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCachedFile());
  }

  @override
  void didUpdateWidget(CachedAvatarImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url == widget.url) return;
    _networkFailed = false;
    _cachedFile = null;
    _lastCachedUrl = null;
    unawaited(_loadCachedFile());
  }

  @override
  Widget build(BuildContext context) {
    final cached = _cachedFile;
    if (_networkFailed && cached != null) {
      return _fileImage(cached);
    }
    return Image.network(
      widget.url,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      errorBuilder: (context, _, _) {
        if (!_networkFailed) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _networkFailed = true);
          });
        }
        return cached == null
            ? widget.fallbackBuilder(context)
            : _fileImage(cached);
      },
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (frame != null || wasSynchronouslyLoaded) {
          _cacheNetworkAvatarOnce();
        }
        return child;
      },
    );
  }

  Widget _fileImage(File file) {
    return Image.file(
      file,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      errorBuilder: (context, _, _) => widget.fallbackBuilder(context),
    );
  }

  Future<void> _loadCachedFile() async {
    final file = await _avatarCacheFile(widget.url);
    if (!mounted) return;
    if (await file.exists()) {
      setState(() => _cachedFile = file);
    }
  }

  void _cacheNetworkAvatarOnce() {
    if (_lastCachedUrl == widget.url) return;
    _lastCachedUrl = widget.url;
    unawaited(_cacheNetworkAvatar());
  }

  Future<void> _cacheNetworkAvatar() async {
    try {
      final uri = Uri.tryParse(widget.url);
      if (uri == null || !uri.hasScheme) return;
      final response = await http.get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode < 200 || response.statusCode >= 300) return;
      if (response.bodyBytes.isEmpty ||
          response.bodyBytes.length > 4 * 1024 * 1024) {
        return;
      }
      final file = await _avatarCacheFile(widget.url);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(response.bodyBytes, flush: false);
      if (mounted) setState(() => _cachedFile = file);
    } catch (e, st) {
      debugPrint('[avatar-cache] cache failed: $e\n$st');
    }
  }

  Future<File> _avatarCacheFile(String url) async {
    final dir = await getApplicationDocumentsDirectory();
    final digest = sha1.convert(url.codeUnits).toString();
    return File('${dir.path}/avatar_cache/$digest.img');
  }
}
