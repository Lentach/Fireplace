import 'package:web/web.dart' as web;

/// Reads `document.visibilityState` LIVE (not via the `visibilitychange` event).
///
/// The push-reliability fix polls this: Android Chrome PWAs frequently miss or
/// delay the `visibilitychange` event on screen-lock / backgrounding, so the
/// cached `clientVisible` flag drifts to a stale `true`. Polling the actual
/// state on a heartbeat self-heals that drift even when the event never fired.
bool isDocumentVisible() => web.document.visibilityState == 'visible';
