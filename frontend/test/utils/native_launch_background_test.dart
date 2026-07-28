import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/utils/web_document_background.dart';

// Native launch splashes must be pinned to the Hot Stone paper scaffold
// (the default theme since 2026-07-28). Before this, drawable-v21 used
// ?android:colorBackground — which follows OS dark mode — so dark-mode
// devices flashed a dark splash straight into the always-light front door.
// Parse the real resource files so drift on any side breaks the build.
void main() {
  test('Android colors.xml pins hot_stone_paper to the light scaffold', () {
    final xml = File(
      'android/app/src/main/res/values/colors.xml',
    ).readAsStringSync();
    final match = RegExp(
      r'<color name="hot_stone_paper">(#[0-9a-fA-F]{6})</color>',
    ).firstMatch(xml);
    expect(match, isNotNull, reason: 'hot_stone_paper resource must exist');
    expect(
      match!.group(1)!.toLowerCase(),
      webDocumentBackgroundCss(RpgTheme.backgroundLight),
    );
  });

  test('both Android launch backgrounds reference hot_stone_paper', () {
    for (final path in [
      'android/app/src/main/res/drawable/launch_background.xml',
      'android/app/src/main/res/drawable-v21/launch_background.xml',
    ]) {
      final xml = File(path).readAsStringSync();
      expect(
        xml.contains('android:drawable="@color/hot_stone_paper"'),
        isTrue,
        reason: '$path must pin the splash to the paper color '
            '(?android:colorBackground follows OS dark mode)',
      );
    }
  });

  test('iOS LaunchScreen background is the Hot Stone paper', () {
    final storyboard = File(
      'ios/Runner/Base.lproj/LaunchScreen.storyboard',
    ).readAsStringSync();
    final match = RegExp(
      r'<color key="backgroundColor" red="([\d.]+)" green="([\d.]+)" '
      r'blue="([\d.]+)"',
    ).firstMatch(storyboard);
    expect(match, isNotNull, reason: 'LaunchScreen must set backgroundColor');
    final r = (double.parse(match!.group(1)!) * 255).round();
    final g = (double.parse(match.group(2)!) * 255).round();
    final b = (double.parse(match.group(3)!) * 255).round();
    expect((r, g, b), (0xF7, 0xF4, 0xF0));
  });
}
