import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:duoyi/core/app_brand.dart';
import 'package:duoyi/widgets/brand_background.dart';

void main() {
  group('BrandBackgroundThumbnail（主题卡片背景缩略图）', () {
    testWidgets('有背景图的主题渲染 Image.asset 缩略图', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: BrandBackgroundThumbnail(
                brand: AppBrands.re0,
                fallback: const Icon(Icons.palette_outlined),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(Image), findsOneWidget);
      expect(find.byIcon(Icons.palette_outlined), findsNothing);
    });

    testWidgets('无背景图的默认主题回退到 fallback 图标', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: BrandBackgroundThumbnail(
                brand: AppBrands.defaultBrand,
                fallback: const Icon(Icons.palette_outlined),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.palette_outlined), findsOneWidget);
    });

    test('组件不引用任何解锁/网络接口（纯预览）', () {
      final source = File(
        'lib/widgets/brand_background.dart',
      ).readAsStringSync();
      final thumbnailStart = source.indexOf('class BrandBackgroundThumbnail');
      final thumbnailSource = source.substring(thumbnailStart);

      // 预览路径不允许出现解锁/后端调用相关 API。
      expect(thumbnailSource, isNot(contains('unlockBrand')));
      expect(thumbnailSource, isNot(contains('http')));
      expect(thumbnailSource, contains('errorBuilder'));
    });
  });
}
