/// A REST failure that kept its HTTP status.
///
/// The auth surface used to receive only a prose string
/// (`'nickname is already taken'`, `'Registration failed (502)'`), so every
/// caller that wanted to react to a specific refusal had to substring-match
/// untranslated server text — and none did, which is why a 409, a 400, a 429
/// and a gateway 502 all rendered as one "Something went wrong". The status is
/// the stable, localizable discriminator; [message] stays developer-facing.
class ApiException implements Exception {
  const ApiException({
    required this.statusCode,
    required this.message,
    this.endpoint,
  });

  /// HTTP status of the failing response.
  final int statusCode;

  /// The server's own `message` when it sent one, else a short fallback.
  /// Diagnostics only: untranslated, and never shown to a user verbatim.
  final String message;

  /// Which call failed, e.g. `POST /auth/register`. Diagnostics only.
  final String? endpoint;

  @override
  String toString() =>
      'ApiException($statusCode)${endpoint == null ? '' : ' $endpoint'}: '
      '$message';
}
