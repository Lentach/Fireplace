import '../config/app_config.dart';

/// Detection for Anti-Quantum Note links: `<baseUrl>/note/<32-hex>#<b64url key>`.
///
/// The whole trimmed message must be exactly ONE own-origin note URL — the
/// banner replaces the bubble body, so a URL embedded in prose stays a plain
/// link. Host is pinned to [AppConfig.baseUrl]: a foreign host must never
/// wear the trusted note banner.
final RegExp _noteUrlTail = RegExp(r'^[0-9a-f]{32}#[A-Za-z0-9_-]+=*$');

bool isAntiQuantumNoteUrl(String content, {String? baseUrl}) {
  final trimmed = content.trim();
  final prefix = '${baseUrl ?? AppConfig.baseUrl}/note/';
  if (!trimmed.startsWith(prefix)) return false;
  return _noteUrlTail.hasMatch(trimmed.substring(prefix.length));
}
