import 'package:web/web.dart' as web;

void resetWebDocumentScroll() {
  final root = web.document.documentElement;
  if (root case web.HTMLElement el) {
    el.scrollTop = 0;
    el.scrollLeft = 0;
  }
  final body = web.document.body;
  if (body != null) {
    body.scrollTop = 0;
    body.scrollLeft = 0;
  }
}
