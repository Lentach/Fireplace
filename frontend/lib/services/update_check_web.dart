import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_service.dart' show ApiService;

/// Web: true when the SERVED bundle's git commit differs from the RUNNING
/// bundle's compiled-in commit.
///
/// `version.json` is served from the frontend origin and `deploy-web.ps1`
/// injects `gitCommit` into it at publish time. The compiled
/// [ApiService.appCommit] is the only truthful identity of the running code —
/// PackageInfo on web fetches version.json over the network and therefore
/// reports the SERVER's version even when the service worker still runs an
/// old bundle (the documented stale-PWA trap). Any failure returns false:
/// this is a nudge, never a gate.
Future<bool> isServedBundleNewer() async {
  const running = ApiService.appCommit;
  if (running.isEmpty || running == 'dev') return false; // local/dev builds
  try {
    final uri = Uri.base.resolve(
      'version.json?ucb=${DateTime.now().millisecondsSinceEpoch}',
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return false;
    final data = jsonDecode(response.body);
    final served = data is Map<String, dynamic>
        ? data['gitCommit'] as String?
        : null;
    // Absent gitCommit = version.json published before the injection existed.
    if (served == null || served.isEmpty) return false;
    return served != running;
  } catch (e) {
    debugPrint('[update-check] skipped: ${e.runtimeType}');
    return false;
  }
}
