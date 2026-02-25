import 'dart:convert';
import 'dart:io';
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

  Future<VoiceUploadResult> uploadVoiceMessage({
    required String token,
    required int duration,
    required int recipientId,
    int? expiresIn,
    String? audioPath,
    List<int>? audioBytes,
  }) async {
    List<int> bytes;
    if (audioBytes != null) {
      bytes = audioBytes;
    } else if (audioPath != null) {
      final file = File(audioPath);
      if (!await file.exists()) {
        throw Exception('Audio file not found: $audioPath');
      }
      bytes = await file.readAsBytes();
    } else {
      throw Exception('Either audioPath or audioBytes required');
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/messages/voice'),
    );

    request.headers['Authorization'] = 'Bearer $token';

    final isWeb = audioBytes != null;
    final ext = isWeb ? 'wav' : 'm4a';
    final mime = isWeb ? 'wav' : 'm4a';
    request.files.add(http.MultipartFile.fromBytes(
      'audio',
      bytes,
      filename: 'voice_${DateTime.now().millisecondsSinceEpoch}.$ext',
      contentType: MediaType('audio', mime),
    ));

    request.fields['duration'] = duration.toString();
    request.fields['recipientId'] = recipientId.toString();
    if (expiresIn != null) {
      request.fields['expiresIn'] = expiresIn.toString();
    }

    final response = await request.send();
    final responseBody = await response.stream.bytesToString();

    if (response.statusCode == 201 || response.statusCode == 200) {
      final json = jsonDecode(responseBody);
      return VoiceUploadResult.fromJson(json);
    } else {
      throw Exception('Failed to upload voice message: ${response.statusCode} - $responseBody');
    }
  }
}

class VoiceUploadResult {
  final String mediaUrl;
  final String publicId;
  final int duration;

  VoiceUploadResult({
    required this.mediaUrl,
    required this.publicId,
    required this.duration,
  });

  factory VoiceUploadResult.fromJson(Map<String, dynamic> json) {
    return VoiceUploadResult(
      mediaUrl: json['mediaUrl'] as String,
      publicId: json['publicId'] as String,
      duration: (json['duration'] as num).round(),
    );
  }
}
