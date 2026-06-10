import 'package:web/web.dart' as web;

/// Read `?notify_conv=<id>` from the current URL.
/// Returns the conversation ID as an int, or null if absent/invalid.
/// Called once at app start before [runApp].
int? consumeNotifyConvParam() {
  final raw = Uri.base.queryParameters['notify_conv'];
  if (raw == null) return null;
  return int.tryParse(raw);
}

/// Strip `?notify_conv=<id>` from the address bar so a manual page refresh
/// does not re-trigger the deep-link navigation.
void stripNotifyConvParam() {
  if (!Uri.base.queryParameters.containsKey('notify_conv')) return;
  final params = Map<String, String>.from(Uri.base.queryParameters)
    ..remove('notify_conv');
  final stripped = Uri.base.replace(queryParameters: params.isEmpty ? null : params);
  web.window.history.replaceState(null, '', stripped.toString());
}
