import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/utils/web_document_background.dart';

void main() {
  group('webDocumentBackgroundCss', () {
    test('drops the alpha channel (document backgrounds are opaque)', () {
      // Same RGB as the dark scaffold but half-transparent -> alpha ignored.
      expect(webDocumentBackgroundCss(const Color(0x8017181A)), '#17181a');
      expect(webDocumentBackgroundCss(const Color(0x00FFFFFF)), '#ffffff');
    });

    test('zero-pads to six lowercase hex digits', () {
      expect(webDocumentBackgroundCss(const Color(0xFF00010A)), '#00010a');
      expect(webDocumentBackgroundCss(const Color(0xFF0000FF)), '#0000ff');
    });

    test('pure white and pure black round-trip', () {
      expect(webDocumentBackgroundCss(const Color(0xFFFFFFFF)), '#ffffff');
      expect(webDocumentBackgroundCss(const Color(0xFF000000)), '#000000');
    });

    // The real contract: web/index.html paints the document for FIRST PAINT
    // (before Flutter boots) and must match the default 'dark' theme scaffold,
    // otherwise the Android keyboard-hide reclaimed strip flashes the wrong
    // color. Parse the actual file so drift on either side breaks the test.
    // CSS hex is case-insensitive, so compare lowercased.
    test('index.html first-paint background matches the default dark scaffold',
        () {
      final html = File('web/index.html').readAsStringSync();
      final match =
          RegExp(r'background-color:\s*(#[0-9a-fA-F]{6})').firstMatch(html);
      expect(
        match,
        isNotNull,
        reason: 'index.html must ship a static html/body background-color',
      );
      final indexCss = match!.group(1)!.toLowerCase();

      expect(indexCss, webDocumentBackgroundCss(RpgTheme.backgroundDarkGray));
      expect(indexCss, '#17181a'); // documented default
    });
  });
}
