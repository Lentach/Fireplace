import 'package:flutter/material.dart';
import '../theme/rpg_theme.dart';

class DrawingCanvasScreen extends StatefulWidget {
  const DrawingCanvasScreen({super.key});

  @override
  State<DrawingCanvasScreen> createState() => _DrawingCanvasScreenState();
}

class _DrawingCanvasScreenState extends State<DrawingCanvasScreen> {
  final List<DrawnLine> _lines = [];
  DrawnLine? _currentLine;
  bool _isEraser = false;
  final GlobalKey _canvasKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final isDark = RpgTheme.isDark(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Draw'),
        actions: [
          // Eraser toggle
          IconButton(
            icon: Icon(_isEraser ? Icons.edit : Icons.auto_fix_high),
            onPressed: () {
              setState(() => _isEraser = !_isEraser);
            },
          ),
          // Clear all
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () {
              setState(() => _lines.clear());
            },
          ),
          // Send
          IconButton(
            icon: const Icon(Icons.check),
            onPressed: _sendDrawing,
          ),
        ],
      ),
      body: Column(
        children: [
          // Canvas
          Expanded(
            child: Container(
              color: Colors.white,
              child: RepaintBoundary(
                key: _canvasKey,
                child: GestureDetector(
                  onPanStart: (details) {
                    setState(() {
                      _currentLine = DrawnLine(
                        points: [details.localPosition],
                        color: _isEraser ? Colors.white : Colors.black,
                        strokeWidth: _isEraser ? 20.0 : 3.0,
                      );
                    });
                  },
                  onPanUpdate: (details) {
                    setState(() {
                      _currentLine = _currentLine?.copyWith(
                        points: [..._currentLine!.points, details.localPosition],
                      );
                    });
                  },
                  onPanEnd: (details) {
                    setState(() {
                      if (_currentLine != null) {
                        _lines.add(_currentLine!);
                        _currentLine = null;
                      }
                    });
                  },
                  child: CustomPaint(
                    painter: DrawingPainter(
                      lines: [..._lines, if (_currentLine != null) _currentLine!],
                    ),
                    size: Size.infinite,
                  ),
                ),
              ),
            ),
          ),

          // Toolbar
          Container(
            padding: const EdgeInsets.all(16),
            color: isDark ? RpgTheme.inputBg : RpgTheme.inputBgLight,
            child: Row(
              children: [
                Text(
                  _isEraser ? 'Eraser mode' : 'Draw mode',
                  style: RpgTheme.bodyFont(fontSize: 14),
                ),
                const Spacer(),
                Text(
                  'Stroke: ${_isEraser ? '20px' : '3px'}',
                  style: RpgTheme.bodyFont(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendDrawing() async {
    if (_lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Canvas is empty')),
      );
      return;
    }

    // TODO: Convert canvas to image and upload (Phase 5)
    // For now, just pop with success message
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Drawing upload coming soon')),
      );
    }
  }
}

class DrawnLine {
  final List<Offset> points;
  final Color color;
  final double strokeWidth;

  DrawnLine({
    required this.points,
    required this.color,
    required this.strokeWidth,
  });

  DrawnLine copyWith({
    List<Offset>? points,
    Color? color,
    double? strokeWidth,
  }) {
    return DrawnLine(
      points: points ?? this.points,
      color: color ?? this.color,
      strokeWidth: strokeWidth ?? this.strokeWidth,
    );
  }
}

class DrawingPainter extends CustomPainter {
  final List<DrawnLine> lines;

  DrawingPainter({required this.lines});

  @override
  void paint(Canvas canvas, Size size) {
    for (final line in lines) {
      final paint = Paint()
        ..color = line.color
        ..strokeWidth = line.strokeWidth
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      for (int i = 0; i < line.points.length - 1; i++) {
        canvas.drawLine(line.points[i], line.points[i + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(DrawingPainter oldDelegate) {
    return oldDelegate.lines != lines;
  }
}
