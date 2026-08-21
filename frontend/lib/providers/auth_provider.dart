import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import '../models/user_model.dart';
import '../services/auth_token_store.dart';
import '../services/api_service.dart';
import '../services/pwa_app_badge_clear.dart';
import '../services/push_service.dart';
import '../services/session_refresh_exception.dart';
import '../config/app_config.dart';
import '../utils/e2e_persistent_diag.dart';

class AuthProvider extends ChangeNotifier {
  AuthProvider({
    ApiService? api,
    AuthTokenStore? tokenStore,
    List<Duration>? tokenReadRetryDelays,
  }) : _api = api ?? ApiService(baseUrl: AppConfig.baseUrl),
       _tokenReadRetryDelays =
           tokenReadRetryDelays ??
           const [Duration(seconds: 2), Duration(seconds: 5)],
       _tokens = tokenStore ?? AuthTokenStore() {
    _pushService = PushService(_api);
    _loadSavedToken();
  }

  /// Slow second-chance delays when the token store reports `readFailed` at
  /// boot. Injectable so tests need not wait real seconds.
  final List<Duration> _tokenReadRetryDelays;

  final ApiService _api;
  final AuthTokenStore _tokens;
  late final PushService _pushService;

  String? _token;
  String? _refreshToken;
  UserModel? _currentUser;
  String? _statusMessage;
  bool _isError = false;
  Timer? _sessionRefreshTimer;
  Future<void>? _sessionRefreshInFlight;
  bool _isRestoringSession = true;
  String? _lastSessionEndReason;

  static const int _refreshMaxAttempts = 3;
  static const Duration _refreshRetryBaseDelay = Duration(milliseconds: 250);

  /// Wired from [MainShell] so socket/media use refreshed JWT without restart.
  void Function(String accessToken)? onAccessTokenChanged;

  String? get token => _token;
  UserModel? get currentUser => _currentUser;
  String? get statusMessage => _statusMessage;
  bool get isError => _isError;
  bool get isRestoringSession => _isRestoringSession;
  bool get isLoggedIn => _token != null && _currentUser != null;

  /// Why the last session ended (e.g. `refresh_invalid`,
  /// `expired_access_without_refresh`). Shown on the auth screen so a victim
  /// screenshot names the exact logout path; null on a clean cold start —
  /// which itself is a signal (wiped storage leaves nothing to clear).
  String? get lastSessionEndReason => _lastSessionEndReason;

  void setOnAccessTokenChanged(void Function(String)? cb) {
    onAccessTokenChanged = cb;
  }

  /// Test-only: force an expired access JWT while keeping refresh token in memory.
  @visibleForTesting
  void setAccessTokenForTest(String token) {
    _token = token;
    _restoreUserFromAccessJwt(token);
    notifyListeners();
  }

  bool _isAccessExpired(String jwt) {
    try {
      return JwtDecoder.isExpired(jwt);
    } catch (_) {
      // Undecodable token → treat as expired (fail closed): forces a refresh
      // attempt instead of trusting garbage; recovers or lands on login.
      return true;
    }
  }

  void _restoreUserFromAccessJwt(String accessJwt) {
    try {
      final payload = JwtDecoder.decode(accessJwt);
      final id = (payload['sub'] as num).toInt();
      final username = payload['username'] as String;
      final tag = payload['tag'] as String? ?? '0000';
      final existing = _currentUser;
      if (existing != null && existing.id == id) {
        // Same account (e.g. silent 15-min token refresh): keep the fully
        // hydrated profile (profilePhotos, about, profilePictureUrl, ...) and
        // only refresh the identity fields the JWT actually carries. Rebuilding
        // from claims alone would collapse profilePhotos to [] and drop about.
        _currentUser = existing.copyWith(id: id, username: username, tag: tag);
      } else {
        // Cold start or account switch: no fully-hydrated prior profile to
        // trust, so rebuild from claims (preserving prior behavior exactly).
        _currentUser = UserModel(
          id: id,
          username: username,
          tag: tag,
          profilePictureUrl: existing?.profilePictureUrl,
        );
      }
    } catch (_) {}
  }

  Future<void> _persistTokens(Map<String, dynamic> body) async {
    final access = body['access_token'] as String?;
    final refresh = body['refresh_token'] as String?;
    if (access == null || refresh == null) {
      throw StateError('Auth response missing tokens');
    }
    _token = access;
    _refreshToken = refresh;
    await _tokens.write(access: access, refresh: refresh);
    _restoreUserFromAccessJwt(access);
    onAccessTokenChanged?.call(access);
    notifyListeners();
  }

  /// Installs the deviceId-bound session a §5.1 provisioning ceremony
  /// returned in `provisioningCompleted` (spec §12 item (iii)). Same storage
  /// path as login/refresh — a second token path would drift.
  Future<void> adoptProvisionedSession(Map<String, dynamic> tokens) =>
      _persistTokens(tokens);

  Future<void> _silentRefresh() async {
    final r = _refreshToken;
    if (r == null) {
      throw SessionRefreshInvalidException('No refresh token');
    }

    Object? lastTransient;
    for (var attempt = 0; attempt < _refreshMaxAttempts; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(_refreshRetryBaseDelay * attempt);
      }
      try {
        final body = await _api.refreshSession(r);
        await _persistTokens(body);
        return;
      } on SessionRefreshInvalidException {
        rethrow;
      } on SessionRefreshTransientException catch (e) {
        lastTransient = e;
      } catch (e) {
        lastTransient = e;
      }
    }

    throw SessionRefreshTransientException(
      lastTransient?.toString() ?? 'Session refresh failed after retries',
    );
  }

  /// Single in-flight refresh for startup, resume, and parallel [ensureSessionReady].
  Future<void> _refreshSessionLocked() async {
    if (_sessionRefreshInFlight != null) {
      return _sessionRefreshInFlight!;
    }

    final future = _silentRefresh();
    _sessionRefreshInFlight = future;
    try {
      await future;
    } finally {
      if (identical(_sessionRefreshInFlight, future)) {
        _sessionRefreshInFlight = null;
      }
    }
  }

  void _logSessionEnd(String reason, {required String source, Object? error}) {
    _lastSessionEndReason = reason;
    final access = _token;
    final userId = _currentUser?.id;
    final accessExpired = access == null ? null : _isAccessExpired(access);
    debugPrint(
      '[auth-session-end] reason=$reason source=$source '
      'hasAccess=${access != null} hasRefresh=${_refreshToken != null} '
      'accessExpired=$accessExpired userId=$userId '
      'errorType=${error.runtimeType}',
    );
    // Involuntary session ends are failure-class field evidence (the 2026-07
    // logout incident was undiagnosable client-side); explicit logout is not.
    if (reason != 'explicit_logout') {
      final payload = {
        'reason': reason,
        'source': source,
        'hasRefresh': _refreshToken != null,
        'accessExpired': accessExpired,
      };
      // The locally-derived reasons fire on EVERY boot while a dead access
      // token lingers in storage (the §5.4 keep-the-store tradeoff), and the
      // durable log is an 80-entry FIFO — plain records would churn out the
      // BOOT_MARKERS forensics planted to diagnose the next storage wipe.
      // Dedup them; eviction re-arms, so recurrence is never lost for good.
      const repeatProne = {
        'expired_access_without_refresh',
        'access_401_without_refresh',
      };
      if (repeatProne.contains(reason)) {
        E2ePersistentDiag.recordDeduped(
          'AUTH_SESSION_END',
          payload,
          matchAll: ['reason: $reason,'],
        );
      } else {
        E2ePersistentDiag.record('AUTH_SESSION_END', payload);
      }
    }
  }

  void _finishRestoringSession() {
    if (!_isRestoringSession) return;
    _isRestoringSession = false;
    notifyListeners();
  }

  void _restoreSavedAccessToken(String savedToken) {
    _token = savedToken;
    _restoreUserFromAccessJwt(savedToken);
    notifyListeners();
  }

  /// [wipeStoredTokens]: only SERVER-AUTHORITATIVE reasons (`refresh_invalid*`,
  /// explicit logout, password change) may delete the persisted tokens. The
  /// locally-derived reasons (`expired_access_without_refresh`,
  /// `access_401_without_refresh`) are inferred from in-memory ABSENCE — if
  /// that absence was ever an artifact (a glitched read, a lost hydration),
  /// wiping storage here converts a transient fault into a permanent logout,
  /// destroying a refresh token the server still honors (user 54's row was
  /// valid to 2027 while he sat on a login screen). They clear the SESSION,
  /// never the STORE; the next cold boot re-reads storage and recovers.
  Future<void> _clearLocalAuthState(
    String reason, {
    required String source,
    Object? error,
    bool wipeStoredTokens = true,
  }) async {
    _logSessionEnd(reason, source: source, error: error);
    _cancelSessionRefreshTimer();
    _isRestoringSession = false;
    _token = null;
    _refreshToken = null;
    _currentUser = null;
    _statusMessage = null;
    _isError = false;
    if (wipeStoredTokens) {
      await _tokens.clear();
    }
    await clearPwaAppBadgeOnLogout();
    notifyListeners();
  }

  /// The server revoked THIS device (multi-device spec §5.5 + amendment
  /// (xxvi)): end the session and say why.
  ///
  /// Logout semantics, deliberately not a wipe: the local plaintext store and
  /// the Signal key material are untouched, exactly as on every other logout
  /// path — remote wipe of a revoked device's data is an explicit non-goal
  /// (spec §1). Stored tokens DO go, because the server already deleted that
  /// device's refresh sessions; keeping them would only produce a doomed
  /// refresh on the next cold boot.
  ///
  /// [notice] is the localized explanation, passed in because only the widget
  /// layer holds the locale.
  Future<void> logoutBecauseDeviceRevoked(String notice) async {
    if (_token == null && _currentUser == null) return;
    await _clearLocalAuthState('device_revoked', source: 'deviceRevoked');
    // After the clear, which resets the status surface.
    _statusMessage = notice;
    _isError = true;
    notifyListeners();
  }

  /// Keeps access JWT valid using the opaque refresh token (messenger-style session).
  Future<void> ensureSessionReady() async {
    await _ensureSessionReadyBody();
  }

  Future<void> _ensureSessionReadyBody() async {
    if (_refreshToken == null) {
      if (_token != null && _isAccessExpired(_token!)) {
        await _clearLocalAuthState(
          'expired_access_without_refresh',
          source: 'ensureSessionReady',
          wipeStoredTokens: false,
        );
      }
      return;
    }
    if (_token != null && !_isAccessExpired(_token!)) return;

    try {
      await _refreshSessionLocked();
    } on SessionRefreshInvalidException catch (e) {
      await _clearLocalAuthState(
        'refresh_invalid',
        source: 'ensureSessionReady',
        error: e,
      );
    } on SessionRefreshTransientException {
      if (_token != null) {
        _restoreUserFromAccessJwt(_token!);
      }
      notifyListeners();
    }
  }

  void _cancelSessionRefreshTimer() {
    _sessionRefreshTimer?.cancel();
    _sessionRefreshTimer = null;
  }

  void _startSessionRefreshTimer() {
    _cancelSessionRefreshTimer();
    _sessionRefreshTimer = Timer.periodic(const Duration(minutes: 15), (_) {
      ensureSessionReady();
    });
  }

  Future<void> _loadSavedToken() async {
    try {
      var saved = await _tokens.read();
      // Bounded retry-before-decide: a read that ERRORS is not a logout —
      // the tokens may be sitting intact behind a transient plugin fault
      // (handoff §5.4). The store already retried fast; these are the slow
      // second chances before we concede the boot.
      for (
        var i = 0;
        saved.readFailed && i < _tokenReadRetryDelays.length;
        i++
      ) {
        await Future<void>.delayed(_tokenReadRetryDelays[i]);
        saved = await _tokens.read();
      }
      if (saved.readFailed) {
        // Storage answered with errors on every attempt. Concede the boot to
        // the login screen but LEAVE THE STORE UNTOUCHED — the next launch
        // re-reads it — and say what happened instead of feigning a logout.
        // Durable AUTH_TOKENS_UNREADABLE was recorded by the store.
        _statusMessage =
            'Could not read the saved session from device storage. '
            'Your login may still be there — restart the app to retry.';
        _isError = true;
        return;
      }
      final savedToken = saved.access;
      final savedRefresh = saved.refresh;
      _refreshToken = savedRefresh;

      if (savedToken == null && savedRefresh == null) return;

      // Whether the SAVED access alone was usable — i.e. boot phase 1 will
      // restore it without refreshing. Decides the proactive slide below.
      final savedAccessUsable =
          savedToken != null && !_isAccessExpired(savedToken);

      // Phase 1: get a usable access token (refresh if missing/expired).
      if (await _restoreAccessOnBoot(savedToken)) return;
      if (_token == null) return;

      // Phase 2: hydrate the current user (one refresh retry on a 401).
      if (await _hydrateCurrentUserOnBoot()) return;

      _startSessionRefreshTimer();
      if (savedAccessUsable) {
        _scheduleBackgroundSessionSlide();
      }
      notifyListeners();
    } finally {
      _finishRestoringSession();
    }
  }

  /// Proactively slides the sliding refresh session once per cold boot even
  /// while the access JWT is still valid. Purpose: (1) the server-side
  /// `refresh_tokens.expires_at` becomes a daily per-device health signal
  /// (a device that stops sliding = storage loss/stale bundle candidate);
  /// (2) the access token in hand is almost always fresh, so a later offline
  /// reopen inside 24h still works. MUST route around [ensureSessionReady]
  /// (it no-ops on a valid access) and MUST swallow every failure including
  /// [SessionRefreshInvalidException]: a revoked-row or transient blip during
  /// boot must never log the user out of a still-valid session — the regular
  /// expiry path deals with truly dead sessions.
  void _scheduleBackgroundSessionSlide() {
    if (_refreshToken == null) return;
    unawaited(
      _refreshSessionLocked().catchError((Object e) {
        debugPrint(
          '[auth-session-slide] background slide failed (kept session): '
          '${e.runtimeType}',
        );
      }),
    );
  }

  /// Boot phase 1: ensure [_token] holds a usable access JWT. When a refresh
  /// token exists and the saved access is missing/expired, refresh; otherwise
  /// restore the saved access. Returns true if the session was cleared and the
  /// caller must abort. [savedToken] is the persisted (possibly expired) access.
  Future<bool> _restoreAccessOnBoot(String? savedToken) async {
    if (_refreshToken != null &&
        (savedToken == null || _isAccessExpired(savedToken))) {
      try {
        await _refreshSessionLocked();
      } on SessionRefreshInvalidException catch (e) {
        await _clearLocalAuthState('refresh_invalid', source: 'boot', error: e);
        return true;
      } on SessionRefreshTransientException {
        if (savedToken != null) {
          _restoreSavedAccessToken(savedToken);
        }
      } catch (e) {
        if (savedToken != null) {
          _restoreSavedAccessToken(savedToken);
        } else {
          debugPrint(
            '[auth-session-restore] source=boot outcome=transient_without_access '
            'hasRefresh=true errorType=${e.runtimeType}',
          );
        }
      }
    } else if (savedToken != null) {
      _restoreSavedAccessToken(savedToken);
    }
    return false;
  }

  /// Boot phase 2: fetch the current user for the restored [_token]. On a 401,
  /// try exactly one refresh + refetch; a transient failure falls back to the
  /// JWT claims. Returns true if the session was cleared and the caller must abort.
  Future<bool> _hydrateCurrentUserOnBoot() async {
    try {
      final userData = await _api.fetchMe(_token!);
      _currentUser = UserModel.fromJson(userData);
    } on Exception catch (e) {
      if (e.toString().startsWith('Exception: HTTP_401')) {
        if (_refreshToken != null) {
          try {
            await _refreshSessionLocked();
            if (_token != null) {
              final userData = await _api.fetchMe(_token!);
              _currentUser = UserModel.fromJson(userData);
            }
          } on SessionRefreshInvalidException catch (refreshError) {
            await _clearLocalAuthState(
              'refresh_invalid_after_access_401',
              source: 'boot_fetch_me',
              error: refreshError,
            );
            return true;
          } on SessionRefreshTransientException {
            if (_token != null) {
              _restoreUserFromAccessJwt(_token!);
            }
          } catch (_) {
            if (_token != null) {
              _restoreUserFromAccessJwt(_token!);
            }
          }
        } else {
          await _clearLocalAuthState(
            'access_401_without_refresh',
            source: 'boot_fetch_me',
            error: e,
            wipeStoredTokens: false,
          );
          return true;
        }
      }
    }
    return false;
  }

  Future<bool> register(String username, String password) async {
    try {
      await _api.register(username, password);
      _statusMessage = 'Hero created! Now login.';
      _isError = false;
      notifyListeners();
      return true;
    } catch (e) {
      _statusMessage = _userFriendlyNetworkError(e);
      _isError = true;
      notifyListeners();
      return false;
    }
  }

  Future<bool> login(String identifier, String password) async {
    try {
      final body = await _api.login(identifier, password);
      await _persistTokens(body);
      final userData = await _api.fetchMe(_token!);
      _currentUser = UserModel.fromJson(userData);

      _statusMessage = null;
      _isError = false;
      _startSessionRefreshTimer();
      notifyListeners();
      return true;
    } catch (e) {
      _statusMessage = _userFriendlyNetworkError(e);
      _isError = true;
      notifyListeners();
      return false;
    }
  }

  static String _userFriendlyNetworkError(Object e) {
    final msg = e.toString().replaceFirst('Exception: ', '');
    if (msg.contains('Failed to fetch') ||
        msg.contains('Connection refused') ||
        msg.contains('Connection reset') ||
        msg.contains('SocketException') ||
        msg.contains('NetworkException')) {
      return 'Cannot reach server. Is the backend running? (e.g. docker-compose up)';
    }
    return msg;
  }

  Future<void> logout() async {
    if (_token != null) {
      await _pushService.unregister(_token!);
    }

    final rt = _refreshToken;
    if (rt != null) {
      try {
        await _api.logoutRefresh(rt);
      } catch (_) {}
    }

    await _clearLocalAuthState('explicit_logout', source: 'logout');
  }

  void clearStatus() {
    _statusMessage = null;
    _isError = false;
    notifyListeners();
  }

  Future<void> updateProfilePicture(XFile imageFile) async {
    if (_token == null) {
      throw Exception('Not authenticated');
    }

    try {
      await _api.uploadProfilePicture(_token!, imageFile);

      final userData = await _api.fetchMe(_token!);
      _currentUser = UserModel.fromJson(userData);
      notifyListeners();
    } catch (e) {
      throw Exception(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> setPrimaryProfilePhoto(int photoId) async {
    if (_token == null || _currentUser == null) {
      throw Exception('Not authenticated');
    }
    final photos = await _api.setPrimaryProfilePhoto(_token!, photoId);
    final primary = photos.firstWhere((photo) => photo.isPrimary);
    _currentUser = _currentUser!.copyWith(
      profilePhotos: photos,
      profilePictureUrl: primary.url,
    );
    notifyListeners();
  }

  /// Persists an explicit photo order; the first id becomes the primary
  /// photo (backend contract for POST /users/profile-photos/order).
  Future<void> reorderProfilePhotos(List<int> orderedIds) async {
    if (_token == null || _currentUser == null) {
      throw Exception('Not authenticated');
    }
    final photos = await _api.reorderProfilePhotos(_token!, orderedIds);
    final primary = photos.firstWhere((photo) => photo.isPrimary);
    _currentUser = _currentUser!.copyWith(
      profilePhotos: photos,
      profilePictureUrl: primary.url,
    );
    notifyListeners();
  }

  Future<void> deleteProfilePhoto(int photoId) async {
    if (_token == null || _currentUser == null) {
      throw Exception('Not authenticated');
    }
    final photos = await _api.deleteProfilePhoto(_token!, photoId);
    final primary = photos.where((photo) => photo.isPrimary).firstOrNull;
    _currentUser = _currentUser!.copyWith(
      profilePhotos: photos,
      profilePictureUrl: primary?.url,
      clearProfilePicture: primary == null,
    );
    notifyListeners();
  }

  Future<void> updateProfileAbout(String? about) async {
    if (_token == null || _currentUser == null) {
      throw Exception('Not authenticated');
    }
    final savedAbout = await _api.updateProfileAbout(_token!, about);
    _currentUser = _currentUser!.copyWith(
      about: savedAbout,
      clearAbout: savedAbout == null,
    );
    notifyListeners();
  }

  Future<void> resetPassword(String oldPassword, String newPassword) async {
    if (_token == null) {
      throw Exception('Not authenticated');
    }
    try {
      await _api.resetPassword(_token!, oldPassword, newPassword);
      await _clearLocalAuthState('password_changed', source: 'resetPassword');
    } catch (e) {
      throw Exception(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<bool> deleteAccount(String password) async {
    if (_token == null) {
      throw Exception('Not authenticated');
    }

    try {
      await _api.deleteAccount(_token!, password);

      await logout();
      return true;
    } catch (e) {
      throw Exception(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  void dispose() {
    _cancelSessionRefreshTimer();
    super.dispose();
  }
}
