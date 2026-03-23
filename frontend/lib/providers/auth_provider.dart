import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';
import '../services/push_service.dart';
import '../config/app_config.dart';

class AuthProvider extends ChangeNotifier {
  final ApiService _api = ApiService(baseUrl: AppConfig.baseUrl);
  late final PushService _pushService = PushService(_api);

  String? _token;
  UserModel? _currentUser;
  String? _statusMessage;
  bool _isError = false;

  String? get token => _token;
  UserModel? get currentUser => _currentUser;
  String? get statusMessage => _statusMessage;
  bool get isError => _isError;
  bool get isLoggedIn => _token != null && _currentUser != null;

  AuthProvider() {
    _loadSavedToken();
  }

  Future<void> _loadSavedToken() async {
    final prefs = await SharedPreferences.getInstance();
    final savedToken = prefs.getString('jwt_token');
    if (savedToken != null) {
      _token = savedToken;
      try {
        final payload = JwtDecoder.decode(savedToken);
        _currentUser = UserModel(
          id: payload['sub'] as int,
          username: payload['username'] as String,
          tag: payload['tag'] as String? ?? '0000',
          profilePictureUrl: null,
        );
        notifyListeners();
      } catch (_) {
        // Keep token and continue with fetchMe fallback.
      }
      try {
        final userData = await _api.fetchMe(_token!);
        _currentUser = UserModel.fromJson(userData);
      } on Exception catch (e) {
        if (e.toString().startsWith('Exception: HTTP_401')) {
          _token = null;
          await prefs.remove('jwt_token');
          notifyListeners();
          return;
        }
      }
      notifyListeners();
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
      final accessToken = await _api.login(identifier, password);
      _token = accessToken;
      final userData = await _api.fetchMe(_token!);
      _currentUser = UserModel.fromJson(userData);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('jwt_token', accessToken);

      _statusMessage = null;
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
    // Unregister FCM token before clearing JWT (need token for API call)
    if (_token != null) {
      await _pushService.unregister(_token!);
    }

    _token = null;
    _currentUser = null;
    _statusMessage = null;
    _isError = false;

    final prefs = await SharedPreferences.getInstance();
    // Don't clear dark mode preference - only clear token
    await prefs.remove('jwt_token');

    notifyListeners();
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

      // Log out after successful deletion
      await logout();
      return true;
    } catch (e) {
      throw Exception(e.toString().replaceFirst('Exception: ', ''));
    }
  }
}
