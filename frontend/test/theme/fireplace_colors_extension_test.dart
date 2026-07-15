import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/theme/rpg_theme.dart';

/// Behavioral lock for FireplaceColors.copyWith/lerp. Both were no-ops until
/// 2026-07-15 (copyWith ignored everything; lerp snapped instead of
/// interpolating during AnimatedTheme theme switches).
void main() {
  const a = FireplaceColors(
    inputBg: Color(0xFF101010),
    convItemBorder: Color(0xFF111111),
    convItemBg: Color(0xFF121212),
    messagesAreaBg: Color(0xFF131313),
    mineMsgBg: Color(0xFF141414),
    theirsMsgBg: Color(0xFF151515),
    settingsTileBg: Color(0xFF161616),
    settingsTileBorder: Color(0xFF171717),
    tabBorder: Color(0xFF181818),
    borderColor: Color(0xFF191919),
    mutedText: Color(0xFF1A1A1A),
  );
  const b = FireplaceColors(
    inputBg: Color(0xFFF0F0F0),
    convItemBorder: Color(0xFFF1F1F1),
    convItemBg: Color(0xFFF2F2F2),
    messagesAreaBg: Color(0xFFF3F3F3),
    mineMsgBg: Color(0xFFF4F4F4),
    theirsMsgBg: Color(0xFFF5F5F5),
    settingsTileBg: Color(0xFFF6F6F6),
    settingsTileBorder: Color(0xFFF7F7F7),
    tabBorder: Color(0xFFF8F8F8),
    borderColor: Color(0xFFF9F9F9),
    mutedText: Color(0xFFFAFAFA),
  );

  void expectAllFields(FireplaceColors actual, FireplaceColors expected) {
    expect(actual.inputBg, expected.inputBg);
    expect(actual.convItemBorder, expected.convItemBorder);
    expect(actual.convItemBg, expected.convItemBg);
    expect(actual.messagesAreaBg, expected.messagesAreaBg);
    expect(actual.mineMsgBg, expected.mineMsgBg);
    expect(actual.theirsMsgBg, expected.theirsMsgBg);
    expect(actual.settingsTileBg, expected.settingsTileBg);
    expect(actual.settingsTileBorder, expected.settingsTileBorder);
    expect(actual.tabBorder, expected.tabBorder);
    expect(actual.borderColor, expected.borderColor);
    expect(actual.mutedText, expected.mutedText);
  }

  group('FireplaceColors.copyWith', () {
    test('no arguments preserves every field', () {
      expectAllFields(a.copyWith(), a);
    });

    test('overrides only the named field', () {
      const override = Color(0xFF123456);
      final copy = a.copyWith(mineMsgBg: override);
      expect(copy.mineMsgBg, override);
      expect(copy.inputBg, a.inputBg);
      expect(copy.theirsMsgBg, a.theirsMsgBg);
      expect(copy.mutedText, a.mutedText);
    });
  });

  group('FireplaceColors.lerp', () {
    test('endpoints return start/end colors', () {
      expectAllFields(a.lerp(b, 0), a);
      expectAllFields(a.lerp(b, 1), b);
    });

    test('midpoint actually interpolates every field (old no-op snapped)', () {
      final mid = a.lerp(b, 0.5);
      expectAllFields(
        mid,
        FireplaceColors(
          inputBg: Color.lerp(a.inputBg, b.inputBg, 0.5)!,
          convItemBorder: Color.lerp(a.convItemBorder, b.convItemBorder, 0.5)!,
          convItemBg: Color.lerp(a.convItemBg, b.convItemBg, 0.5)!,
          messagesAreaBg: Color.lerp(a.messagesAreaBg, b.messagesAreaBg, 0.5)!,
          mineMsgBg: Color.lerp(a.mineMsgBg, b.mineMsgBg, 0.5)!,
          theirsMsgBg: Color.lerp(a.theirsMsgBg, b.theirsMsgBg, 0.5)!,
          settingsTileBg: Color.lerp(a.settingsTileBg, b.settingsTileBg, 0.5)!,
          settingsTileBorder: Color.lerp(
            a.settingsTileBorder,
            b.settingsTileBorder,
            0.5,
          )!,
          tabBorder: Color.lerp(a.tabBorder, b.tabBorder, 0.5)!,
          borderColor: Color.lerp(a.borderColor, b.borderColor, 0.5)!,
          mutedText: Color.lerp(a.mutedText, b.mutedText, 0.5)!,
        ),
      );
      expect(mid.mineMsgBg, isNot(a.mineMsgBg));
      expect(mid.mineMsgBg, isNot(b.mineMsgBg));
    });

    test('lerp against null falls back to this', () {
      expect(a.lerp(null, 0.5), same(a));
    });
  });
}
