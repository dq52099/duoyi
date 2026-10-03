import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class CachedAvatarImage extends StatefulWidget {
  final String url;
  final double width;
  final double height;
  final BoxFit fit;
  final Object? cacheKey;
  final Widget Function(BuildContext context) fallbackBuilder;

  const CachedAvatarImage({
    super.key,
    required this.url,
    required this.width,
    required this.height,
    required this.fallbackBuilder,
    this.fit = BoxFit.cover,
    this.cacheKey,
  });

  @override
  State<CachedAvatarImage> createState() => _CachedAvatarImageState();
}

class _CachedAvatarImageState extends State<CachedAvatarImage> {
  static Future<Directory>? _cacheRootFuture;

  File? _cachedFile;
  bool _cacheLookupComplete = false;
  bool _networkFailed = false;
  int _cacheLookupGeneration = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCachedFile());
  }

  @override
  void didUpdateWidget(CachedAvatarImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url == widget.url && oldWidget.cacheKey == widget.cacheKey) {
      return;
    }
    _networkFailed = false;
    _cachedFile = null;
    _cacheLookupComplete = false;
    unawaited(_loadCachedFile());
  }

  @override
  Widget build(BuildContext context) {
    if (widget.url.trim().isEmpty) {
      return _stableFrame(widget.fallbackBuilder(context), center: true);
    }
    final cached = _cachedFile;
    if (cached != null) {
      return _fileImage(context, cached);
    }
    if (!_cacheLookupComplete || _networkFailed) {
      return _stableFrame(widget.fallbackBuilder(context), center: true);
    }
    return _stableFrame(
      Image.network(
        widget.url,
        width: widget.width,
        height: widget.height,
        cacheWidth: _decodePixels(context, widget.width),
        cacheHeight: _decodePixels(context, widget.height),
        fit: widget.fit,
        errorBuilder: (context, _, _) {
          if (!_networkFailed) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _networkFailed = true);
            });
          }
          return cached == null
              ? _stableFrame(widget.fallbackBuilder(context), center: true)
              : _fileImage(context, cached);
        },
      ),
      center: false,
    );
  }

  Widget _fileImage(BuildContext context, File file) {
    return _stableFrame(
      Image.file(
        file,
        width: widget.width,
        height: widget.height,
        cacheWidth: _decodePixels(context, widget.width),
        cacheHeight: _decodePixels(context, widget.height),
        fit: widget.fit,
        errorBuilder: (context, _, _) =>
            _stableFrame(widget.fallbackBuilder(context), center: true),
      ),
      center: false,
    );
  }

  int? _decodePixels(BuildContext context, double logicalSize) {
    if (!logicalSize.isFinite || logicalSize <= 0) return null;
    final pixels = (logicalSize * MediaQuery.devicePixelRatioOf(context))
        .ceil();
    return pixels.clamp(1, 4096).toInt();
  }

  Widget _stableFrame(Widget child, {required bool center}) {
    final width = widget.width.isFinite ? widget.width : null;
    final height = widget.height.isFinite ? widget.height : null;
    final content = center ? Center(child: child) : child;
    if (width == null && height == null) return content;
    return SizedBox(width: width, height: height, child: content);
  }

  Future<void> _loadCachedFile() async {
    final url = widget.url;
    final cacheKey = _effectiveCacheKey;
    final generation = ++_cacheLookupGeneration;
    final file = await _avatarCacheFile(cacheKey);
    if (!mounted) return;
    if (generation != _cacheLookupGeneration ||
        url != widget.url ||
        cacheKey != _effectiveCacheKey) {
      return;
    }
    if (await file.exists()) {
      setState(() {
        _cachedFile = file;
        _cacheLookupComplete = true;
      });
    } else {
      setState(() => _cacheLookupComplete = true);
    }
  }

  String get _effectiveCacheKey {
    final explicit = widget.cacheKey?.toString().trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    return widget.url;
  }

  Future<File> _avatarCacheFile(String cacheKey) async {
    final dir = await (_cacheRootFuture ??= getApplicationDocumentsDirectory()
        .then((root) => Directory('${root.path}/avatar_cache')));
    final digest = sha1.convert(cacheKey.codeUnits).toString();
    return File('${dir.path}/$digest.img');
  }
}
