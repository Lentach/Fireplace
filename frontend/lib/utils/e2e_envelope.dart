import 'dart:convert';

/// E2E encrypted message envelope format. Single source of truth for build/parse.
class E2eEnvelope {
  E2eEnvelope._();

  static const String _keyContent = 'content';
  static const String _keyMessageType = 'messageType';
  static const String _keyMediaUrl = 'mediaUrl';
  static const String _keyMediaDuration = 'mediaDuration';
  static const String _keyMediaKey = 'mediaKey';
  static const String _keyMediaIv = 'mediaIv';
  static const String _keyMediaWidth = 'mediaWidth';
  static const String _keyMediaHeight = 'mediaHeight';
  static const String _keyMediaThumbHash = 'mediaThumbHash';
  static const int _maximumMediaDimension = 32768;
  static const String _keyLinkPreview = 'linkPreview';
  static const String _keyUrl = 'url';
  static const String _keyTitle = 'title';
  static const String _keyImageUrl = 'imageUrl';

  /// The §5.2 layer-2 device-list cross-check (spec §12 amendment (xv)). Lives
  /// INSIDE the E2E plaintext: the server never sees it. Unknown keys are
  /// ignored by [parse], so an older peer simply omits it (the `linkPreview`
  /// precedent, root `CLAUDE.md` §7).
  static const String _keySenderListInfo = 'senderListInfo';

  static Map<String, dynamic> build(
    String content, {
    String messageType = 'TEXT',
    String? mediaUrl,
    int? mediaDuration,
    String? mediaKey,
    String? mediaIv,
    int? mediaWidth,
    int? mediaHeight,
    String? mediaThumbHash,
    Map<String, String?>? linkPreview,
    Map<String, dynamic>? senderListInfo,
  }) {
    final envelope = <String, dynamic>{_keyContent: content};
    if (messageType != 'TEXT') envelope[_keyMessageType] = messageType;
    if (mediaUrl != null) envelope[_keyMediaUrl] = mediaUrl;
    if (mediaDuration != null) envelope[_keyMediaDuration] = mediaDuration;
    if (mediaKey != null) envelope[_keyMediaKey] = mediaKey;
    if (mediaIv != null) envelope[_keyMediaIv] = mediaIv;
    if (_areValidMediaDimensions(mediaWidth, mediaHeight)) {
      envelope[_keyMediaWidth] = mediaWidth;
      envelope[_keyMediaHeight] = mediaHeight;
    }
    if (mediaThumbHash != null && mediaThumbHash.isNotEmpty) {
      envelope[_keyMediaThumbHash] = mediaThumbHash;
    }
    if (linkPreview != null) envelope[_keyLinkPreview] = linkPreview;
    if (senderListInfo != null && senderListInfo.isNotEmpty) {
      envelope[_keySenderListInfo] = senderListInfo;
    }
    return envelope;
  }

  static ({
    String content,
    String messageType,
    String? mediaUrl,
    int? mediaDuration,
    String? mediaKey,
    String? mediaIv,
    int? mediaWidth,
    int? mediaHeight,
    String? mediaThumbHash,
    String? linkPreviewUrl,
    String? linkPreviewTitle,
    String? linkPreviewImageUrl,
    Object? senderListInfo,
  })
  parse(String jsonStr) {
    final envelope = jsonDecode(jsonStr) as Map<String, dynamic>;
    final content = envelope[_keyContent] as String? ?? '';
    final messageType = envelope[_keyMessageType] as String? ?? 'TEXT';
    final mediaUrl = envelope[_keyMediaUrl] as String?;
    final rawDuration = envelope[_keyMediaDuration];
    final mediaDuration = rawDuration is num ? rawDuration.round() : null;
    final mediaWidth = envelope[_keyMediaWidth];
    final mediaHeight = envelope[_keyMediaHeight];
    final validDimensions = _areValidMediaDimensions(mediaWidth, mediaHeight);
    final rawThumbHash = envelope[_keyMediaThumbHash];
    final mediaThumbHash = rawThumbHash is String ? rawThumbHash : null;
    final lp = envelope[_keyLinkPreview] as Map<String, dynamic>?;
    return (
      content: content,
      messageType: messageType,
      mediaUrl: mediaUrl,
      mediaDuration: mediaDuration,
      mediaKey: envelope[_keyMediaKey] as String?,
      mediaIv: envelope[_keyMediaIv] as String?,
      mediaWidth: validDimensions ? mediaWidth as int : null,
      mediaHeight: validDimensions ? mediaHeight as int : null,
      mediaThumbHash:
          validDimensions && mediaThumbHash != null && mediaThumbHash.isNotEmpty
          ? mediaThumbHash
          : null,
      linkPreviewUrl: lp?[_keyUrl] as String?,
      linkPreviewTitle: lp?[_keyTitle] as String?,
      linkPreviewImageUrl: lp?[_keyImageUrl] as String?,
      senderListInfo: envelope[_keySenderListInfo],
    );
  }

  static bool _areValidMediaDimensions(Object? width, Object? height) =>
      width is int &&
      height is int &&
      width > 0 &&
      height > 0 &&
      width <= _maximumMediaDimension &&
      height <= _maximumMediaDimension;
}
