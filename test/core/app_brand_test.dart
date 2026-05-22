import 'package:duoyi/core/app_brand.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default brand uses Duoyi name', () {
    expect(AppBrands.defaultBrand.name, '多仪');
    expect(AppBrands.defaultBrand.strings.appTitle, '多仪');
  });
}
