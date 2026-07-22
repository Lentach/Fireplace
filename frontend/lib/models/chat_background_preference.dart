enum ChatBackgroundPreference { themeDefault, plain, glyphs }

enum ChatBackgroundLayer { plain, glyphs, starfield }

ChatBackgroundLayer resolveChatBackground({
  required ChatBackgroundPreference preference,
  required bool isCosmicTheme,
}) {
  return switch (preference) {
    ChatBackgroundPreference.themeDefault =>
      isCosmicTheme ? ChatBackgroundLayer.starfield : ChatBackgroundLayer.plain,
    ChatBackgroundPreference.plain => ChatBackgroundLayer.plain,
    ChatBackgroundPreference.glyphs => ChatBackgroundLayer.glyphs,
  };
}
