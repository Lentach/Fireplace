import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

class GifModel {
  final String id;
  final String previewUrl;
  final String fullUrl;

  const GifModel({
    required this.id,
    required this.previewUrl,
    required this.fullUrl,
  });

  factory GifModel.fromJson(Map<String, dynamic> json) {
    final images = json['images'] as Map<String, dynamic>? ?? {};
    final small = images['fixed_height_small'] as Map<String, dynamic>? ?? {};
    final full = images['fixed_height'] as Map<String, dynamic>? ?? {};
    return GifModel(
      id: json['id'] as String? ?? '',
      previewUrl: small['url'] as String? ?? '',
      fullUrl: full['url'] as String? ?? '',
    );
  }
}

class GifService {
  static const _baseUrl = 'https://api.giphy.com/v1/gifs';
  http.Client? _client;

  void dispose() {
    _client?.close();
    _client = null;
  }

  Future<List<GifModel>> fetchTrending({int limit = 25, int offset = 0}) async {
    return _fetch('$_baseUrl/trending', limit: limit, offset: offset);
  }

  Future<List<GifModel>> search(String query, {int limit = 25, int offset = 0}) async {
    return _fetch('$_baseUrl/search', query: query, limit: limit, offset: offset);
  }

  Future<List<GifModel>> _fetch(String url, {String? query, int limit = 25, int offset = 0}) async {
    final apiKey = AppConfig.giphyApiKey;
    if (apiKey.isEmpty) {
      debugPrint('[GifService] GIPHY_API_KEY not set. Pass --dart-define=GIPHY_API_KEY=your_key');
      return [];
    }
    _client?.close();
    _client = http.Client();
    final params = {
      'api_key': apiKey,
      'limit': '$limit',
      'offset': '$offset',
      'rating': 'pg-13',
      if (query != null) 'q': query,
    };
    final uri = Uri.parse(url).replace(queryParameters: params);
    try {
      final response = await _client!.get(uri);
      if (response.statusCode != 200) return [];
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final list = data['data'] as List<dynamic>? ?? [];
      return list.map((e) => GifModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }
}
