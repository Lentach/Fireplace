import 'package:flutter/widgets.dart';

/// Fallback impl for platforms with neither `dart:io` nor `dart:js_interop`.
/// Scanning is never supported here; the typed-code field is the flow.
Future<bool> linkQrScanSupported() async => false;

/// See `link_qr_scanner.dart` for the shared contract.
class LinkQrScanner extends StatefulWidget {
  const LinkQrScanner({super.key, required this.onCode, this.onUnsupported});

  final void Function(String code) onCode;
  final VoidCallback? onUnsupported;

  @override
  State<LinkQrScanner> createState() => _LinkQrScannerState();
}

class _LinkQrScannerState extends State<LinkQrScanner> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onUnsupported?.call();
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
