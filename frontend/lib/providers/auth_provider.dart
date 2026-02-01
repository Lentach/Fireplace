import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import '../services/api_service.dart';
import '../config/app_config.dart';

class AuthProvider extends ChangeNotifier {
  final ApiService _api = ApiService(baseUrl: AppConfig.baseUrl);

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
    if (savedToken != null && !JwtDecoder.isExpired(savedToken)) {
      _token = savedToken;
      final payload = JwtDecoder.decode(savedToken);
      _currentUser = UserModel(
        id: payload['sub'] as int,
        email: payload['email'] as String,
        username: payload['username'] as String?,
        profilePictureUrl: payload['profilePictureUrl'] as String?,
      );
      notifyListeners();
    }
  }

  Future<bool> register(String email, String password, String? username) async {
    try {
      await _api.register(email, password, username);
      _statusMessage = 'Hero created! Now login.';
      _isError = false;
      notifyListeners();
      return true;
    } catch (e) {
      _statusMessage = e.toString().replaceFirst('Exception: ', '');
      _isError = true;
      notifyListeners();
      return false;
    }
  }

  Future<bool> login(String email, String password) async {
    try {
      final accessToken = await _api.login(email, password);
      _token = accessToken;

      final payload = JwtDecoder.decode(accessToken);
      _currentUser = UserModel(
        id: payload['sub'] as int,
        email: payload['email'] as String,
        username: payload['username'] as String?,
        profilePictureUrl: payload['profilePictureUrl'] as String?,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('jwt_token', accessToken);

      _statusMessage = null;
      _isError = false;
      notifyListeners();
      return true;
    } catch (e) {
      _statusMessage = e.toString().replaceFirst('Exception: ', '');
      _isError = true;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
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
      final profilePictureUrl = await _api.uploadProfilePicture(_token!, imageFile);

      // Update current user with new profile picture URL
      if (_currentUser != null) {
        _currentUser = _currentUser!.copyWith(
          profilePictureUrl: profilePictureUrl,
        );
        notifyListeners();
      }
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
