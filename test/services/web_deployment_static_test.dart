import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('web release and pages deploy keep the public /duoyi/ deployment', () {
    final workflow = File('.github/workflows/build-apk.yml').readAsStringSync();
    final webJobStart = workflow.indexOf('\n  web:\n');
    final deployPagesJobStart = workflow.indexOf(
      '\n  deploy-pages:\n',
      webJobStart,
    );
    final releaseJobStart = workflow.indexOf('\n  release:\n', webJobStart);
    expect(webJobStart, greaterThanOrEqualTo(0));
    expect(deployPagesJobStart, greaterThan(webJobStart));
    expect(releaseJobStart, greaterThan(webJobStart));

    final webJob = workflow.substring(webJobStart, deployPagesJobStart);
    expect(
      webJob,
      contains(
        "DUOYI_WEB_BASE_HREF: \${{ vars.DUOYI_WEB_BASE_HREF || '/duoyi/' }}",
      ),
    );
    expect(
      webJob,
      contains('BUILD_ARGS=(--release --base-href "\$DUOYI_WEB_BASE_HREF")'),
    );
    expect(webJob, contains('--dart-define=DUOYI_WEB_TARGET=desktop'));
    expect(webJob, contains('--dart-define=DUOYI_WEB_TARGET=mobile'));
    expect(webJob, contains('mv build/web build/web-desktop'));
    expect(webJob, contains('mv build/web build/web-mobile'));
    expect(webJob, contains("github.ref == 'refs/heads/main'"));
    expect(webJob, contains('actions/upload-pages-artifact@v4'));
    expect(webJob, contains('path: build/web-desktop'));
    expect(
      webJob,
      contains(
        'web-artifacts/duoyi-web-\$SUFFIX.tar.gz" -C build/web-desktop .',
      ),
    );
    expect(webJob, contains('web-artifacts/duoyi-web-desktop-\$SUFFIX.tar.gz'));
    expect(webJob, contains('web-artifacts/duoyi-web-mobile-\$SUFFIX.tar.gz'));
    expect(
      webJob,
      contains(
        'web-artifacts/duoyi-web-mobile-\$SUFFIX.tar.gz" -C build/web-mobile .',
      ),
    );

    final deployPagesJob = workflow.substring(
      deployPagesJobStart,
      releaseJobStart,
    );
    expect(deployPagesJob, contains("needs: web"));
    expect(
      deployPagesJob,
      contains("if: github.ref == 'refs/heads/main'"),
    );
    expect(deployPagesJob, contains('pages: write'));
    expect(deployPagesJob, contains('id-token: write'));
    expect(deployPagesJob, contains('name: github-pages'));
    expect(deployPagesJob, contains('actions/deploy-pages@v4'));

    expect(
      workflow,
      isNot(contains('flutter build web --release --base-href "/"')),
      reason:
          'The public download page links to /duoyi/, so CI must not build a root-based web artifact by default.',
    );

    final downloadPage = File('deploy/duoyi.html').readAsStringSync();
    expect(downloadPage, contains('href="/duoyi/"'));
    expect(downloadPage, contains('http://6688667.xyz/duoyi/'));
    expect(downloadPage, contains('duoyi-web-desktop-v1.1.39.tar.gz'));
    expect(downloadPage, contains('duoyi-web-mobile-v1.1.39.tar.gz'));
    expect(downloadPage, isNot(contains('v1.1.38')));
    expect(downloadPage, isNot(contains('v1.1.37')));
    expect(downloadPage, isNot(contains('duoyi-v1.1.35.apk')));

    final webTarget = File('lib/core/web_target.dart').readAsStringSync();
    expect(webTarget, contains("String.fromEnvironment("));
    expect(webTarget, contains("'DUOYI_WEB_TARGET'"));
    expect(webTarget, contains("raw == 'desktop'"));
    expect(webTarget, contains("raw == 'mobile'"));

    final preferencesProvider = File(
      'lib/providers/preferences_provider.dart',
    ).readAsStringSync();
    expect(preferencesProvider, contains('desktopWebDefaultBottomNavTabs'));
    expect(preferencesProvider, contains('{0, 1, 2, 3, 6}'));
    expect(preferencesProvider, contains('isBottomNavTabSupported'));
    expect(preferencesProvider, contains('normalizeDefaultTab'));
    expect(preferencesProvider, contains('tab == 5'));

    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('WebTarget.isDesktopWebBuild'));
    expect(main, contains('_desktopWebVisibleBottomNavTabs'));
    expect(main, contains('if (tab == 5) continue;'));

    final moreApps = File(
      'lib/screens/more_apps_screen.dart',
    ).readAsStringSync();
    expect(moreApps, contains('WebTarget.isDesktopWebBuild'));
    expect(moreApps, contains('app.tab == 5'));

    final preferencesScreen = File(
      'lib/screens/preferences_screen.dart',
    ).readAsStringSync();
    expect(preferencesScreen, contains('WebTarget.isDesktopWebBuild'));
    expect(preferencesScreen, contains('isBottomNavTabSupported(tab)'));
    expect(
      preferencesScreen,
      contains('where(PreferencesProvider.isBottomNavTabSupported)'),
    );

    final widgetScreen = File(
      'lib/screens/widget_screen.dart',
    ).readAsStringSync();
    expect(widgetScreen, contains('desktop_web_widget_fallback'));
    expect(widgetScreen, contains('WidgetPreviewCard.calendar'));
    expect(widgetScreen, contains('const CalendarScreen()'));

    final builtIndex = File('build/web/index.html');
    if (builtIndex.existsSync()) {
      expect(builtIndex.readAsStringSync(), contains('<base href="/duoyi/">'));
    }
  });
}
