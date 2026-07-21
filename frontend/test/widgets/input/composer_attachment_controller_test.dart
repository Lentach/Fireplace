import 'dart:typed_data';

import 'package:fireplace/services/media_crypto_service.dart';
import 'package:fireplace/widgets/input/composer_attachment_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ComposerAttachmentController.stage', () {
    test('stages a valid image and notifies', () {
      final c = ComposerAttachmentController();
      var notified = 0;
      c.addListener(() => notified++);

      final result = c.stage(
        bytes: Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/png',
        filename: 'pasted.png',
      );

      expect(result, StageResult.ok);
      expect(c.staged, isNotNull);
      expect(c.staged!.filename, 'pasted.png');
      expect(c.staged!.mimeType, 'image/png');
      expect(notified, 1);
    });

    test('a second stage replaces the first (v1 single-image rule)', () {
      final c = ComposerAttachmentController();
      c.stage(
        bytes: Uint8List.fromList([1]),
        mimeType: 'image/png',
        filename: 'first.png',
      );
      c.stage(
        bytes: Uint8List.fromList([2, 2]),
        mimeType: 'image/jpeg',
        filename: 'second.jpg',
      );

      expect(c.staged!.filename, 'second.jpg');
      expect(c.staged!.bytes.length, 2);
    });

    test('rejects unsupported mime types without staging', () {
      final c = ComposerAttachmentController();
      final result = c.stage(
        bytes: Uint8List.fromList([1]),
        mimeType: 'application/pdf',
        filename: 'doc.pdf',
      );

      expect(result, StageResult.unsupportedType);
      expect(c.staged, isNull);
    });

    test('rejects images over MediaCryptoService.maxBytes', () {
      final c = ComposerAttachmentController();
      final result = c.stage(
        bytes: Uint8List(MediaCryptoService.maxBytes + 1),
        mimeType: 'image/png',
        filename: 'huge.png',
      );

      expect(result, StageResult.tooLarge);
      expect(c.staged, isNull);
    });

    test('clear removes the staged image and notifies once', () {
      final c = ComposerAttachmentController();
      c.stage(
        bytes: Uint8List.fromList([1]),
        mimeType: 'image/webp',
        filename: 'a.webp',
      );
      var notified = 0;
      c.addListener(() => notified++);

      c.clear();
      c.clear(); // idempotent — no second notify

      expect(c.staged, isNull);
      expect(notified, 1);
    });
  });

  group('pastedFilenameForMime', () {
    const cases = {
      'image/png': 'pasted.png',
      'image/jpeg': 'pasted.jpg',
      'image/gif': 'pasted.gif',
      'image/webp': 'pasted.webp',
    };
    cases.forEach((mime, expected) {
      test('$mime -> $expected', () {
        expect(pastedFilenameForMime(mime), expected);
      });
    });

    test('unknown mime falls back to pasted.img', () {
      expect(pastedFilenameForMime('application/octet-stream'), 'pasted.img');
    });
  });
}
