import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

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
    (key: '2h', seconds: 7200),
    (key: '6h', seconds: 21600),
    (key: '12h', seconds: 43200),
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
    final l10n = AppLocalizations.of(context);
    final isEmpty = _controller.text.trim().isEmpty;

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
              const Text('\u26db\ufe0f', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text(
                l10n.antiQuantumNoteTitle,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Navigator.of(context).pop(),
                color: Colors.grey,
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
                borderSide: BorderSide(color: Colors.grey.shade700),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade700),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: _ttlOptions.map((opt) {
              final selected = _selectedTtl == opt.seconds;
              final label = switch (opt.key) {
                '2h' => l10n.antiQuantumNoteTtl2h,
                '6h' => l10n.antiQuantumNoteTtl6h,
                '12h' => l10n.antiQuantumNoteTtl12h,
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
                        color: selected ? const Color(0xFFC0392B) : theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected ? const Color(0xFFC0392B) : Colors.grey.shade700,
                        ),
                      ),
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: selected ? Colors.white : Colors.grey,
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
                backgroundColor: const Color(0xFFC0392B),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(l10n.antiQuantumNoteGenerateAndSend, style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              l10n.antiQuantumNoteFooter,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}
