import 'package:web/web.dart' as web;

import '../services/device_link/link_crypto.dart';

/// Read a §5.1 link code carried in the URL fragment (`/link#fp-link.v1.…`)
/// — the QR deep-link form. Called once at app start before [runApp].
/// Returns the raw fragment text (validated by [LinkOobCode.tryParse] at the
/// consumer), or null when the URL carries none.
String? consumeLinkFragment() {
  if (Uri.base.path != kLinkDeepLinkPath) return null;
  final fragment = Uri.base.fragment;
  if (!fragment.startsWith('fp-link.')) return null;
  return fragment;
}

/// Replace the deep-link URL with the app root so a refresh does not re-open
/// the ceremony, and so the one-time code does not sit in the address bar or
/// browser history. The fragment was never sent to the server.
void stripLinkFragment() {
  if (Uri.base.path != kLinkDeepLinkPath) return;
  final root = Uri.base.replace(path: '/', fragment: '', query: null);
  web.window.history.replaceState(null, '', root.toString());
}

/// The origin a QR should point at so a phone camera opens THIS install.
Uri linkDeepLinkOrigin() => Uri.base;
