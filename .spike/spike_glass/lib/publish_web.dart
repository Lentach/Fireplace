import 'dart:js_interop';

@JS('document.title')
external set _docTitleJS(JSString v);

void publishResult(String v) => _docTitleJS = v.toJS;
