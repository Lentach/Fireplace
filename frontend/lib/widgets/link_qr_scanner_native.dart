import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Native impl of `link_qr_scanner.dart`: `mobile_scanner` (CameraX/ML Kit on
/// Android, AVFoundation/Vision on iOS), restricted to QR codes.
Future<bool> linkQrScanSupported() async =>
    Platform.isAndroid || Platform.isIOS;

/// See `link_qr_scanner.dart` for the shared contract.
class LinkQrScanner extends StatefulWidget {
  const LinkQrScanner({super.key, required this.onCode, this.onUnsupported});

  final void Function(String code) onCode;
  final VoidCallback? onUnsupported;

  @override
  State<LinkQrScanner> createState() => _LinkQrScannerState();
}

class _LinkQrScannerState extends State<LinkQrScanner> {
  MobileScannerController? _controller;

  /// `onCode` fires at most once; `onUnsupported` likewise (the errorBuilder
  /// runs on every rebuild while the controller stays errored).
  bool _delivered = false;
  bool _reportedUnsupported = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid || Platform.isIOS) {
      _controller = MobileScannerController(
        formats: const [BarcodeFormat.qrCode],
      );
    } else {
      // Desktop native (tests run here too): no camera pipeline — say so
      // once the frame exists and render nothing.
      WidgetsBinding.instance.addPostFrameCallback((_) => _unsupported());
    }
  }

  void _unsupported() {
    if (_reportedUnsupported || !mounted) return;
    _reportedUnsupported = true;
    widget.onUnsupported?.call();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_delivered) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null || value.isEmpty) continue;
      _delivered = true;
      widget.onCode(value);
      return;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();
    return MobileScanner(
      controller: controller,
      onDetect: _onDetect,
      // Camera denied / unavailable: fall back to the typed field (the
      // caller's job) instead of mobile_scanner's default error icon.
      errorBuilder: (context, error) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _unsupported());
        return const SizedBox.shrink();
      },
    );
  }
}
