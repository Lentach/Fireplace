import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';

class ApiService {
  final String baseUrl;

  ApiService({required this.baseUrl});

  Future<Map<String, dynamic>> register(
    String username,
    String password,
  ) async {
    final body = {'username': username, 'password': password};

    final response = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 201) {
      throw Exception(data['message'] ?? 'Registration failed');
    }
    return data;
  }

  Future<String> login(String identifier, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'identifier': identifier, 'password': password}),
    );

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception(data['message'] ?? 'Login failed');
    }
    return data['access_token'] as String;
  }

  Future<String> uploadProfilePicture(String token, XFile imageFile) async {
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/users/profile-picture'),
    );

    request.headers['Authorization'] = 'Bearer $token';

    // Handle web vs native platforms
    if (kIsWeb) {
      // Web: use readAsBytes with proper MIME type
      final bytes = await imageFile.readAsBytes();
      final extension = imageFile.name.toLowerCase().split('.').last;
      final mimeType = extension == 'png' ? 'image/png' : 'image/jpeg';

      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: imageFile.name,
          contentType: http.MediaType.parse(mimeType),
        ),
      );
    } else {
      // Native: use fromPath
      request.files.add(
        await http.MultipartFile.fromPath('file', imageFile.path),
      );
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception(data['message'] ?? 'Upload failed');
    }

    return data['profilePictureUrl'] as String;
  }

  Future<void> resetPassword(
    String token,
    String oldPassword,
    String newPassword,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/users/reset-password'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'oldPassword': oldPassword,
        'newPassword': newPassword,
      }),
    );

    if (response.statusCode != 201 && response.statusCode != 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(data['message'] ?? 'Password reset failed');
    }
  }

  Future<void> deleteAccount(String token, String password) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/users/account'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'password': password}),
    );

    if (response.statusCode != 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(data['message'] ?? 'Account deletion failed');
    }
  }

  Future<void> registerFcmToken(
    String jwtToken,
    String fcmToken,
    String platform,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/users/fcm-token'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwtToken',
      },
      body: jsonEncode({'token': fcmToken, 'platform': platform}),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Failed to register FCM token');
    }
  }

  Future<void> removeFcmToken(String jwtToken, String fcmToken) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/users/fcm-token'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwtToken',
      },
      body: jsonEncode({'token': fcmToken}),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Failed to remove FCM token');
    }
  }

  /// Upload an AES-encrypted media blob to [POST /media/upload].
  Future<Map<String, dynamic>> uploadEncryptedMedia({
    required String token,
    required Uint8List encryptedBytes,
    required String mediaType,
    int? duration,
    int? expiresIn,
    String? fileName,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/media/upload'),
    );
    request.headers['Authorization'] = 'Bearer $token';
    request.fields['mediaType'] = mediaType;
    if (duration != null) request.fields['duration'] = duration.toString();
    if (expiresIn != null) request.fields['expiresIn'] = expiresIn.toString();
    if (fileName != null) request.fields['fileName'] = fileName;

    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        encryptedBytes,
        filename: 'encrypted.bin',
        contentType: MediaType('application', 'octet-stream'),
      ),
    );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(data['message'] ?? 'Upload failed');
    }
    return data;
  }

  Future<String> createSecretNote(String token, String ciphertext, int expiresIn) async {
    final response = await http.post(
      Uri.parse('$baseUrl/notes'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'ciphertext': ciphertext, 'expiresIn': expiresIn}),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Failed to create secret note: ${response.statusCode}');
    }
    final data = jsonDecode(response.body);
    return data['token'] as String;
  }

  /// Proxy link preview fetch (for web where CORS blocks direct requests).
  Future<Map<String, String?>?> fetchLinkPreview(String token, String text) async {
    final response = await http.post(
      Uri.parse('$baseUrl/messages/link-preview'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'text': text}),
    );

    if (response.statusCode != 200 && response.statusCode != 201) return null;

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data.isEmpty || data['url'] == null) return null;

    return {
      'url': data['url'] as String?,
      'title': data['title'] as String?,
      'imageUrl': data['imageUrl'] as String?,
    };
  }

  Future<Uint8List> fetchMediaBytes(String url, String token) async {
    final headers =
        url.contains('/media/msgs/')
            ? {'Authorization': 'Bearer $token'}
            : <String, String>{};
    final response = await http.get(Uri.parse(url), headers: headers);
    if (response.statusCode != 200) {
      throw Exception('Media fetch failed: ${response.statusCode}');
    }
    return response.bodyBytes;
  }

  Future<Map<String, dynamic>> fetchMe(String token) async {
    final response = await http.get(
      Uri.parse('$baseUrl/users/me'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode != 200) {
      throw Exception('HTTP_${response.statusCode}: fetchMe failed');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

}
