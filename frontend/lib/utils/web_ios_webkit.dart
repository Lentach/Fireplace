import 'web_ios_webkit_stub.dart'
    if (dart.library.html) 'web_ios_webkit_web.dart' as impl;

/// True on iPhone / iPad / iPod Safari and iPadOS desktop UA (WebKit).
bool isIOSWebKit() => impl.isIOSWebKit();
