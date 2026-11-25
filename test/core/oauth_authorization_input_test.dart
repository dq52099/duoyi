// Preparation only: these pure input cases have not been executed.
import 'package:duoyi/core/oauth_authorization_input.dart';
import 'package:flutter_test/flutter_test.dart';

const _redirect = 'https://calendar.example/oauth/google';
const _state = 'fixture-state96';
const _code = 'fixture-code96';
const _callback = '$_redirect?code=$_code&state=$_state';

String _resolve(
  OAuthAuthorizationInput input, {
  String redirect = _redirect,
  String? state = _state,
}) => input.resolveCode(registeredRedirectUri: redirect, expectedState: state);

void _reject(
  OAuthAuthorizationInput input,
  OAuthAuthorizationInputFailure reason, {
  String redirect = _redirect,
  String? state = _state,
}) {
  expect(
    () => _resolve(input, redirect: redirect, state: state),
    throwsA(
      isA<OAuthAuthorizationInputException>().having(
        (error) => error.reason,
        'reason',
        reason,
      ),
    ),
  );
}

void main() {
  test(
    'OI96-01 Google HTTPS callback decodes opaque code and permits response extras',
    () {
      const input = OAuthAuthorizationInput.callback(
        '$_redirect?code=4%2F0Google%2Bopaque-96&state=$_state&authuser=0&scope=email',
      );
      expect(input.isCallback, isTrue);
      expect(_resolve(input), '4/0Google+opaque-96');
    },
  );

  test('OI96-02 registered custom hierarchical redirect resolves callback', () {
    const redirect = 'duoyi://oauth/calendar';
    const input = OAuthAuthorizationInput.callback(
      '$redirect?code=custom-code96&state=$_state',
    );
    expect(_resolve(input, redirect: redirect), 'custom-code96');
  });

  test(
    'OI96-03 Google installed-app hostless custom redirect resolves callback',
    () {
      const redirect = 'com.googleusercontent.apps.fixture96:/oauth2redirect';
      const input = OAuthAuthorizationInput.callback(
        '$redirect?code=4%2F0Installed-96&state=$_state',
      );
      expect(_resolve(input, redirect: redirect), '4/0Installed-96');
    },
  );

  test(
    'OI96-04 scheme and host case plus outer pasted whitespace are canonical',
    () {
      const input = OAuthAuthorizationInput.callback(
        ' \nHTTPS://CALENDAR.EXAMPLE/oauth/google?code=$_code&state=$_state\t ',
      );
      expect(_resolve(input), _code);
    },
  );

  test(
    'OI96-05 explicit and implicit HTTPS HTTP default ports match both ways',
    () {
      const pairs = <(String, String)>[
        ('https://calendar.example/cb', 'https://calendar.example:443/cb'),
        ('https://calendar.example:443/cb', 'https://calendar.example/cb'),
        ('http://calendar.example/cb', 'http://calendar.example:80/cb'),
        ('http://calendar.example:80/cb', 'http://calendar.example/cb'),
      ];
      for (final (redirect, endpoint) in pairs) {
        expect(
          _resolve(
            OAuthAuthorizationInput.callback(
              '$endpoint?code=$_code&state=$_state',
            ),
            redirect: redirect,
          ),
          _code,
        );
      }
    },
  );

  test('OI96-06 matching registered nondefault port resolves callback', () {
    const redirect = 'https://calendar.example:9443/oauth/google';
    expect(
      _resolve(
        const OAuthAuthorizationInput.callback(
          '$redirect?code=$_code&state=$_state',
        ),
        redirect: redirect,
      ),
      _code,
    );
  });

  test(
    'OI96-07 fixed query compares reordered duplicate values as a decoded multiset',
    () {
      const redirect =
          '$_redirect?tag=alpha&tag=alpha&tag=beta&tenant=Team%20A';
      const input = OAuthAuthorizationInput.callback(
        '$_redirect?tag=beta&tenant=Team+A&tag=alpha&tag=alpha&code=$_code&state=$_state',
      );
      expect(_resolve(input, redirect: redirect), _code);
    },
  );

  test(
    'OI96-08 fixed query missing key or changed value is a redirect mismatch',
    () {
      const redirect = '$_redirect?tenant=team96&mode=calendar';
      for (final query in [
        'mode=calendar',
        'tenant=wrong&mode=calendar',
        'tenant=team96&mode=wrong',
      ]) {
        _reject(
          OAuthAuthorizationInput.callback(
            '$_redirect?$query&code=$_code&state=$_state',
          ),
          OAuthAuthorizationInputFailure.redirectMismatch,
          redirect: redirect,
        );
      }
    },
  );

  test(
    'OI96-09 fixed query requires exact duplicate counts and value distribution',
    () {
      const redirect = '$_redirect?tag=alpha&tag=alpha&tag=beta';
      for (final query in [
        'tag=alpha&tag=beta',
        'tag=alpha&tag=alpha&tag=beta&tag=alpha',
        'tag=alpha&tag=beta&tag=beta',
      ]) {
        _reject(
          OAuthAuthorizationInput.callback(
            '$_redirect?$query&code=$_code&state=$_state',
          ),
          OAuthAuthorizationInputFailure.redirectMismatch,
          redirect: redirect,
        );
      }
    },
  );

  test('OI96-10 wrong callback scheme is a redirect mismatch', () {
    _reject(
      const OAuthAuthorizationInput.callback(
        'http://calendar.example/oauth/google?code=$_code&state=$_state',
      ),
      OAuthAuthorizationInputFailure.redirectMismatch,
    );
  });

  test(
    'OI96-11 wrong callback host including suffix lookalike is rejected',
    () {
      for (final host in ['other.example', 'calendar.example.evil']) {
        _reject(
          OAuthAuthorizationInput.callback(
            'https://$host/oauth/google?code=$_code&state=$_state',
          ),
          OAuthAuthorizationInputFailure.redirectMismatch,
        );
      }
    },
  );

  test('OI96-12 wrong effective or nondefault callback port is rejected', () {
    _reject(
      const OAuthAuthorizationInput.callback(
        'https://calendar.example:80/oauth/google?code=$_code&state=$_state',
      ),
      OAuthAuthorizationInputFailure.redirectMismatch,
    );
    _reject(
      const OAuthAuthorizationInput.callback(
        'https://calendar.example:9444/oauth/google?code=$_code&state=$_state',
      ),
      OAuthAuthorizationInputFailure.redirectMismatch,
      redirect: 'https://calendar.example:9443/oauth/google',
    );
  });

  test('OI96-13 callback path must match case spelling and trailing slash', () {
    for (final path in ['/oauth/Google', '/oauth/google/', '/oauth/other']) {
      _reject(
        OAuthAuthorizationInput.callback(
          'https://calendar.example$path?code=$_code&state=$_state',
        ),
        OAuthAuthorizationInputFailure.redirectMismatch,
      );
    }
  });

  test(
    'OI96-14 registered fixed authorization response parameters are ambiguous',
    () {
      for (final key in [
        'code',
        'state',
        'error',
        'error_description',
        'error_uri',
      ]) {
        _reject(
          const OAuthAuthorizationInput.callback(_callback),
          OAuthAuthorizationInputFailure.redirectMismatch,
          redirect: '$_redirect?$key=${key == 'code' ? _code : _state}',
        );
      }
    },
  );

  test('OI96-15 userinfo and empty userinfo are forbidden on either URI', () {
    for (final authority in [
      'user96:password96@calendar.example',
      '@calendar.example',
    ]) {
      final endpoint = 'https://$authority/oauth/google';
      _reject(
        OAuthAuthorizationInput.callback('$endpoint?code=$_code&state=$_state'),
        OAuthAuthorizationInputFailure.malformedCallback,
      );
      _reject(
        const OAuthAuthorizationInput.callback(_callback),
        OAuthAuthorizationInputFailure.malformedCallback,
        redirect: endpoint,
      );
    }
  });

  test('OI96-16 nonempty and empty fragments are forbidden on either URI', () {
    for (final fragment in ['#fragment96', '#']) {
      _reject(
        OAuthAuthorizationInput.callback('$_callback$fragment'),
        OAuthAuthorizationInputFailure.malformedCallback,
      );
      _reject(
        const OAuthAuthorizationInput.callback(_callback),
        OAuthAuthorizationInputFailure.malformedCallback,
        redirect: '$_redirect$fragment',
      );
    }
  });

  test(
    'OI96-17 callback and registration reject malformed URI and query encoding',
    () {
      for (final value in [
        '',
        'relative/cb?code=$_code&state=$_state',
        '4/0Raw-96',
        'https:/oauth/google?code=$_code&state=$_state',
        'https:///oauth/google?code=$_code&state=$_state',
        'http:opaque?code=$_code&state=$_state',
        '$_redirect?code=%FF&state=$_state',
        '$_redirect?code=$_code&state=%C3%28',
        '$_redirect?%FF=value&code=$_code&state=$_state',
      ]) {
        _reject(
          OAuthAuthorizationInput.callback(value),
          OAuthAuthorizationInputFailure.malformedCallback,
        );
      }
      for (final redirect in [
        '',
        '/oauth/google',
        'relative/cb',
        'https:/oauth/google',
        'https:///oauth/google',
        'http:opaque',
        '$_redirect?tenant=%FF',
      ]) {
        _reject(
          const OAuthAuthorizationInput.callback(_callback),
          OAuthAuthorizationInputFailure.malformedCallback,
          redirect: redirect,
        );
      }
    },
  );

  test(
    'OI96-18 callback code cannot be missing empty or decoded whitespace or controls',
    () {
      for (final query in [
        '',
        'code',
        'code=',
        'code=%20',
        'code=%09',
        'code=alpha+beta',
        'code=%20alpha',
        'code=%00',
        'code=alpha%00beta',
        'code=alpha%1Fbeta',
        'code=alpha%7Fbeta',
      ]) {
        _reject(
          OAuthAuthorizationInput.callback('$_redirect?$query&state=$_state'),
          OAuthAuthorizationInputFailure.malformedCode,
        );
      }
    },
  );

  test(
    'OI96-19 repeated callback codes including encoded duplicate key are rejected',
    () {
      for (final query in [
        'code=one&code=one',
        'code=one&code=two',
        'code=one&%63ode=one',
      ]) {
        _reject(
          OAuthAuthorizationInput.callback('$_redirect?$query&state=$_state'),
          OAuthAuthorizationInputFailure.malformedCode,
        );
      }
    },
  );

  test(
    'OI96-20 callback state cannot be missing empty or different from expected',
    () {
      for (final query in [
        '',
        'state',
        'state=',
        'state=other96',
        'state=%20',
      ]) {
        _reject(
          OAuthAuthorizationInput.callback('$_redirect?code=$_code&$query'),
          OAuthAuthorizationInputFailure.stateMismatch,
        );
      }
    },
  );

  test(
    'OI96-21 repeated callback states including encoded duplicate key are rejected',
    () {
      for (final query in [
        'state=$_state&state=$_state',
        'state=$_state&state=other96',
        'state=$_state&%73tate=$_state',
      ]) {
        _reject(
          OAuthAuthorizationInput.callback('$_redirect?code=$_code&$query'),
          OAuthAuthorizationInputFailure.stateMismatch,
        );
      }
    },
  );

  test(
    'OI96-22 absent expected state cannot disable callback state binding',
    () {
      for (final state in <String?>[null, '']) {
        _reject(
          const OAuthAuthorizationInput.callback(_callback),
          OAuthAuthorizationInputFailure.stateMismatch,
          state: state,
        );
      }
    },
  );

  test(
    'OI96-23 authorization error keys reject even otherwise valid code and state',
    () {
      for (final key in ['error', 'error_description', 'error_uri']) {
        for (final suffix in ['', '=denied96']) {
          _reject(
            OAuthAuthorizationInput.callback('$_callback&$key$suffix'),
            OAuthAuthorizationInputFailure.authorizationError,
          );
        }
      }
    },
  );

  test(
    'OI96-24 manual Google opaque slash code preserves plus and trims only edges',
    () {
      const input = OAuthAuthorizationInput.manualCode(
        ' \t4/0Manual+opaque_code.96\n ',
      );
      expect(input.isCallback, isFalse);
      expect(_resolve(input, state: null), '4/0Manual+opaque_code.96');
    },
  );

  test('OI96-25 URI shaped manual input cannot bypass callback validation', () {
    for (final value in [
      _callback,
      '$_redirect?code=$_code&state=wrong96',
      'duoyi://oauth/calendar?code=$_code&state=$_state',
      '//calendar.example/oauth/google?code=$_code&state=$_state',
      'relative/cb?code=$_code&state=$_state',
      'opaque-code96#fragment96',
      'urn:fixture:code96',
    ]) {
      final input = OAuthAuthorizationInput.manualCode(value);
      expect(input.isCallback, isFalse);
      _reject(input, OAuthAuthorizationInputFailure.malformedCode);
    }
  });

  test('OI96-26 manual code rejects blank whitespace and ASCII controls', () {
    for (final value in [
      '',
      ' \t\n ',
      'code one96',
      'code\tone96',
      'code\none96',
      'code\u0000one96',
      'code\u001fone96',
      'code\u007fone96',
    ]) {
      _reject(
        OAuthAuthorizationInput.manualCode(value),
        OAuthAuthorizationInputFailure.malformedCode,
      );
    }
  });

  test('OI96-27 input and actual rejection diagnostics omit sensitive values', () {
    const secretCode = 'sensitive-code96';
    const secretState = 'sensitive-state96';
    const secretError = 'sensitive-provider-error96';
    const vectors = <(OAuthAuthorizationInput, OAuthAuthorizationInputFailure)>[
      (
        OAuthAuthorizationInput.manualCode(
          '$_redirect?code=$secretCode&state=$secretState',
        ),
        OAuthAuthorizationInputFailure.malformedCode,
      ),
      (
        OAuthAuthorizationInput.callback(
          'https://user96:password96@calendar.example/oauth/google?code=$secretCode&state=$secretState',
        ),
        OAuthAuthorizationInputFailure.malformedCallback,
      ),
      (
        OAuthAuthorizationInput.callback(
          '$_redirect?code=%FF&state=$secretState&error_description=$secretError',
        ),
        OAuthAuthorizationInputFailure.malformedCallback,
      ),
      (
        OAuthAuthorizationInput.callback(
          'https://wrong96.example/oauth/google?code=$secretCode&state=$secretState',
        ),
        OAuthAuthorizationInputFailure.redirectMismatch,
      ),
      (
        OAuthAuthorizationInput.callback(
          '$_redirect?code=$secretCode&state=$secretState',
        ),
        OAuthAuthorizationInputFailure.stateMismatch,
      ),
      (
        OAuthAuthorizationInput.callback(
          '$_redirect?code=$secretCode&state=$_state&error_description=$secretError',
        ),
        OAuthAuthorizationInputFailure.authorizationError,
      ),
    ];
    for (final (input, reason) in vectors) {
      expect(input.toString(), 'OAuthAuthorizationInput');
      try {
        _resolve(input);
        fail('Expected the real input API to reject ${reason.name}');
      } on OAuthAuthorizationInputException catch (error) {
        expect(error.reason, reason);
        final diagnostic = error.toString();
        expect(
          diagnostic,
          'OAuth authorization input rejected (${reason.name})',
        );
        for (final sensitive in [
          secretCode,
          secretState,
          secretError,
          'password96',
          _redirect,
        ]) {
          expect(diagnostic, isNot(contains(sensitive)));
        }
      }
    }
    const manualInput = OAuthAuthorizationInput.manualCode(secretCode);
    expect(manualInput.toString(), 'OAuthAuthorizationInput');
  });

  test('OI96-28 fixed query empty values remain an exact multiset', () {
    const redirect = '$_redirect?mode=&mode=';
    const valid = OAuthAuthorizationInput.callback(
      '$_redirect?mode&mode=&code=$_code&state=$_state',
    );
    expect(_resolve(valid, redirect: redirect), _code);
    _reject(
      const OAuthAuthorizationInput.callback(
        '$_redirect?mode=&code=$_code&state=$_state',
      ),
      OAuthAuthorizationInputFailure.redirectMismatch,
      redirect: redirect,
    );
  });

  test(
    'OI96-29 malformed port or authority cannot fall back to manual raw code',
    () {
      for (final value in [
        'https://calendar.example:bad/oauth/google?code=$_code&state=$_state',
        'https://calendar.example:bad/oauth/google',
        'https://[::g]/oauth/google?code=$_code&state=$_state',
        '//calendar.example:bad/oauth/google',
        '//[::g]/oauth/google',
      ]) {
        final input = OAuthAuthorizationInput.manualCode(value);
        expect(input.isCallback, isFalse);
        _reject(input, OAuthAuthorizationInputFailure.malformedCode);
      }
    },
  );

  test(
    'OI96-30 callback and registration reject malformed raw percent escapes',
    () {
      for (final escape in ['%', '%2', '%GG']) {
        _reject(
          OAuthAuthorizationInput.callback(
            '$_redirect?code=$escape&state=$_state',
          ),
          OAuthAuthorizationInputFailure.malformedCallback,
        );
        _reject(
          OAuthAuthorizationInput.callback(
            '$_redirect?$escape=value&code=$_code&state=$_state',
          ),
          OAuthAuthorizationInputFailure.malformedCallback,
        );
        _reject(
          const OAuthAuthorizationInput.callback(_callback),
          OAuthAuthorizationInputFailure.malformedCallback,
          redirect: '$_redirect?tenant=$escape',
        );
        _reject(
          const OAuthAuthorizationInput.callback(_callback),
          OAuthAuthorizationInputFailure.malformedCallback,
          redirect: '$_redirect?$escape=value',
        );
      }
    },
  );

  test(
    'OI96-31 valid callback percent decoding and literal manual percent stay distinct',
    () {
      const callback = OAuthAuthorizationInput.callback(
        '$_redirect?code=4%2F0Percent%25opaque%2Bcode101&state=$_state',
      );
      expect(_resolve(callback), '4/0Percent%opaque+code101');
      for (final code in [
        '4/0Manual%opaque+code101',
        '4/0Manual%2Fopaque+code101',
      ]) {
        expect(
          _resolve(OAuthAuthorizationInput.manualCode(code), state: null),
          code,
        );
      }
    },
  );

  test('OI96-32 path and query at signs do not become authority userinfo', () {
    const endpoint = '$_redirect/@calendar';
    const redirect = '$endpoint?tenant=team%40example';
    const input = OAuthAuthorizationInput.callback(
      '$endpoint?tenant=team@example&code=4%2F0At%40opaque%2Bcode101&state=fixture%40state101',
    );
    expect(
      _resolve(input, redirect: redirect, state: 'fixture@state101'),
      '4/0At@opaque+code101',
    );
  });

  test('OI96-33 manual opaque slash and at sign code remains valid', () {
    const input = OAuthAuthorizationInput.manualCode(
      ' \t4/0Manual@opaque+code101\n ',
    );
    expect(input.isCallback, isFalse);
    expect(_resolve(input, state: null), '4/0Manual@opaque+code101');
  });

  test(
    'OI96-34 raw URI repairs reject while standard path canonicalization remains valid',
    () {
      for (final value in [
        'https://calendar.example/oauth/ google?code=$_code&state=$_state',
        '$_redirect?code=fixture code101&state=$_state',
        '$_redirect?code=fixture\tcode101&state=$_state',
        '$_redirect?code=fixture\u0000code101&state=$_state',
        '$_redirect?code=fixture\u007fcode101&state=$_state',
        'https://calendar.example/oauth\\google?code=$_code&state=$_state',
        'https:/\\@calendar.example/oauth/google?code=$_code&state=$_state',
      ]) {
        _reject(
          OAuthAuthorizationInput.callback(value),
          OAuthAuthorizationInputFailure.malformedCallback,
        );
      }
      for (final redirect in [
        'https://calendar.example/oauth/ google',
        '$_redirect?tenant=team name101',
        '$_redirect?tenant=team\tname101',
        '$_redirect?tenant=team\u0000name101',
        '$_redirect?tenant=team\u007fname101',
        'https://calendar.example/oauth\\google',
        'https:/\\@calendar.example/oauth/google',
      ]) {
        _reject(
          const OAuthAuthorizationInput.callback(_callback),
          OAuthAuthorizationInputFailure.malformedCallback,
          redirect: redirect,
        );
      }
      for (final path in [
        '/oauth/./google',
        '/oauth/unused/../google',
        '/oauth/%67oogle',
        '/oauth/unused/%2E%2E/google',
      ]) {
        final endpoint = 'https://calendar.example$path';
        expect(
          _resolve(
            OAuthAuthorizationInput.callback(
              '$endpoint?code=$_code&state=$_state',
            ),
          ),
          _code,
        );
        expect(
          _resolve(
            const OAuthAuthorizationInput.callback(_callback),
            redirect: endpoint,
          ),
          _code,
        );
      }
      _reject(
        const OAuthAuthorizationInput.callback(
          'https://calendar.example/oauth%2Fgoogle?code=$_code&state=$_state',
        ),
        OAuthAuthorizationInputFailure.redirectMismatch,
      );
    },
  );
}
