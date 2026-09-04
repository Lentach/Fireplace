/// Native/non-web: there is no origin storage bucket to wipe. App data lives
/// in SharedPreferences, the platform keystore and files under the app's own
/// directories, and the eraser clears those directly — plus an Android
/// uninstall genuinely removes them, unlike a PWA removal.
///
/// Returns the names of the stores that could not be cleared; nothing to do
/// here, so always empty.
Future<List<String>> wipeOriginStorage() async => const <String>[];
