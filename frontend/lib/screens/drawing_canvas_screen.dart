import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:cross_file/cross_file.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../theme/rpg_theme.dart';
import '../widgets/top_snackbar.dart';

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
      showTopSnackBar(context, 'Canvas is empty');
      return;
    }

    // Capture providers before async operations
    final chat = context.read<ChatProvider>();
    final auth = context.read<AuthProvider>();

    try {
      // Show loading
      if (mounted) {
        showTopSnackBar(context, 'Uploading drawing...');
      }

      // Capture canvas as image
      final boundary = _canvasKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      // Save to temporary file
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${tempDir.path}/drawing_$timestamp.png');
      await file.writeAsBytes(pngBytes);

      // Convert to XFile
      final xFile = XFile(file.path);

      if (chat.activeConversationId == null) {
        if (mounted) {
          showTopSnackBar(context, 'No active conversation');
        }
        return;
      }

      final conv = chat.conversations
          .firstWhere((c) => c.id == chat.activeConversationId);
      final recipientId = chat.getOtherUserId(conv);

      await chat.sendImageMessage(auth.token!, xFile, recipientId);

      // Clean up temp file
      await file.delete();

      if (mounted) {
        Navigator.pop(context);
        showTopSnackBar(context, 'Drawing sent!');
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, 'Upload failed: $e', backgroundColor: Colors.red);
      }
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
