import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../theme/rpg_theme.dart';
import '../utils/jumbo_emoji.dart';

class AntiQuantumNoteDialog extends StatefulWidget {
  final Future<void> Function(String content, int expiresInSeconds) onSend;

  const AntiQuantumNoteDialog({super.key, required this.onSend});

  @override
  State<AntiQuantumNoteDialog> createState() => _AntiQuantumNoteDialogState();
}

class _AntiQuantumNoteDialogState extends State<AntiQuantumNoteDialog> {
  final _controller = TextEditingController();
  int _selectedTtl = 21600; // 6h default
  bool _sending = false;

  static const _ttlOptions = [
    (key: '1h', seconds: 3600),
    (key: '6h', seconds: 21600),
    (key: '12h', seconds: 43200),
    (key: '24h', seconds: 86400),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleSend() async {
    if (_sending || _controller.text.trim().isEmpty) return;
    setState(() => _sending = true);
    try {
      await widget.onSend(_controller.text.trim(), _selectedTtl);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final fc = FireplaceColors.of(context);
    final l10n = AppLocalizations.of(context);
    final isEmpty = _controller.text.trim().isEmpty;
    // Readable label on the primary fill — some theme accents are bright
    // (#2AABEE, #5C9EAD) where white fails 4.5:1.
    final onAccent = RpgTheme.readableOn(colorScheme.primary);

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '\u26db\ufe0f',
                style: withEmojiFont(const TextStyle(fontSize: 20)),
              ),
              const SizedBox(width: 8),
              Text(
                l10n.antiQuantumNoteTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Navigator.of(context).pop(),
                color: fc.mutedText,
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            maxLines: 4,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: l10n.antiQuantumNoteHint,
              filled: true,
              fillColor: theme.colorScheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: fc.borderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: fc.borderColor),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: _ttlOptions.map((opt) {
              final selected = _selectedTtl == opt.seconds;
              final label = switch (opt.key) {
                '1h' => l10n.antiQuantumNoteTtl1h,
                '6h' => l10n.antiQuantumNoteTtl6h,
                '12h' => l10n.antiQuantumNoteTtl12h,
                '24h' => l10n.antiQuantumNoteTtl24h,
                _ => opt.key,
              };
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedTtl = opt.seconds),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: selected
                            ? colorScheme.primary
                            : theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected
                              ? colorScheme.primary
                              : fc.borderColor,
                        ),
                      ),
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: selected ? onAccent : fc.mutedText,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (isEmpty || _sending) ? null : _handleSend,
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: onAccent,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: _sending
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: onAccent,
                      ),
                    )
                  : Text(
                      l10n.antiQuantumNoteGenerateAndSend,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              l10n.antiQuantumNoteFooter,
              style: TextStyle(fontSize: 10, color: fc.mutedText),
            ),
          ),
        ],
      ),
    );
  }
}
