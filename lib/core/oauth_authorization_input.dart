/// Stable, sanitized callback failures. The input and authorization code never
/// appear in exception messages or diagnostic projections.
enum OAuthAuthorizationInputFailure {
  malformedCode,
  malformedCallback,
  redirectMismatch,
  stateMismatch,
  authorizationError,
}

class OAuthAuthorizationInputException implements Exception {
  final OAuthAuthorizationInputFailure reason;
  const OAuthAuthorizationInputException(this.reason);

  @override
  String toString() => 'OAuth authorization input rejected (${reason.name})';
}

/// An explicit input mode, independent of pending-attempt authority.
///
/// Resolving this value checks syntax and callback bindings only. The storage
/// coordinator must separately validate the immutable attempt, draft, owner,
/// PKCE and age, then acquire and persist a dispatch claim before using a code.
class OAuthAuthorizationInput {
  final String _value;
  final bool _callback;

  const OAuthAuthorizationInput.manualCode(String code)
    : _value = code,
      _callback = false;

  const OAuthAuthorizationInput.callback(String uri)
    : _value = uri,
      _callback = true;

  bool get isCallback => _callback;

  String resolveCode({
    required String registeredRedirectUri,
    required String? expectedState,
  }) {
    if (!_callback) {
      final code = _value.trim();
      final parsed = Uri.tryParse(code);
      if (code.isEmpty ||
          _invalidCode.hasMatch(code) ||
          _uriScheme.hasMatch(code) ||
          code.startsWith('//') ||
          code.contains('?') ||
          code.contains('#') ||
          parsed?.hasScheme == true ||
          parsed?.hasAuthority == true ||
          parsed?.hasQuery == true ||
          parsed?.hasFragment == true) {
        throw const OAuthAuthorizationInputException(
          OAuthAuthorizationInputFailure.malformedCode,
        );
      }
      return code;
    }

    final rawCallback = _value.trim();
    final callback = Uri.tryParse(rawCallback);
    final redirect = Uri.tryParse(registeredRedirectUri);
    if (!_absoluteUnambiguous(callback, rawCallback) ||
        !_absoluteUnambiguous(redirect, registeredRedirectUri)) {
      throw const OAuthAuthorizationInputException(
        OAuthAuthorizationInputFailure.malformedCallback,
      );
    }
    final actual = callback!;
    final expected = redirect!;
    if (actual.scheme.toLowerCase() != expected.scheme.toLowerCase() ||
        actual.host.toLowerCase() != expected.host.toLowerCase() ||
        _port(actual) != _port(expected) ||
        actual.path != expected.path) {
      throw const OAuthAuthorizationInputException(
        OAuthAuthorizationInputFailure.redirectMismatch,
      );
    }

    final parameters = _parameters(actual);
    if (parameters.containsKey('error') ||
        parameters.containsKey('error_description') ||
        parameters.containsKey('error_uri')) {
      throw const OAuthAuthorizationInputException(
        OAuthAuthorizationInputFailure.authorizationError,
      );
    }
    final codes = parameters['code'];
    if (codes == null ||
        codes.length != 1 ||
        codes.single.isEmpty ||
        _invalidCode.hasMatch(codes.single)) {
      throw const OAuthAuthorizationInputException(
        OAuthAuthorizationInputFailure.malformedCode,
      );
    }
    final states = parameters['state'];
    if (expectedState == null ||
        expectedState.isEmpty ||
        states == null ||
        states.length != 1 ||
        states.single != expectedState) {
      throw const OAuthAuthorizationInputException(
        OAuthAuthorizationInputFailure.stateMismatch,
      );
    }
    for (final entry in _parameters(expected).entries) {
      // Authorization response parameters cannot also be fixed endpoint
      // parameters. Such a registration is ambiguous and is not admitted.
      if (const {
            'code',
            'state',
            'error',
            'error_description',
            'error_uri',
          }.contains(entry.key) ||
          !_sameValues(entry.value, parameters[entry.key])) {
        throw const OAuthAuthorizationInputException(
          OAuthAuthorizationInputFailure.redirectMismatch,
        );
      }
    }
    return codes.single;
  }

  static bool _absoluteUnambiguous(Uri? uri, String source) =>
      uri != null &&
      uri.hasScheme &&
      !_invalidCode.hasMatch(source) &&
      !source.contains(r'\') &&
      _hasValidPercentEscapes(source) &&
      !uri.hasFragment &&
      uri.userInfo.isEmpty &&
      !uri.authority.contains('@') &&
      !_hasRawUserInfo(source) &&
      (!const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
          (uri.hasAuthority && uri.host.isNotEmpty));

  static final _invalidCode = RegExp(r'[\s\x00-\x1f\x7f]');
  static final _uriScheme = RegExp(r'^[A-Za-z][A-Za-z0-9+.-]*:');
  static final _hexPair = RegExp(r'^[0-9A-Fa-f]{2}$');
  static final _rawAuthority = RegExp(r'^[A-Za-z][A-Za-z0-9+.-]*://([^/?#]*)');

  // Uri normalizes an empty userinfo separator out of authority. Check the
  // original authority, excluding the path/query, before that information is
  // lost; an @ inside an opaque code or a path is not a userinfo separator.
  static bool _hasRawUserInfo(String source) =>
      _rawAuthority.firstMatch(source)?.group(1)?.contains('@') ?? false;

  // Uri.parse repairs malformed percent escapes. Validate the original URI
  // first so repaired input cannot acquire callback or endpoint authority.
  static bool _hasValidPercentEscapes(String source) {
    for (var index = 0; index < source.length; index++) {
      if (source.codeUnitAt(index) != 0x25) continue;
      if (index + 2 >= source.length ||
          !_hexPair.hasMatch(source.substring(index + 1, index + 3))) {
        return false;
      }
      index += 2;
    }
    return true;
  }

  static Map<String, List<String>> _parameters(Uri uri) {
    try {
      return uri.queryParametersAll;
    } on FormatException {
      throw const OAuthAuthorizationInputException(
        OAuthAuthorizationInputFailure.malformedCallback,
      );
    }
  }

  static int _port(Uri uri) {
    if (uri.hasPort) return uri.port;
    return switch (uri.scheme.toLowerCase()) {
      'https' => 443,
      'http' => 80,
      _ => 0,
    };
  }

  static bool _sameValues(List<String> expected, List<String>? actual) {
    if (actual == null || expected.length != actual.length) return false;
    final wanted = [...expected]..sort();
    final received = [...actual]..sort();
    for (var index = 0; index < wanted.length; index++) {
      if (wanted[index] != received[index]) return false;
    }
    return true;
  }

  @override
  String toString() => 'OAuthAuthorizationInput';
}
