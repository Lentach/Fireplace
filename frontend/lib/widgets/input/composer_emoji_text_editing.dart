import 'package:characters/characters.dart';
import 'package:flutter/services.dart';

TextEditingValue insertEmojiAtSelection(TextEditingValue value, String emoji) {
  final text = value.text;
  final selection = value.selection;
  final start = (selection.isValid ? selection.start : text.length).clamp(
    0,
    text.length,
  );
  final end = (selection.isValid ? selection.end : text.length).clamp(
    0,
    text.length,
  );
  final newText = text.replaceRange(start, end, emoji);
  return value.copyWith(
    text: newText,
    selection: TextSelection.collapsed(offset: start + emoji.length),
    composing: TextRange.empty,
  );
}

TextEditingValue deletePreviousEmojiGrapheme(TextEditingValue value) {
  final text = value.text;
  final selection = value.selection;
  if (!selection.isValid) return value;

  if (!selection.isCollapsed) {
    final start = selection.start.clamp(0, text.length);
    final end = selection.end.clamp(0, text.length);
    return value.copyWith(
      text: text.replaceRange(start, end, ''),
      selection: TextSelection.collapsed(offset: start),
      composing: TextRange.empty,
    );
  }

  final caret = selection.baseOffset.clamp(0, text.length);
  if (caret == 0) return value.copyWith(composing: TextRange.empty);

  final beforeCaret = text.substring(0, caret);
  final afterCaret = text.substring(caret);
  final newBeforeCaret = beforeCaret.characters.skipLast(1).toString();
  return value.copyWith(
    text: newBeforeCaret + afterCaret,
    selection: TextSelection.collapsed(offset: newBeforeCaret.length),
    composing: TextRange.empty,
  );
}
