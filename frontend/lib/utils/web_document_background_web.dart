import 'dart:js_interop';

import 'package:flutter/widgets.dart' show Color;
import 'package:web/web.dart' as web;

import 'web_document_background.dart';

String? _lastCss;

void syncWebDocumentBackground(Color color) {
  final css = webDocumentBackgroundCss(color);
  if (css == _lastCss) return; // called per MaterialApp.builder pass — dedupe
  _lastCss = css;
  final root = web.document.documentElement;
  if (root != null && root.isA<web.HTMLElement>()) {
    (root as web.HTMLElement).style.backgroundColor = css;
  }
  web.document.body?.style.backgroundColor = css;
}
