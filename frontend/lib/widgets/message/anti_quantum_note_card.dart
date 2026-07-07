import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../l10n/app_localizations.dart';
import '../../theme/rpg_theme.dart';

/// In-chat banner for an Anti-Quantum Note link. Replaces the raw URL text
/// (and any link-preview card) inside the TEXT bubble; tapping opens the
/// one-time reveal page exactly like tapping the link did.
class AntiQuantumNoteCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cardBg = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.04);
    final subtitleColor = isMine
        ? textColor.withValues(alpha: 0.75)
        : (isDark ? RpgTheme.timeColorDark : RpgTheme.textSecondaryLight);

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: GestureDetector(
        key: const Key('anti-quantum-note-card'),
        onTap: () => launchUrl(
          Uri.parse(noteUrl),
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
                    gradient: LinearGradient(
                      colors: [Color(0xFFC0392B), Color(0xFF922B21)],
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
                          gradient: const LinearGradient(
                            colors: [Color(0xFFC0392B), Color(0xFF922B21)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFC0392B)
                                  .withValues(alpha: 0.35),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.lock_outline,
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
                                color: textColor,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              l10n.antiQuantumNoteCardSubtitle,
                              style: RpgTheme.bodyFont(
                                fontSize: 11,
                                color: subtitleColor,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
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
