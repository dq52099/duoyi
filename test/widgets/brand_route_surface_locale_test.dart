import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:duoyi/core/i18n.dart';
import 'package:duoyi/providers/theme_provider.dart';
import 'package:duoyi/widgets/brand_background.dart';

/// 挂在 BrandRouteSurface 下的 const 子页：模拟
/// `const BrandRouteSurface(child: XxxScreen())` 推入路由后，
/// 父级不会下发新实例的形态。
class _ConstLocaleProbe extends StatelessWidget {
  const _ConstLocaleProbe();

  @override
  Widget build(BuildContext context) {
    return Text(I18n.tr('nav.mine'));
  }
}

void main() {
  testWidgets('BrandRouteSurface const 子树在语言热切换后重挂并跟随新语言', (tester) async {
    I18n.setLocale(AppLocale.zh);
    addTearDown(() => I18n.setLocale(AppLocale.zh));

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ThemeProvider(),
        child: const MaterialApp(
          home: BrandRouteSurface(child: _ConstLocaleProbe()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('我的'), findsOneWidget);

    // 语言热切换：不重建外层 widget 树，仅 I18n.setLocale 生效。
    I18n.setLocale(AppLocale.en);
    await tester.pumpAndSettle();

    expect(find.text('Me'), findsOneWidget);
    expect(find.text('我的'), findsNothing);
  });
}
