import 'package:web/web.dart' as web;

/// Clears accidental document scroll from mobile browsers scroll-into-view on focus.
void resetWebDocumentScroll() {
  final root = web.document.documentElement;
  if (root != null) {
    root.scrollTop = 0;
    root.scrollLeft = 0;
  }
  final body = web.document.body;
  if (body != null) {
    body.scrollTop = 0;
    body.scrollLeft = 0;
  }
}
