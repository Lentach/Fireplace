import '../config/app_config.dart';

/// Detection + parsing for Anti-Quantum Note links:
/// `<baseUrl>/note/<32-hex>#<b64url key>[&c=<convId>][&e=<expiry epoch ms>]`
///
/// The whole trimmed message must be exactly ONE own-origin note URL — the
/// banner replaces the bubble body, so a URL embedded in prose stays a plain
/// link. Host is pinned to [AppConfig.baseUrl]: a foreign host must never
/// wear the trusted note banner.
///
/// `c`/`e` live in the FRAGMENT on purpose: fragments are never transmitted
/// in HTTP requests, so the server learns neither the conversation id nor
/// anything it does not already know. `c` powers the reveal page's
/// "Open Fireplace" deep link (`/?notify_conv=<c>`); `e` powers the in-chat
/// self-destruct countdown without any server round trip.
final RegExp _noteUrlTail =
    RegExp(r'^[0-9a-f]{32}#[A-Za-z0-9_-]+=*(&[ce]=\d+)*$');

bool isAntiQuantumNoteUrl(String content, {String? baseUrl}) {
  final trimmed = content.trim();
  final prefix = '${baseUrl ?? AppConfig.baseUrl}/note/';
  if (!trimmed.startsWith(prefix)) return false;
  return _noteUrlTail.hasMatch(trimmed.substring(prefix.length));
}

class AntiQuantumNoteLink {
  final String url;

  /// 32-hex server token (the `/note/<token>` path segment) — the id the
  /// status endpoint takes. Never contains the key: that stays in the
  /// fragment.
  final String token;

  /// Server-side note death moment, from the `e` fragment param.
  /// Null for links sent before the countdown feature existed.
  final DateTime? expiresAt;

  const AntiQuantumNoteLink({
    required this.url,
    required this.token,
    this.expiresAt,
  });
}

/// Parse a note link previously accepted by [isAntiQuantumNoteUrl];
/// returns null when [content] is not a note link.
AntiQuantumNoteLink? parseAntiQuantumNoteLink(String content,
    {String? baseUrl}) {
  if (!isAntiQuantumNoteUrl(content, baseUrl: baseUrl)) return null;
  final url = content.trim();
  DateTime? expiresAt;
  final fragment = url.substring(url.indexOf('#') + 1);
  for (final part in fragment.split('&').skip(1)) {
    if (part.startsWith('e=')) {
      final ms = int.tryParse(part.substring(2));
      if (ms != null) {
        expiresAt = DateTime.fromMillisecondsSinceEpoch(ms);
      }
    }
  }
  final hashIndex = url.indexOf('#');
  final token = url.substring(hashIndex - 32, hashIndex);
  return AntiQuantumNoteLink(url: url, token: token, expiresAt: expiresAt);
}
