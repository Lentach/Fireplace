// Web-specific implementation
import 'dart:html' as html;

String getBaseUrlForPlatform() {
  // Use window.location.host for web
  // This gets the actual hostname from browser URL
  final host = html.window.location.host.split(':')[0]; // Remove port if present
  return 'http://$host:3000';
}
