import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class ApiService {
  final String baseUrl;

  ApiService({required this.baseUrl});

  Future<Map<String, dynamic>> register(
    String email,
    String password,
    String? username,
  ) async {
    final body = {'email': email, 'password': password};
    if (username != null && username.isNotEmpty) {
      body['username'] = username;
    }

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

  Future<String> login(String email, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
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

  Future<Map<String, dynamic>> uploadImageMessage(
    String token,
    XFile imageFile,
    int recipientId,
    int? expiresIn,
  ) async {
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/messages/image'),
    );

    request.headers['Authorization'] = 'Bearer $token';
    request.fields['recipientId'] = recipientId.toString();
    if (expiresIn != null) {
      request.fields['expiresIn'] = expiresIn.toString();
    }

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

    return data;
  }
}
