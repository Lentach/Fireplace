import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Client-side link preview fetcher.
/// Used for E2E encrypted messages where the server cannot read content.
class LinkPreviewService {
  static final _urlRegex =
      RegExp(r'https?://[^\s<>"{}|\\^`\[\]]+', caseSensitive: false);

  static final _privateIpRegex = RegExp(
    r'^(localhost|127\.|10\.|172\.(1[6-9]|2\d|3[01])\.|192\.168\.|::1|fc00:|fd)',
    caseSensitive: false,
  );

  /// SSRF protection: only HTTPS, no private IPs.
  /// [pageUrl] used to resolve relative imageUrl (e.g. /image.png).
  static bool isSafeImageUrl(String? imageUrl, [String? pageUrl]) {
    if (imageUrl == null || imageUrl.isEmpty) return false;
    try {
      final Uri? resolved = pageUrl != null
          ? Uri.parse(pageUrl).resolve(imageUrl.trim())
          : Uri.tryParse(imageUrl.trim());
      if (resolved == null) return false;
      if (resolved.scheme != 'https') return false;
      final host = resolved.host;
      if (host.isEmpty) return false;
      final hostNorm = host.startsWith('[') ? host.substring(1, host.length - 1) : host;
      return !_privateIpRegex.hasMatch(hostNorm);
    } catch (_) {
      return false;
    }
  }

  /// First URL in [text], or null. Same regex the preview paths use.
  static String? extractFirstUrl(String text) =>
      _urlRegex.firstMatch(text)?.group(0);

  /// URL without its `#fragment`. Fragments can carry secrets (Anti-Quantum
  /// Note decryption keys, magic-link tokens) and are never needed to fetch
  /// a preview — HTTP never transmits them. NEVER send a fragment to the
  /// link-preview proxy.
  static String stripFragment(String url) {
    final hashIndex = url.indexOf('#');
    return hashIndex == -1 ? url : url.substring(0, hashIndex);
  }

  /// Extract first URL from text, fetch OG metadata, return preview or null.
  static Future<Map<String, String?>?> fetchPreview(String text) async {
    final match = _urlRegex.firstMatch(text);
    if (match == null) return null;
    final url = match.group(0)!;

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return null;

    // SSRF protection: skip private/local URLs
    if (_privateIpRegex.hasMatch(uri.host)) return null;

    try {
      final response = await http
          .get(uri, headers: {
            'User-Agent': 'Mozilla/5.0 (compatible; Fireplace/1.0)',
          })
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) return null;

      final contentType = response.headers['content-type'] ?? '';
      if (!contentType.contains('text/html')) return null;

      // Only parse first 100KB
      final html =
          response.body.substring(0, min(response.body.length, 100000));

      final title = _extractOgTag(html, 'og:title') ?? _extractTitle(html);
      final rawImageUrl = _extractOgTag(html, 'og:image');
      final imageUrl = rawImageUrl != null && isSafeImageUrl(rawImageUrl, url)
          ? rawImageUrl
          : null;

      if (title == null && imageUrl == null) return null;

      return {'url': url, 'title': title, 'imageUrl': imageUrl};
    } catch (e) {
      debugPrint('[LinkPreviewService] Failed to fetch preview for $url: $e');
      return null;
    }
  }

  static String? _extractOgTag(String html, String property) {
    // Match <meta property="og:title" content="...">
    final regex = RegExp(
      '<meta[^>]*property=["\']$property["\'][^>]*content=["\'](.*?)["\']',
      caseSensitive: false,
    );
    final match = regex.firstMatch(html);
    if (match != null) return _decodeHtmlEntities(match.group(1)!);

    // Also try content before property (some sites reverse attribute order)
    final regex2 = RegExp(
      '<meta[^>]*content=["\'](.*?)["\'][^>]*property=["\']$property["\']',
      caseSensitive: false,
    );
    final match2 = regex2.firstMatch(html);
    if (match2 != null) return _decodeHtmlEntities(match2.group(1)!);

    return null;
  }

  static String? _extractTitle(String html) {
    final regex = RegExp(
      '<title[^>]*>(.*?)</title>',
      caseSensitive: false,
      dotAll: true,
    );
    final match = regex.firstMatch(html);
    if (match != null) {
      final title = _decodeHtmlEntities(match.group(1)!.trim());
      return title.isEmpty ? null : title;
    }
    return null;
  }

  static String _decodeHtmlEntities(String text) {
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&#x27;', "'")
        .replaceAll('&apos;', "'");
  }
}
