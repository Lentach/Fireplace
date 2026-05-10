import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';
import '../services/pwa_app_badge_clear.dart';
import '../services/push_service.dart';
import '../config/app_config.dart';

class AuthProvider extends ChangeNotifier {
  final ApiService _api = ApiService(baseUrl: AppConfig.baseUrl);
  late final PushService _pushService = PushService(_api);

  String? _token;
  String? _refreshToken;
  UserModel? _currentUser;
  String? _statusMessage;
  bool _isError = false;
  Timer? _sessionRefreshTimer;

  /// Wired from [MainShell] so socket/media use refreshed JWT without restart.
  void Function(String accessToken)? onAccessTokenChanged;

  String? get token => _token;
  UserModel? get currentUser => _currentUser;
  String? get statusMessage => _statusMessage;
  bool get isError => _isError;
  bool get isLoggedIn => _token != null && _currentUser != null;

  AuthProvider() {
    _loadSavedToken();
  }

  void setOnAccessTokenChanged(void Function(String)? cb) {
    onAccessTokenChanged = cb;
  }

  bool _isAccessExpired(String jwt) {
    try {
      return JwtDecoder.isExpired(jwt);
    } catch (_) {
      return true;
    }
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
    try {
      final payload = JwtDecoder.decode(access);
      _currentUser = UserModel(
        id: (payload['sub'] as num).toInt(),
        username: payload['username'] as String,
        tag: payload['tag'] as String? ?? '0000',
        profilePictureUrl: _currentUser?.profilePictureUrl,
      );
    } catch (_) {}
    onAccessTokenChanged?.call(access);
    notifyListeners();
  }

  Future<void> _silentRefresh() async {
    final r = _refreshToken;
    if (r == null) throw StateError('No refresh token');
    final body = await _api.refreshSession(r);
    await _persistTokens(body);
  }

  Future<void> _clearLocalAuthState() async {
    _cancelSessionRefreshTimer();
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
    if (_refreshToken == null) {
      if (_token != null && _isAccessExpired(_token!)) {
        await _clearLocalAuthState();
      }
      return;
    }
    if (_token != null && !_isAccessExpired(_token!)) return;
    try {
      await _silentRefresh();
    } catch (_) {
      await _clearLocalAuthState();
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
    final prefs = await SharedPreferences.getInstance();
    final savedToken = prefs.getString('jwt_token');
    final savedRefresh = prefs.getString('refresh_token');
    _refreshToken = savedRefresh;

    if (savedToken == null && savedRefresh == null) return;

    if (savedRefresh != null &&
        (savedToken == null || _isAccessExpired(savedToken))) {
      try {
        final body = await _api.refreshSession(savedRefresh);
        await _persistTokens(body);
      } catch (_) {
        await _clearLocalAuthState();
        return;
      }
    } else if (savedToken != null) {
      _token = savedToken;
      try {
        final payload = JwtDecoder.decode(savedToken);
        _currentUser = UserModel(
          id: (payload['sub'] as num).toInt(),
          username: payload['username'] as String,
          tag: payload['tag'] as String? ?? '0000',
          profilePictureUrl: null,
        );
        notifyListeners();
      } catch (_) {}
    }

    if (_token == null) return;

    try {
      final userData = await _api.fetchMe(_token!);
      _currentUser = UserModel.fromJson(userData);
    } on Exception catch (e) {
      if (e.toString().startsWith('Exception: HTTP_401')) {
        if (_refreshToken != null) {
          try {
            await _silentRefresh();
            if (_token != null) {
              final userData = await _api.fetchMe(_token!);
              _currentUser = UserModel.fromJson(userData);
            }
          } catch (_) {
            await _clearLocalAuthState();
            return;
          }
        } else {
          await _clearLocalAuthState();
          return;
        }
      }
    }
    _startSessionRefreshTimer();
    notifyListeners();
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

    await _clearLocalAuthState();
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

  Future<void> resetPassword(String oldPassword, String newPassword) async {
    if (_token == null) {
      throw Exception('Not authenticated');
    }

    try {
      await _api.resetPassword(_token!, oldPassword, newPassword);
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
