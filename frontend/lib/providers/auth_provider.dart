import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';
import '../services/pwa_app_badge_clear.dart';
import '../services/push_service.dart';
import '../services/session_refresh_exception.dart';
import '../config/app_config.dart';

class AuthProvider extends ChangeNotifier {
  AuthProvider({ApiService? api})
    : _api = api ?? ApiService(baseUrl: AppConfig.baseUrl) {
    _pushService = PushService(_api);
    _loadSavedToken();
  }

  final ApiService _api;
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

  @visibleForTesting
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
      _currentUser = UserModel(
        id: (payload['sub'] as num).toInt(),
        username: payload['username'] as String,
        tag: payload['tag'] as String? ?? '0000',
        profilePictureUrl: _currentUser?.profilePictureUrl,
      );
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jwt_token', access);
    await prefs.setString('refresh_token', refresh);
    _restoreUserFromAccessJwt(access);
    onAccessTokenChanged?.call(access);
    notifyListeners();
  }

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

  Future<void> _clearLocalAuthState(
    String reason, {
    required String source,
    Object? error,
  }) async {
    _logSessionEnd(reason, source: source, error: error);
    _cancelSessionRefreshTimer();
    _isRestoringSession = false;
    _token = null;
    _refreshToken = null;
    _currentUser = null;
    _statusMessage = null;
    _isError = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
    await prefs.remove('refresh_token');
    await clearPwaAppBadgeOnLogout();
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
      final prefs = await SharedPreferences.getInstance();
      final savedToken = prefs.getString('jwt_token');
      final savedRefresh = prefs.getString('refresh_token');
      _refreshToken = savedRefresh;

      if (savedToken == null && savedRefresh == null) return;

      if (savedRefresh != null &&
          (savedToken == null || _isAccessExpired(savedToken))) {
        try {
          await _refreshSessionLocked();
        } on SessionRefreshInvalidException catch (e) {
          await _clearLocalAuthState(
            'refresh_invalid',
            source: 'boot',
            error: e,
          );
          return;
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

      if (_token == null) return;

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
              return;
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
            );
            return;
          }
        }
      }
      _startSessionRefreshTimer();
      notifyListeners();
    } finally {
      _finishRestoringSession();
    }
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
