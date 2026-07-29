import 'content_kv.dart';

/// Web build of the opener: the legacy SharedPreferences/localStorage backend
/// is the ONLY backend there (web sealing is a separate, canary-gated effort
/// — see `content_key_canary.dart`). This file must stay free of `dart:io`.
Future<ContentKv> openPlatformContentKv() => PrefsContentKv.open();
