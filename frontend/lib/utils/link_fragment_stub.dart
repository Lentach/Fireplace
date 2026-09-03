import 'anti_quantum_note_link.dart';

/// Stub — native builds have no URL to carry a link code.
String? consumeLinkFragment() => null;

/// No-op on native.
void stripLinkFragment() {}

/// A native install's QR points at the production web origin: the scanning
/// phone opens the PWA (or the native app via its intent filter) there.
Uri linkDeepLinkOrigin() => Uri.parse(kFireplaceProductionOrigin);
