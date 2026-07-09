import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fireplace/models/message_model.dart';
import 'package:fireplace/providers/auth_provider.dart';
import 'package:fireplace/widgets/message/gif_message_content.dart';
import 'package:fireplace/widgets/message/image_message_content.dart';
import 'package:fireplace/widgets/message/media_preview_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

final _tinyPng = Uint8List.fromList(const [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(
    body: MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
      ],
      child: child,
    ),
  ),
);

MessageModel _mediaMessage(MessageType type) => MessageModel(
  id: type == MessageType.image ? 1 : 2,
  content: '',
  senderId: 1,
  senderUsername: 'alice',
  conversationId: 10,
  deliveryStatus: MessageDeliveryStatus.read,
  messageType: type,
  createdAt: DateTime(2026, 1, 1, 14, 30),
  mediaUrl: 'https://res.cloudinary.com/demo/image/upload/test.png',
  mediaWidth: 1,
  mediaHeight: 1,
);

Future<void> _withFakeMediaFetch(
  Uint8List bytes,
  Future<void> Function() body,
) => HttpOverrides.runZoned<Future<void>>(
  body,
  createHttpClient: (_) => _FakeHttpClient(bytes),
);

void main() {
  group('MediaPreviewFrame.calculateSize', () {
    test('uses source aspect ratio for ordinary media', () {
      final size = MediaPreviewFrame.calculateSize(
        availableWidth: 320,
        viewportHeight: 800,
        devicePixelRatio: 2,
        mediaWidth: 800,
        mediaHeight: 600,
      );

      expect(size.width, 320);
      expect(size.height, 240);
    });

    test('caps panoramas at a stable 3:1 frame', () {
      final size = MediaPreviewFrame.calculateSize(
        availableWidth: 320,
        viewportHeight: 800,
        devicePixelRatio: 2,
        mediaWidth: 3000,
        mediaHeight: 500,
      );

      expect(size.width, 320);
      expect(size.height, closeTo(320 / 3, 0.001));
    });

    test('caps tall media at a stable 1:2 frame', () {
      final size = MediaPreviewFrame.calculateSize(
        availableWidth: 320,
        viewportHeight: 800,
        devicePixelRatio: 2,
        mediaWidth: 500,
        mediaHeight: 2000,
      );

      expect(size.width, 240);
      expect(size.height, 480);
    });

    test('keeps tiny media tappable without taking full row width', () {
      final size = MediaPreviewFrame.calculateSize(
        availableWidth: 320,
        viewportHeight: 800,
        devicePixelRatio: 2,
        mediaWidth: 40,
        mediaHeight: 40,
      );

      expect(size.width, 96);
      expect(size.height, 96);
    });

    test('uses the legacy 220px fallback when dimensions are absent', () {
      final size = MediaPreviewFrame.calculateSize(
        availableWidth: 320,
        viewportHeight: 800,
        devicePixelRatio: 2,
        mediaWidth: null,
        mediaHeight: null,
      );

      expect(size.width, 320);
      expect(size.height, MediaPreviewFrame.legacyHeight);
    });
  });

  group('media preview containment', () {
    testWidgets('IMAGE preview renders fetched bytes with BoxFit.contain', (
      tester,
    ) async {
      await _withFakeMediaFetch(_tinyPng, () async {
        await tester.pumpWidget(
          _wrap(ImageMessageContent(message: _mediaMessage(MessageType.image))),
        );
        await tester.pumpAndSettle();

        final memoryImages = tester
            .widgetList<Image>(find.byType(Image))
            .where((image) => image.image is MemoryImage)
            .toList();
        expect(memoryImages, hasLength(1));
        expect(memoryImages.single.fit, BoxFit.contain);
        expect(memoryImages.any((image) => image.fit == BoxFit.cover), isFalse);
      });
    });

    testWidgets('GIF preview renders fetched bytes with BoxFit.contain', (
      tester,
    ) async {
      await _withFakeMediaFetch(_tinyPng, () async {
        await tester.pumpWidget(
          _wrap(GifMessageContent(message: _mediaMessage(MessageType.gif))),
        );
        await tester.pumpAndSettle();

        final memoryImages = tester
            .widgetList<Image>(find.byType(Image))
            .where((image) => image.image is MemoryImage)
            .toList();
        expect(memoryImages, hasLength(1));
        expect(memoryImages.single.fit, BoxFit.contain);
        expect(memoryImages.any((image) => image.fit == BoxFit.cover), isFalse);
      });
    });
  });
}

class _FakeHttpClient implements HttpClient {
  final Uint8List bytes;

  _FakeHttpClient(this.bytes);

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _FakeHttpClientRequest(bytes);

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientRequest implements HttpClientRequest {
  final Uint8List bytes;

  _FakeHttpClientRequest(this.bytes);

  @override
  final HttpHeaders headers = _FakeHttpHeaders();

  @override
  Encoding encoding = utf8;

  @override
  bool followRedirects = true;

  @override
  int maxRedirects = 5;

  @override
  int contentLength = -1;

  @override
  bool persistentConnection = true;

  @override
  Future<HttpClientResponse> get done async => _FakeHttpClientResponse(bytes);

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final _ in stream) {}
  }

  @override
  void add(List<int> data) {}

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}

  @override
  Future<HttpClientResponse> close() async => _FakeHttpClientResponse(bytes);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  final Uint8List bytes;

  _FakeHttpClientResponse(this.bytes);

  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => bytes.length;

  @override
  HttpHeaders get headers => _FakeHttpHeaders();

  @override
  bool get isRedirect => false;

  @override
  bool get persistentConnection => false;

  @override
  String get reasonPhrase => 'OK';

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.fromIterable([bytes]).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpHeaders implements HttpHeaders {
  final Map<String, List<String>> _headers = {};

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {
    _headers.putIfAbsent(name.toLowerCase(), () => []).add(value.toString());
  }

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _headers[name.toLowerCase()] = [value.toString()];
  }

  @override
  List<String>? operator [](String name) => _headers[name.toLowerCase()];

  @override
  void forEach(void Function(String name, List<String> values) action) {
    _headers.forEach(action);
  }

  @override
  String? value(String name) => this[name]?.join(',');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
