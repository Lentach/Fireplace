// Web-specific implementation
import 'package:web/web.dart' as web;

String getBaseUrlForPlatform() {
  // Use window.location.host for web
  // This gets the actual hostname from browser URL
  final host = web.window.location.host.split(':')[0]; // Remove port if present
  return 'http://$host:3000';
}
