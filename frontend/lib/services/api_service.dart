import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';

import 'session_refresh_exception.dart';
import '../models/user_model.dart';

class ApiService {
  final String baseUrl;
  final http.Client _httpClient;

  /// Compiled-in build commit sent as `X-App-Commit` on auth calls so server
  /// logs can tell which bundle a (re-)logging-in device runs. Absence of the
  /// header on a login = a bundle older than this telemetry = stale PWA.
  static const String appCommit = String.fromEnvironment(
    'GIT_COMMIT',
    defaultValue: 'dev',
  );

  static const Map<String, String> _authJsonHeaders = {
    'Content-Type': 'application/json',
    'X-App-Commit': appCommit,
  };

  ApiService({required this.baseUrl, http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  /// Extract a human error message from a (possibly non-JSON) error response
  /// WITHOUT throwing. A gateway 502 (HTML), empty 5xx, or timeout body must
  /// surface the HTTP status, not an opaque FormatException from decoding it.
  String _errorMessage(http.Response response, String fallback) {
    try {
      final data = jsonDecode(response.body);
      if (data is Map && data['message'] != null) {
        return data['message'].toString();
      }
    } catch (_) {}
    return '$fallback (${response.statusCode})';
  }

  Future<Map<String, dynamic>> register(
    String username,
    String password,
  ) async {
    final body = {'username': username, 'password': password};

    final response = await _httpClient.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: _authJsonHeaders,
      body: jsonEncode(body),
    );

    if (response.statusCode != 201) {
      throw Exception(_errorMessage(response, 'Registration failed'));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Login returns access + refresh tokens (refresh enables long-lived sessions).
  Future<Map<String, dynamic>> login(String identifier, String password) async {
    final response = await _httpClient.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: _authJsonHeaders,
      body: jsonEncode({'identifier': identifier, 'password': password}),
    );

    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception(_errorMessage(response, 'Login failed'));
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final access = data['access_token'] as String?;
    final refresh = data['refresh_token'] as String?;
    if (access == null || refresh == null) {
      throw Exception('Login response missing tokens');
    }
    return data;
  }

  Future<Map<String, dynamic>> refreshSession(String refreshToken) async {
    try {
      final response = await _httpClient.post(
        Uri.parse('$baseUrl/auth/refresh'),
        headers: _authJsonHeaders,
        body: jsonEncode({'refresh_token': refreshToken}),
      );

      final status = response.statusCode;
      if (status == 401 || status == 403) {
        throw SessionRefreshInvalidException('Session refresh unauthorized');
      }
      if (status == 429 || status == 408) {
        throw SessionRefreshTransientException('Session refresh rate limited');
      }
      if (status >= 500) {
        throw SessionRefreshTransientException('Session refresh server error');
      }

      Map<String, dynamic> data;
      try {
        data = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        throw SessionRefreshTransientException('Invalid refresh response body');
      }

      final message = data['message'] as String? ?? 'Session refresh failed';

      if (status != 200 && status != 201) {
        if (status >= 400 && status < 500) {
          throw SessionRefreshInvalidException(message);
        }
        throw SessionRefreshTransientException(message);
      }

      final access = data['access_token'] as String?;
      final refresh = data['refresh_token'] as String?;
      if (access == null || refresh == null) {
        throw SessionRefreshTransientException('Refresh response missing tokens');
      }
      return data;
    } on SessionRefreshInvalidException {
      rethrow;
    } on SessionRefreshTransientException {
      rethrow;
    } on http.ClientException catch (e) {
      throw SessionRefreshTransientException(e.message);
    }
  }

  Future<void> logoutRefresh(String refreshToken) async {
    final response = await _httpClient.post(
      Uri.parse('$baseUrl/auth/logout'),
      headers: _authJsonHeaders,
      body: jsonEncode({'refresh_token': refreshToken}),
    );
    if (response.statusCode != 204 && response.statusCode != 200) {
      try {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        throw Exception(data['message'] ?? 'Logout failed');
      } catch (_) {
        throw Exception('Logout failed: ${response.statusCode}');
      }
    }
  }

  Future<String> uploadProfilePicture(String token, XFile imageFile) async {
    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/users/profile-picture'),
    );

    request.headers['Authorization'] = 'Bearer $token';

    // Bytes on ALL platforms: the crop flow hands over XFile.fromData, which
    // has no filesystem path on native — fromPath would throw there.
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

    final streamedResponse = await _httpClient.send(request);
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 201 && response.statusCode != 200) {
      throw Exception(_errorMessage(response, 'Upload failed'));
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['profilePictureUrl'] as String;
  }

  Future<List<UserProfilePhoto>> setPrimaryProfilePhoto(
    String token,
    int photoId,
  ) async {
    final response = await _httpClient.post(
      Uri.parse('$baseUrl/users/profile-photos/$photoId/main'),
      headers: {'Authorization': 'Bearer $token'},
    );
    // Nest returns 201 for POST by default.
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(_errorMessage(response, 'Unable to set primary photo'));
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data['profilePhotos'] as List<dynamic>)
        .map((value) => UserProfilePhoto.fromJson(value as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<List<UserProfilePhoto>> deleteProfilePhoto(
    String token,
    int photoId,
  ) async {
    final response = await _httpClient.delete(
      Uri.parse('$baseUrl/users/profile-photos/$photoId'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode != 200) {
      throw Exception(_errorMessage(response, 'Unable to delete profile photo'));
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data['profilePhotos'] as List<dynamic>)
        .map((value) => UserProfilePhoto.fromJson(value as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<List<UserProfilePhoto>> reorderProfilePhotos(
    String token,
    List<int> orderedIds,
  ) async {
    final response = await _httpClient.post(
      Uri.parse('$baseUrl/users/profile-photos/order'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'orderedIds': orderedIds}),
    );
    // Nest returns 201 for POST by default.
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(_errorMessage(response, 'Unable to reorder photos'));
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data['profilePhotos'] as List<dynamic>)
        .map((value) => UserProfilePhoto.fromJson(value as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<String?> updateProfileAbout(String token, String? about) async {
    final response = await _httpClient.patch(
      Uri.parse('$baseUrl/users/profile-about'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'about': about}),
    );
    if (response.statusCode != 200) {
      throw Exception(_errorMessage(response, 'Unable to update profile'));
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['about'] as String?;
  }

  Future<void> resetPassword(
    String token,
    String oldPassword,
    String newPassword,
  ) async {
    final response = await _httpClient.post(
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
      throw Exception(_errorMessage(response, 'Password reset failed'));
    }
  }

  Future<void> deleteAccount(String token, String password) async {
    final response = await _httpClient.delete(
      Uri.parse('$baseUrl/users/account'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({'password': password}),
    );

    if (response.statusCode != 200) {
      throw Exception(_errorMessage(response, 'Account deletion failed'));
    }
  }

  Future<void> registerFcmToken(
    String jwtToken,
    String fcmToken,
    String platform,
  ) async {
    final response = await _httpClient.post(
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
    final response = await _httpClient.delete(
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

  Future<void> registerWebPushSubscription(
    String jwtToken,
    Map<String, dynamic> subscription,
  ) async {
    final response = await _httpClient.post(
      Uri.parse('$baseUrl/users/web-push-subscription'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwtToken',
      },
      body: jsonEncode(subscription),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Failed to register Web Push subscription');
    }
  }

  Future<void> removeWebPushSubscription(
    String jwtToken,
    String endpoint,
  ) async {
    final response = await _httpClient.delete(
      Uri.parse('$baseUrl/users/web-push-subscription'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $jwtToken',
      },
      body: jsonEncode({'endpoint': endpoint}),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Failed to remove Web Push subscription');
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

    final streamedResponse = await _httpClient.send(request);
    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(_errorMessage(response, 'Upload failed'));
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<String> createSecretNote(String token, String ciphertext, int expiresIn) async {
    final response = await _httpClient.post(
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

  /// Whether an Anti-Quantum Note still exists server-side. `false` means the
  /// note is gone — read (burned) or expired; the caller disambiguates with
  /// the link's own `e=` clock. Throws on transport/HTTP failure so callers
  /// can fail open instead of falsely reporting a live note as destroyed.
  Future<bool> isNoteAlive(String token, String noteToken) async {
    final response = await _httpClient.get(
      Uri.parse('$baseUrl/note/$noteToken/status'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode != 200) {
      throw Exception('Note status check failed: ${response.statusCode}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['alive'] == true;
  }

  /// Proxy link preview fetch (for web where CORS blocks direct requests).
  Future<Map<String, String?>?> fetchLinkPreview(String token, String text) async {
    final response = await _httpClient.post(
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

  /// Media URLs from the server often use `http://localhost:3000/...`. On
  /// Android/iOS emulators `localhost` is the device itself, not the dev PC.
  /// Rewrite loopback hosts to [baseUrl]'s host (e.g. `10.0.2.2` on Android
  /// emulator, or a dev PC's LAN IP for a phone) so GIF/image/file/voice fetch
  /// works on every platform — web included. See [rewriteLoopbackMediaUrl].
  String _effectiveMediaUrl(String url) => rewriteLoopbackMediaUrl(url, baseUrl);

  Future<Uint8List> fetchMediaBytes(String url, String token) async {
    final resolved = _effectiveMediaUrl(url);
    final resolvedUri = Uri.tryParse(resolved);
    final baseUri = Uri.tryParse(baseUrl);
    // The media `mediaUrl` arrives in the (sender-controlled, server-unvalidated)
    // E2E envelope, so only ever talk to the backend origin or the legacy
    // Cloudinary host — and only ever send the JWT to our own origin.
    final sameOrigin = resolvedUri != null &&
        baseUri != null &&
        resolvedUri.scheme == baseUri.scheme &&
        resolvedUri.host == baseUri.host &&
        resolvedUri.port == baseUri.port;
    final isLegacyCloudinary = resolvedUri != null &&
        resolvedUri.scheme == 'https' &&
        resolvedUri.host == 'res.cloudinary.com';
    if (!sameOrigin && !isLegacyCloudinary) {
      // H-04: never fetch an attacker-chosen host (so the token cannot leak to it).
      throw Exception(
        'Refusing to fetch media from untrusted host: ${resolvedUri?.host}',
      );
    }
    // Credentials go to our own backend only — never cross-origin.
    final headers = sameOrigin && resolved.contains('/media/msgs/')
        ? {'Authorization': 'Bearer $token'}
        : <String, String>{};
    final response = await _httpClient.get(Uri.parse(resolved), headers: headers);
    if (response.statusCode != 200) {
      throw Exception('Media fetch failed: ${response.statusCode}');
    }
    return response.bodyBytes;
  }

  Future<Map<String, dynamic>> fetchMe(String token) async {
    final response = await _httpClient.get(
      Uri.parse('$baseUrl/users/me'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode != 200) {
      throw Exception('HTTP_${response.statusCode}: fetchMe failed');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

}

/// Rewrites a loopback (`localhost` / `127.0.0.1`) media host to [baseUrl]'s
/// scheme/host/port so the URL is reachable from the current client: the
/// Android emulator (`10.0.2.2`), a phone hitting a dev PC over the LAN, or a
/// web build whose stored `mediaUrl` carries the backend's default
/// `MEDIA_BASE_URL` (`http://localhost:3000`). Non-loopback hosts (e.g. a
/// correctly-configured production origin) are returned unchanged.
///
/// Applies on ALL platforms, web included. Web previously skipped this, so a
/// `localhost` media URL was fetched verbatim and failed on every device that
/// was not the backend host — voice/image/file playback broke cross-device
/// (the listener's `localhost` resolved to its own machine, not the backend).
String rewriteLoopbackMediaUrl(String url, String baseUrl) {
  late final Uri u;
  try {
    u = Uri.parse(url);
  } catch (_) {
    return url;
  }
  if (u.host != 'localhost' && u.host != '127.0.0.1') {
    return url;
  }
  late final Uri b;
  try {
    b = Uri.parse(baseUrl);
  } catch (_) {
    return url;
  }
  if (!b.hasScheme || b.host.isEmpty) return url;
  // Adopt baseUrl's authority fully. `Uri.port` yields the scheme's default
  // (443/80) when baseUrl omits a port, and Dart drops default ports in
  // toString() — so https same-origin rewrites don't get a stray `:3000`.
  return u
      .replace(
        scheme: b.scheme,
        host: b.host,
        port: b.port,
      )
      .toString();
}
