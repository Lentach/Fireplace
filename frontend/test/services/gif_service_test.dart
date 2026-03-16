import 'package:flutter_test/flutter_test.dart';
import 'package:fireplace/services/gif_service.dart';

void main() {
  group('GifModel', () {
    test('fromJson parses Giphy API response', () {
      final json = {
        'id': 'abc123',
        'images': {
          'fixed_height_small': {'url': 'https://media.giphy.com/small.gif'},
          'fixed_height': {'url': 'https://media.giphy.com/full.gif'},
        },
      };
      final gif = GifModel.fromJson(json);
      expect(gif.id, 'abc123');
      expect(gif.previewUrl, 'https://media.giphy.com/small.gif');
      expect(gif.fullUrl, 'https://media.giphy.com/full.gif');
    });

    test('fromJson handles missing fields gracefully', () {
      final json = {
        'id': 'xyz',
        'images': {
          'fixed_height_small': {'url': ''},
          'fixed_height': {'url': ''},
        },
      };
      final gif = GifModel.fromJson(json);
      expect(gif.id, 'xyz');
      expect(gif.previewUrl, '');
      expect(gif.fullUrl, '');
    });
  });
}
