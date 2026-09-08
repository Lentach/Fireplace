/// (lxxvii) clause 3 — scanner-result normalization, pure Dart.
///
/// A scanned QR carries either the bare out-of-band code
/// (`fp-link.v1.…` / `fp-link.v2.…`, spec §5.1 + amendment (lxxvii) clause 2)
/// or the deep-link form — a URL whose FRAGMENT is the code
/// (`https://…/link#fp-link.…`), which is what a phone camera app opens.
///
/// Returns the bare code, or null when [raw] carries neither. Deliberately
/// shallow: full structural validation (UUID, key length, canonical base64url,
/// role segment) stays in `LinkOobCode.tryParse` — this helper only decides
/// "is there a link code in what the camera saw", so the scanner can hand the
/// ceremony the same string a manual paste would.
String? extractLinkCode(String raw) {
  var text = raw.trim();
  if (!text.startsWith('fp-link.')) {
    final uri = Uri.tryParse(text);
    if (uri == null) return null;
    final fragment = uri.fragment.trim();
    if (!fragment.startsWith('fp-link.')) return null;
    text = fragment;
  }
  if (!text.startsWith('fp-link.v1.') && !text.startsWith('fp-link.v2.')) {
    return null;
  }
  return text;
}
