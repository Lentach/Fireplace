import 'package:flutter/material.dart';

/// Height of an [lines]-line caption drawn with [style] in [context].
///
/// Both honeycombs — the Contacts board (`contact_network_view.dart`) and the
/// Chats picker (`chat_honeycomb_picker.dart`) — reserve caption space in
/// their own layout maths, so they have to agree on how tall a caption is.
///
/// **Pass the bare style; this does the merge.** That is the whole point of
/// the helper: `Text` merges its style into the ambient `DefaultTextStyle`,
/// which carries a line height the bare style omits, so measuring the bare
/// style under-reports by roughly 4px per line. At one line that hid inside
/// the Contacts board's 9px row slack; at two it overflowed the caption box
/// outright. Doing the merge here means a third caller cannot reintroduce it.
///
/// Ceil plus 1px of slack, because fractional text heights clip glyph
/// descenders at accessibility text scales.
double measureCaptionHeight(
  BuildContext context,
  TextStyle style, {
  int lines = 1,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: List<String>.filled(lines, 'Ag').join('\n'),
      style: DefaultTextStyle.of(context).style.merge(style),
    ),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  return painter.size.height.ceilToDouble() + 1;
}
