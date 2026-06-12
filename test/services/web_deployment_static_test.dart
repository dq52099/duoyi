import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('web release artifact keeps the public /duoyi/ deployment base href', () {
    final workflow = File('.github/workflows/build-apk.yml').readAsStringSync();
    final webJobStart = workflow.indexOf('\n  web:\n');
    final releaseJobStart = workflow.indexOf('\n  release:\n', webJobStart);
    expect(webJobStart, greaterThanOrEqualTo(0));
    expect(releaseJobStart, greaterThan(webJobStart));

    final webJob = workflow.substring(webJobStart, releaseJobStart);
    expect(
      webJob,
      contains(
        "DUOYI_WEB_BASE_HREF: \${{ vars.DUOYI_WEB_BASE_HREF || '/duoyi/' }}",
      ),
    );
    expect(
      webJob,
      contains(
        'flutter build web --release --base-href "\$DUOYI_WEB_BASE_HREF" \$DART_DEFINES',
      ),
    );
    expect(
      workflow,
      isNot(contains('flutter build web --release --base-href "/"')),
      reason:
          'The public download page links to /duoyi/, so CI must not build a root-based web artifact by default.',
    );

    final downloadPage = File('deploy/duoyi.html').readAsStringSync();
    expect(downloadPage, contains('href="/duoyi/"'));
    expect(downloadPage, contains('http://6688667.xyz/duoyi/'));

    final builtIndex = File('build/web/index.html');
    if (builtIndex.existsSync()) {
      expect(builtIndex.readAsStringSync(), contains('<base href="/duoyi/">'));
    }
  });
}
