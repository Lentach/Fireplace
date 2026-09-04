import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../providers/passcode_provider.dart' show kPasscodeMinAlphanumericLength;
import '../services/passcode_store.dart';
import '../theme/rpg_theme.dart';
import 'hex_avatar.dart' show hexPath, kHexWidthRatio;

/// One passcode entry surface, used for every step of the feature: unlocking
/// the app, setting a code, repeating it, and confirming the current one
/// before a change or a disable.
///
/// The numeric modes draw their OWN keypad instead of raising the system
/// keyboard — the same reason Zangi and Telegram do: a `TextField` on this
/// screen means an IME with clipboard, autocorrect and (on iOS PWA) a
/// viewport that pans the whole page, and the lock screen must not depend on
/// any of that. The custom alphanumeric mode does use a real field, because
/// letters need one.
class PasscodeEntryView extends StatefulWidget {
  const PasscodeEntryView({
    super.key,
    required this.mode,
    required this.title,
    required this.onSubmit,
    this.subtitle,
    this.errorText,
    this.footer,
    this.onOptions,
    this.enabled = true,
  });

  final PasscodeMode mode;
  final String title;
  final String? subtitle;

  /// Called with the finished code: automatically at the last digit for the
  /// numeric modes, on the submit button for the alphanumeric one. The view
  /// clears itself as soon as the future is handed back, so a wrong code
  /// always leaves an empty field rather than a half-erased one.
  final Future<void> Function(String code) onSubmit;

  final String? errorText;

  /// Extra content under the keypad (the "forgot passcode" door).
  final Widget? footer;

  /// Shows the "Passcode Options" link when non-null.
  final VoidCallback? onOptions;

  /// False while a cooldown is running: taps are ignored and the keypad dims.
  final bool enabled;

  @override
  State<PasscodeEntryView> createState() => _PasscodeEntryViewState();
}

class _PasscodeEntryViewState extends State<PasscodeEntryView> {
  final TextEditingController _text = TextEditingController();
  String _digits = '';
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  int get _length => widget.mode.fixedLength ?? 0;

  void _append(String digit) {
    if (!widget.enabled || _busy) return;
    if (_digits.length >= _length) return;
    setState(() => _digits += digit);
    if (_digits.length == _length) _submit(_digits);
  }

  void _backspace() {
    if (!widget.enabled || _busy || _digits.isEmpty) return;
    setState(() => _digits = _digits.substring(0, _digits.length - 1));
  }

  Future<void> _submit(String code) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onSubmit(code);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _digits = '';
          _text.clear();
        });
      }
    }
  }

  void _submitCustom() {
    if (!widget.enabled || _busy) return;
    final code = _text.text;
    if (code.trim().length < kPasscodeMinAlphanumericLength) {
      setState(() {});
      return;
    }
    _submit(code);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final colors = FireplaceColors.of(context);
    final l10n = AppLocalizations.of(context);
    final tooShort =
        widget.mode == PasscodeMode.alphanumeric &&
        _text.text.isNotEmpty &&
        _text.text.trim().length < kPasscodeMinAlphanumericLength;
    final error = widget.errorText ?? (tooShort ? l10n.passcodeTooShort : null);

    return SafeArea(
      // Scrollable and centered rather than a Column with Spacers: the
      // keypad, an error line and the recovery panel together exceed a short
      // viewport (a 600px-tall web window, a landscape phone), and an
      // overflowing lock screen would put the recovery button off-screen —
      // unreachable exactly when the user needs it.
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight - 24,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: RpgTheme.bodyFont(
                fontSize: 20,
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (widget.subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                widget.subtitle!,
                key: const Key('passcode-subtitle'),
                textAlign: TextAlign.center,
                style: RpgTheme.bodyFont(fontSize: 13, color: colors.mutedText),
              ),
            ],
            const SizedBox(height: 28),
            if (widget.mode.isNumeric)
              _PasscodeDots(length: _length, filled: _digits.length)
            else
              _customField(colorScheme, colors, l10n),
            SizedBox(
              // Reserved so an error appearing never shifts the keypad under
              // the user's finger.
              height: 40,
              child: Center(
                child: error == null
                    ? null
                    : Text(
                        error,
                        key: const Key('passcode-error'),
                        textAlign: TextAlign.center,
                        style: RpgTheme.bodyFont(
                          fontSize: 13,
                          color: colorScheme.error,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 24),
            if (widget.onOptions != null)
              TextButton(
                key: const Key('passcode-options-link'),
                onPressed: widget.enabled && !_busy ? widget.onOptions : null,
                child: Text(
                  l10n.passcodeOptions,
                  style: RpgTheme.bodyFont(
                    fontSize: 15,
                    color: colorScheme.primary,
                  ),
                ),
              ),
            if (widget.mode.isNumeric) ...[
              const SizedBox(height: 8),
              _Keypad(
                enabled: widget.enabled && !_busy,
                onDigit: _append,
                onBackspace: _backspace,
              ),
            ],
            if (widget.footer != null) ...[
              const SizedBox(height: 12),
              widget.footer!,
            ],
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _customField(
    ColorScheme colorScheme,
    FireplaceColors colors,
    AppLocalizations l10n,
  ) {
    return Column(
      children: [
        TextField(
          key: const Key('passcode-text-field'),
          controller: _text,
          autofocus: true,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          enabled: widget.enabled && !_busy,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _submitCustom(),
          style: RpgTheme.bodyFont(fontSize: 16, color: colorScheme.onSurface),
          decoration: InputDecoration(
            hintText: l10n.passcodeCustomHint,
            hintStyle: RpgTheme.bodyFont(
              fontSize: 15,
              color: colors.mutedText,
            ),
            filled: true,
            fillColor: colors.inputBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: colors.borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: colors.borderColor),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            key: const Key('passcode-submit'),
            onPressed: widget.enabled && !_busy ? _submitCustom : null,
            child: Text(l10n.passcodeConfirmAction),
          ),
        ),
      ],
    );
  }
}

/// One small pointy-top hex per expected digit — the app's shape language, in
/// place of Zangi's circles.
class _PasscodeDots extends StatelessWidget {
  const _PasscodeDots({required this.length, required this.filled});

  final int length;
  final int filled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final colors = FireplaceColors.of(context);
    return Row(
      key: const Key('passcode-dots'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7),
            child: SizedBox(
              key: Key(
                i < filled
                    ? 'passcode-dot-filled-$i'
                    : 'passcode-dot-empty-$i',
              ),
              width: 14 * kHexWidthRatio,
              height: 14,
              child: CustomPaint(
                painter: _HexDotPainter(
                  fill: i < filled ? colorScheme.primary : null,
                  border: i < filled ? colorScheme.primary : colors.mutedText,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _HexDotPainter extends CustomPainter {
  const _HexDotPainter({required this.border, this.fill});

  final Color? fill;
  final Color border;

  @override
  void paint(Canvas canvas, Size size) {
    final path = hexPath(size.center(Offset.zero), size.height / 2 - 0.75);
    if (fill != null) {
      canvas.drawPath(path, Paint()..color = fill!);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = border,
    );
  }

  @override
  bool shouldRepaint(_HexDotPainter old) =>
      old.fill != fill || old.border != border;
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.enabled,
    required this.onDigit,
    required this.onBackspace,
  });

  final bool enabled;
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  /// Letter rows are the phone-keypad convention every user already knows
  /// (and what Zangi shows); they are decorative, never input.
  static const Map<String, String> _letters = {
    '2': 'ABC',
    '3': 'DEF',
    '4': 'GHI',
    '5': 'JKL',
    '6': 'MNO',
    '7': 'PQRS',
    '8': 'TUV',
    '9': 'WXYZ',
  };

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Column(
        children: [
          for (final row in const [
            ['1', '2', '3'],
            ['4', '5', '6'],
            ['7', '8', '9'],
          ])
            _row([
              for (final d in row)
                _HexKey(
                  digit: d,
                  letters: _letters[d],
                  enabled: enabled,
                  onTap: () => onDigit(d),
                ),
            ]),
          _row([
            const SizedBox(width: 76, height: 66),
            _HexKey(
              digit: '0',
              enabled: enabled,
              onTap: () => onDigit('0'),
            ),
            SizedBox(
              width: 76,
              height: 66,
              child: Semantics(
                button: true,
                label: MaterialLocalizations.of(context).deleteButtonTooltip,
                child: IconButton(
                  key: const Key('passcode-backspace'),
                  onPressed: enabled ? onBackspace : null,
                  icon: const Icon(Icons.backspace_outlined, size: 22),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _row(List<Widget> children) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (final child in children)
        Padding(
          padding: const EdgeInsets.all(4),
          child: child,
        ),
    ],
  );
}

class _HexKey extends StatefulWidget {
  const _HexKey({
    required this.digit,
    required this.enabled,
    required this.onTap,
    this.letters,
  });

  final String digit;
  final String? letters;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_HexKey> createState() => _HexKeyState();
}

class _HexKeyState extends State<_HexKey> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final colors = FireplaceColors.of(context);
    return Semantics(
      button: true,
      label: widget.digit,
      child: GestureDetector(
        key: Key('passcode-key-${widget.digit}'),
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: widget.enabled ? () => setState(() => _pressed = false) : null,
        onTap: widget.enabled
            ? () {
                setState(() => _pressed = false);
                HapticFeedback.selectionClick();
                widget.onTap();
              }
            : null,
        child: SizedBox(
          width: 76,
          height: 66,
          child: CustomPaint(
            painter: _HexKeyPainter(
              fill: _pressed ? colorScheme.primary.withValues(alpha: 0.18) : null,
              border: _pressed ? colorScheme.primary : colors.borderColor,
            ),
            // Painted glyphs only: the outer Semantics already announces the
            // digit, so leaving these visible to the a11y tree read "1 1"
            // (and "2 2 ABC") on the real build.
            child: ExcludeSemantics(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.digit,
                    style: RpgTheme.bodyFont(
                      fontSize: 24,
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (widget.letters != null)
                    Text(
                      widget.letters!,
                      style: RpgTheme.bodyFont(
                        fontSize: 9,
                        color: colors.mutedText,
                        fontWeight: FontWeight.w600,
                      ).copyWith(letterSpacing: 1.4),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HexKeyPainter extends CustomPainter {
  const _HexKeyPainter({required this.border, this.fill});

  final Color? fill;
  final Color border;

  @override
  void paint(Canvas canvas, Size size) {
    // Pointy-top hex sized to the box height, matching the honeycomb lattice
    // used by the Chats avatars and the Contacts board.
    final path = hexPath(size.center(Offset.zero), size.height / 2 - 0.75);
    if (fill != null) {
      canvas.drawPath(path, Paint()..color = fill!);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..color = border,
    );
  }

  @override
  bool shouldRepaint(_HexKeyPainter old) =>
      old.fill != fill || old.border != border;
}
