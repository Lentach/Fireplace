import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:package_info_plus/package_info_plus.dart';

/// Build-time metadata from `--dart-define` (set in production deploy / CI).
class AppVersionInfo {
  AppVersionInfo._({
    required this.version,
    required this.buildNumber,
    required this.gitCommit,
    required this.buildTime,
  });

  static const String _gitCommitDefine = String.fromEnvironment(
    'GIT_COMMIT',
    defaultValue: 'dev',
  );

  static const String _buildTimeDefine = String.fromEnvironment(
    'BUILD_TIME',
    defaultValue: '',
  );

  static AppVersionInfo? _cached;

  /// Clears cached instance between tests.
  @visibleForTesting
  static void debugResetForTest() {
    _cached = null;
  }

  final String version;
  final String buildNumber;
  final String gitCommit;
  final String buildTime;

  static Future<AppVersionInfo> load() async {
    if (_cached != null) return _cached!;
    final packageInfo = await PackageInfo.fromPlatform();
    _cached = AppVersionInfo._(
      version: packageInfo.version,
      buildNumber: packageInfo.buildNumber,
      gitCommit: _gitCommitDefine,
      buildTime: _buildTimeDefine,
    );
    return _cached!;
  }

  /// Human-readable line for Settings footer (semver only — no +build suffix).
  String get displayLine {
    final parts = <String>[version, gitCommit];
    if (buildTime.isNotEmpty) {
      parts.add(buildTime);
    }
    return parts.join(' · ');
  }
}
