/// Non-web build: there is no in-place process restart, so the caller keeps
/// the state it already has. See `app_relaunch.dart` for why nothing is faked
/// here.
bool canRelaunchApp() => false;

void relaunchApp() {}
