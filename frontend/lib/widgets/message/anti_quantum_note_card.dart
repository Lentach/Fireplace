import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/rpg_theme.dart';
import '../../utils/anti_quantum_note_link.dart';

const Color _kNoteRed = Color(0xFFC0392B);
const Color _kNoteRedDark = Color(0xFF922B21);

/// In-chat banner for an Anti-Quantum Note link. Replaces the raw URL text
/// (and any link-preview card) inside the TEXT bubble; tapping opens the
/// one-time reveal page exactly like tapping the link did.
///
/// When the link carries an `e=` expiry (see anti_quantum_note_link.dart) the
/// banner shows a live self-destruct countdown, and flips to a "destroyed"
/// state at the exact server-side death moment — fully client-side.
class AntiQuantumNoteCard extends StatefulWidget {
  final String noteUrl;
  final bool isMine;
  final Color textColor;
  final bool isDark;
  final double maxWidth;

  const AntiQuantumNoteCard({
    super.key,
    required this.noteUrl,
    required this.isMine,
    required this.textColor,
    required this.isDark,
    required this.maxWidth,
  });

  @override
  State<AntiQuantumNoteCard> createState() => _AntiQuantumNoteCardState();
}

class _AntiQuantumNoteCardState extends State<AntiQuantumNoteCard> {
  DateTime? _expiresAt;
  Timer? _ticker;

  bool get _destroyed =>
      _expiresAt != null && !_expiresAt!.isAfter(DateTime.now());

  @override
  void initState() {
    super.initState();
    _expiresAt = parseAntiQuantumNoteLink(widget.noteUrl)?.expiresAt;
    _armTicker();
  }

  @override
  void didUpdateWidget(covariant AntiQuantumNoteCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.noteUrl != widget.noteUrl) {
      _expiresAt = parseAntiQuantumNoteLink(widget.noteUrl)?.expiresAt;
      _armTicker();
    }
  }

  void _armTicker() {
    _ticker?.cancel();
    if (_expiresAt == null || _destroyed) return;
    // Minute granularity is what the label shows; re-arm each tick so the
    // final tick lands on the destruction moment, not up to 59s past it.
    final remaining = _expiresAt!.difference(DateTime.now());
    final tickIn = remaining.inSeconds <= 60
        ? remaining + const Duration(seconds: 1)
        : Duration(seconds: (remaining.inSeconds % 60) + 1);
    _ticker = Timer(tickIn, () {
      if (!mounted) return;
      setState(() {});
      _armTicker();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _countdownLabel() {
    final remaining = _expiresAt!.difference(DateTime.now());
    final h = remaining.inHours;
    final m = remaining.inMinutes.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    if (remaining.inMinutes >= 1) return '${m}m';
    return '<1m';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final destroyed = _destroyed;
    final cardBg = widget.isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.04);
    final subtitleColor = widget.isMine
        ? widget.textColor.withValues(alpha: 0.75)
        : (widget.isDark ? RpgTheme.timeColorDark : RpgTheme.textSecondaryLight);
    final badgeGradient = destroyed
        ? LinearGradient(
            colors: [Colors.grey.shade600, Colors.grey.shade800],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : const LinearGradient(
            colors: [_kNoteRed, _kNoteRedDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: widget.maxWidth),
      child: GestureDetector(
        key: const Key('anti-quantum-note-card'),
        onTap: () => launchUrl(
          Uri.parse(widget.noteUrl),
          mode: LaunchMode.externalApplication,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(10),
          ),
          clipBehavior: Clip.hardEdge,
          // No IntrinsicHeight: it measures text at unconstrained width, so a
          // wrapped 2-line subtitle overflows the frozen height. The Stack lets
          // the Row size itself; the accent bar is pinned to the full height.
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 3,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: destroyed
                        ? LinearGradient(colors: [
                            Colors.grey.shade600,
                            Colors.grey.shade800,
                          ])
                        : const LinearGradient(
                            colors: [_kNoteRed, _kNoteRedDark],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      child: Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: badgeGradient,
                          boxShadow: destroyed
                              ? null
                              : [
                                  BoxShadow(
                                    color: _kNoteRed.withValues(alpha: 0.35),
                                    blurRadius: 6,
                                  ),
                                ],
                        ),
                        child: Icon(
                          destroyed
                              ? Icons.local_fire_department
                              : Icons.lock_outline,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.only(
                          right: 12,
                          top: 8,
                          bottom: 8,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.antiQuantumNoteTitle,
                              style: RpgTheme.bodyFont(
                                fontSize: 13,
                                color: widget.textColor,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              destroyed
                                  ? l10n.antiQuantumNoteCardDestroyed
                                  : l10n.antiQuantumNoteCardSubtitle,
                              style: RpgTheme.bodyFont(
                                fontSize: 11,
                                color: subtitleColor,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (!destroyed && _expiresAt != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                l10n.antiQuantumNoteCardCountdown(
                                  _countdownLabel(),
                                ),
                                key: const Key(
                                  'anti-quantum-note-countdown',
                                ),
                                style: RpgTheme.bodyFont(
                                  fontSize: 11,
                                  // Brand red drowns on dark bubbles; use the
                                  // lightened variant there for contrast.
                                  color: widget.isDark
                                      ? const Color(0xFFE9776B)
                                      : _kNoteRed,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
