import 'package:flutter/material.dart';
import '../theme/rpg_theme.dart';

class VoiceRecordingOverlay extends StatefulWidget {
  final Function(String audioPath, int duration) onSendVoice;
  final VoidCallback onCancel;
  final int recordingDuration;

  const VoiceRecordingOverlay({
    super.key,
    required this.onSendVoice,
    required this.onCancel,
    required this.recordingDuration,
  });

  @override
  State<VoiceRecordingOverlay> createState() => _VoiceRecordingOverlayState();
}

class _VoiceRecordingOverlayState extends State<VoiceRecordingOverlay>
    with SingleTickerProviderStateMixin {
  double _cancelDragOffset = 0.0; // horizontal drag for cancel gesture
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes}:${secs.toString().padLeft(2, '0')}';
  }

  Color _getTimerColor() {
    if (widget.recordingDuration >= 118) return Colors.red; // 1:58+
    if (widget.recordingDuration >= 110) return Colors.yellow; // 1:50+
    return Colors.white;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _cancelDragOffset += details.delta.dx;
      if (_cancelDragOffset < -100) {
        // Trigger cancel
        widget.onCancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = RpgTheme.isDark(context);

    return GestureDetector(
      onHorizontalDragUpdate: _onHorizontalDragUpdate,
      child: Material(
        color: isDark ? Colors.black87 : Colors.white.withOpacity(0.95),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Timer display
              Text(
                _formatDuration(widget.recordingDuration),
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: _getTimerColor(),
                ),
              ),
              const SizedBox(height: 32),

              // Waveform placeholder (will add in next task)
              Container(
                height: 100,
                width: MediaQuery.of(context).size.width * 0.8,
                color: Colors.grey.withOpacity(0.2),
                child: const Center(child: Text('Waveform here')),
              ),

              const SizedBox(height: 48),

              // Pulsing mic icon
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return Transform.scale(
                    scale: 1.0 + (_pulseController.value * 0.2),
                    child: Icon(
                      Icons.mic,
                      size: 80,
                      color: Colors.red.withOpacity(0.8 + (_pulseController.value * 0.2)),
                    ),
                  );
                },
              ),

              const SizedBox(height: 48),

              // Swipe to cancel instruction
              Opacity(
                opacity: _cancelDragOffset < 0 ? 1.0 - (_cancelDragOffset.abs() / 100) : 1.0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.arrow_back, color: Colors.red.withOpacity(0.7)),
                    const SizedBox(width: 8),
                    Text(
                      'Swipe left to cancel',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black54,
                        fontSize: 16,
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
