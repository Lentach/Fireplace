import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

final _urlRegex = RegExp(r'https?://[^\s]+', caseSensitive: false);

InlineSpan _buildPlainTextRun(String run, TextStyle style) =>
    TextSpan(text: run, style: style);

void _addRun(
  List<InlineSpan> spans,
  InlineSpan Function(String run, TextStyle style) buildRun,
  String run,
  TextStyle style,
) {
  final span = buildRun(run, style);
  if (span is TextSpan &&
      span.text == null &&
      span.style == null &&
      span.recognizer == null &&
      span.children != null) {
    spans.addAll(span.children!);
    return;
  }
  spans.add(span);
}

/// Builds text spans with HTTP(S) URLs styled and opened as external links.
///
/// Each URL creates a [TapGestureRecognizer]. [TextSpan] does not dispose
/// recognizers, so callers that retain these spans must dispose their
/// recognizers. This mirrors the existing in-app message-span pattern.
List<InlineSpan> buildLinkifiedSpans(
  String text, {
  required TextStyle style,
  TextStyle? linkStyle,
  InlineSpan Function(String run, TextStyle style)? runBuilder,
}) {
  final buildRun = runBuilder ?? _buildPlainTextRun;
  final spans = <InlineSpan>[];
  var last = 0;

  for (final match in _urlRegex.allMatches(text)) {
    if (match.start > last) {
      _addRun(spans, buildRun, text.substring(last, match.start), style);
    }

    final url = match.group(0)!;
    spans.add(
      TextSpan(
        text: url,
        style:
            linkStyle ?? style.copyWith(decoration: TextDecoration.underline),
        recognizer: TapGestureRecognizer()
          ..onTap = () =>
              launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      ),
    );
    last = match.end;
  }

  if (last < text.length) {
    _addRun(spans, buildRun, text.substring(last), style);
  }

  return spans;
}
