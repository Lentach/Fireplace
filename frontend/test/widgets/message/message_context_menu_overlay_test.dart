import 'package:fireplace/l10n/app_localizations.dart';
import 'package:fireplace/models/message_model.dart';
import 'package:fireplace/providers/auth_provider.dart';
import 'package:fireplace/providers/messaging_provider.dart';
import 'package:fireplace/providers/settings_provider.dart';
import 'package:fireplace/theme/rpg_theme.dart';
import 'package:fireplace/widgets/message/chat_message_bubble.dart';
import 'package:fireplace/widgets/message/message_context_menu_bubble_highlight.dart';
import 'package:fireplace/widgets/message/context_menu_bubble_anchor.dart';
import 'package:fireplace/widgets/message/message_context_menu_overlay.dart';
import 'package:fireplace/widgets/message/message_bubble_inline_time.dart';
import 'package:fireplace/widgets/message_swipe_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

MessageModel _msg({required int id, required int senderId}) => MessageModel(
      id: id,
      content: 'hello',
      senderId: senderId,
      senderUsername: 'alice',
      conversationId: 1,
      createdAt: DateTime(2026, 5, 23),
      deliveryStatus: MessageDeliveryStatus.sent,
      messageType: MessageType.text,
    );

MessageModel _imageMsg({required int id, required int senderId}) => MessageModel(
      id: id,
      content: '',
      senderId: senderId,
      senderUsername: 'alice',
      conversationId: 1,
      createdAt: DateTime(2026, 5, 23),
      deliveryStatus: MessageDeliveryStatus.sent,
      messageType: MessageType.image,
    );

void main() {
  group('messageBubbleUsesInlineTime', () {
    test('short text without reply uses inline time', () {
      final msg = _msg(id: 1, senderId: 1);
      expect(
        messageBubbleUsesInlineTime(message: msg, displayContent: 'hello'),
        isTrue,
      );
    });

    test('long text or newline uses stacked time', () {
      final msg = _msg(id: 1, senderId: 1);
      expect(
        messageBubbleUsesInlineTime(
          message: msg,
          displayContent: 'this message is definitely too long',
        ),
        isFalse,
      );
      expect(
        messageBubbleUsesInlineTime(message: msg, displayContent: 'line\nbreak'),
        isFalse,
      );
    });

    test('reply or link preview disables inline time', () {
      final msg = _msg(id: 1, senderId: 1).copyWith(
        replyTo: const ReplyToPreview(
          id: 2,
          content: 'quoted',
          senderUsername: 'bob',
          messageType: MessageType.text,
        ),
      );
      expect(
        messageBubbleUsesInlineTime(message: msg, displayContent: 'hi'),
        isFalse,
      );

      final withPreview = _msg(id: 1, senderId: 1).copyWith(
        linkPreviewUrl: 'https://example.com',
      );
      expect(
        messageBubbleUsesInlineTime(message: withPreview, displayContent: 'hi'),
        isFalse,
      );
    });

    test('ping uses inline time; image and file do not', () {
      final ping = _msg(id: 1, senderId: 1).copyWith(
        messageType: MessageType.ping,
        content: 'Ping!',
      );
      expect(
        messageBubbleUsesInlineTime(message: ping, displayContent: 'Ping!'),
        isTrue,
      );

      final image = _imageMsg(id: 1, senderId: 1);
      expect(
        messageBubbleUsesInlineTime(message: image, displayContent: ''),
        isFalse,
      );

      final file = _msg(id: 1, senderId: 1).copyWith(
        messageType: MessageType.file,
        content: 'doc.pdf',
      );
      expect(
        messageBubbleUsesInlineTime(message: file, displayContent: 'doc.pdf'),
        isFalse,
      );
    });
  });

  group('computeMessageContextMenuLayout', () {
    const viewPadding = EdgeInsets.only(top: 48, left: 0, right: 0, bottom: 34);
    const viewSize = Size(390, 844);
    const panelHeight = kMessageActionPanelHeightEstimate;
    const emojiHeight = kMessageContextMenuEmojiRowHeight;
    const gap = kMessageContextMenuOverlayGap;

    double scaleOverflow(double bubbleHeight) =>
        bubbleHighlightScaleOverflow(bubbleHeight);

    test('layout rect subtracts anchor bottom margin from render box', () {
      const anchorRect = Rect.fromLTWH(80, 300, 200, 58);
      final layoutRect = bubbleRectForContextMenuLayout(anchorRect);
      expect(layoutRect.height, 48);
      expect(layoutRect.top, anchorRect.top);
      expect(layoutRect.left, anchorRect.left);
      expect(layoutRect.width, anchorRect.width);
    });

    test('standard layout keeps equal gaps around bubble highlight', () {
      const bubbleRect = Rect.fromLTWH(120, 400, 200, 40);
      final layout = computeMessageContextMenuLayout(
        bubbleRect: bubbleRect,
        viewPadding: viewPadding,
        viewSize: viewSize,
        keyboardBottom: 0,
      );
      final scalePad = scaleOverflow(bubbleRect.height);

      expect(layout.panelAboveBubble, isFalse);
      expect(
        layout.emojiTop + emojiHeight + gap,
        closeTo(layout.bubbleHighlightTop - scalePad, 0.001),
      );
      expect(
        layout.bubbleHighlightTop + bubbleRect.height + scalePad + gap,
        closeTo(layout.panelTop, 0.001),
      );
      expect(
        layout.panelTop + panelHeight,
        lessThanOrEqualTo(viewSize.height - 88),
      );
    });

    test('standard layout keeps equal gaps for tall media bubble (220dp)', () {
      const bubbleRect = Rect.fromLTWH(120, 400, 200, kMessageMediaBubbleHeight);
      final layout = computeMessageContextMenuLayout(
        bubbleRect: bubbleRect,
        viewPadding: viewPadding,
        viewSize: viewSize,
        keyboardBottom: 0,
      );
      final scalePad = scaleOverflow(bubbleRect.height);

      expect(layout.panelAboveBubble, isFalse);
      expect(
        layout.emojiTop + emojiHeight + gap,
        closeTo(layout.bubbleHighlightTop - scalePad, 0.001),
      );
      expect(
        layout.bubbleHighlightTop + bubbleRect.height + scalePad + gap,
        closeTo(layout.panelTop, 0.001),
      );
      expect(
        layout.panelTop + panelHeight,
        lessThanOrEqualTo(viewSize.height - 88),
      );
    });

    test('near bottom shifts stack so full panel fits above composer', () {
      const bubbleRect = Rect.fromLTWH(16, 680, 200, 40);
      final maxContentBottom = viewSize.height - 88;
      final layout = computeMessageContextMenuLayout(
        bubbleRect: bubbleRect,
        viewPadding: viewPadding,
        viewSize: viewSize,
        keyboardBottom: 0,
      );
      final scalePad = scaleOverflow(bubbleRect.height);

      expect(
        layout.panelTop + panelHeight,
        lessThanOrEqualTo(maxContentBottom),
      );
      expect(layout.bubbleHighlightTop, lessThan(bubbleRect.top));
      expect(
        layout.emojiTop + emojiHeight + gap,
        closeTo(layout.bubbleHighlightTop - scalePad, 0.001),
      );
      expect(
        layout.bubbleHighlightTop + bubbleRect.height + scalePad + gap,
        closeTo(layout.panelTop, 0.001),
      );
    });

    test('bottom message at y ~720 keeps all four action rows within bounds', () {
      const bubbleRect = Rect.fromLTWH(16, 720, 200, 40);
      final maxContentBottom = viewSize.height - 88;
      final layout = computeMessageContextMenuLayout(
        bubbleRect: bubbleRect,
        viewPadding: viewPadding,
        viewSize: viewSize,
        keyboardBottom: 0,
      );

      expect(
        layout.panelTop + panelHeight,
        lessThanOrEqualTo(maxContentBottom),
      );
      expect(layout.panelTop, greaterThanOrEqualTo(viewPadding.top));
      expect(layout.panelTop + panelHeight - layout.panelTop, panelHeight);
    });

    test('Telegram order: emoji top < bubble top < panel top when centered', () {
      const bubbleRect = Rect.fromLTWH(80, 300, 220, 56);
      final layout = computeMessageContextMenuLayout(
        bubbleRect: bubbleRect,
        viewPadding: viewPadding,
        viewSize: viewSize,
        keyboardBottom: 0,
      );
      final scalePad = scaleOverflow(bubbleRect.height);

      expect(layout.emojiTop, lessThan(layout.bubbleHighlightTop));
      expect(
        layout.panelTop,
        greaterThan(layout.bubbleHighlightTop + bubbleRect.height + scalePad),
      );
    });

    test('inverted layout preserves gaps between emoji panel and bubble', () {
      const bubbleRect = Rect.fromLTWH(16, 52, 200, 40);
      final layout = computeMessageContextMenuLayout(
        bubbleRect: bubbleRect,
        viewPadding: viewPadding,
        viewSize: viewSize,
        keyboardBottom: 0,
      );

      expect(layout.panelAboveBubble, isTrue);
      expect(layout.emojiTop, viewPadding.top);
      expect(layout.panelTop, layout.emojiTop + emojiHeight + gap);
      expect(
        layout.bubbleHighlightTop,
        layout.panelTop + panelHeight + gap,
      );
    });
  });

  group('horizontal alignment helpers', () {
    const viewPadding = EdgeInsets.only(top: 48, left: 16, right: 16, bottom: 34);
    const viewSize = Size(390, 844);

    test('received panel aligns to bubble left edge', () {
      const bubbleRect = Rect.fromLTWH(16, 400, 220, 40);
      final left = computePanelLeft(
        bubbleRect: bubbleRect,
        viewPadding: viewPadding,
        viewSize: viewSize,
        isMine: false,
        panelWidth: 180,
      );
      expect(left, bubbleRect.left);
    });

    test('sent panel aligns to bubble right edge', () {
      const bubbleRect = Rect.fromLTWH(194, 400, 180, 40);
      final left = computePanelLeft(
        bubbleRect: bubbleRect,
        viewPadding: viewPadding,
        viewSize: viewSize,
        isMine: true,
        panelWidth: 180,
      );
      expect(left, bubbleRect.right - 180);
    });

    test('received emoji bar aligns to bubble left edge', () {
      const bubbleRect = Rect.fromLTWH(16, 400, 220, 40);
      const emojiBarWidth = 248.0;
      final left = computeEmojiBarLeft(
        bubbleRect: bubbleRect,
        viewPadding: viewPadding,
        viewSize: viewSize,
        isMine: false,
        emojiBarWidth: emojiBarWidth,
      );
      expect(left, bubbleRect.left);
    });

    test('sent emoji bar aligns to bubble right edge', () {
      const bubbleRect = Rect.fromLTWH(126, 400, 248, 40);
      const emojiBarWidth = 248.0;
      final left = computeEmojiBarLeft(
        bubbleRect: bubbleRect,
        viewPadding: viewPadding,
        viewSize: viewSize,
        isMine: true,
        emojiBarWidth: emojiBarWidth,
      );
      expect(left, bubbleRect.right - emojiBarWidth);
    });
  });

  testWidgets('ChatMessageBubble short text has equal top and bottom gaps', (tester) async {
    final msg = _msg(id: 10, senderId: 1);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: RpgTheme.themeDataLight,
        home: Scaffold(
          body: MultiProvider(
            providers: [
              ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
              ChangeNotifierProvider<MessagingProvider>(
                create: (_) => MessagingProvider(),
              ),
              ChangeNotifierProvider<SettingsProvider>(
                create: (_) => SettingsProvider(),
              ),
            ],
            child: SizedBox(
              width: 390,
              height: 600,
              child: ChatMessageBubble(message: msg, isMine: true),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byType(MessageSwipeWrapper));
    await tester.pumpAndSettle();

    final highlight = tester.renderObject(
      find.byKey(const Key('context-menu-bubble-highlight')),
    ) as RenderBox;
    final emoji = tester.renderObject(
      find.byKey(const Key('context-menu-emoji-bar')),
    ) as RenderBox;
    final panel = tester.renderObject(
      find.byKey(const Key('context-menu-action-panel')),
    ) as RenderBox;

    final highlightTop = highlight.localToGlobal(Offset.zero).dy;
    final layoutHeight = highlight.size.height;
    final highlightVisualTop = bubbleHighlightVisualTop(
      bubbleHighlightTop: highlightTop,
      layoutBubbleHeight: layoutHeight,
    );
    final highlightVisualBottom = bubbleHighlightVisualBottom(
      bubbleHighlightTop: highlightTop,
      layoutBubbleHeight: layoutHeight,
    );
    final emojiBottom = emoji.localToGlobal(Offset.zero).dy + emoji.size.height;
    final panelTop = panel.localToGlobal(Offset.zero).dy;

    final topGap = highlightVisualTop - emojiBottom;
    final bottomGap = panelTop - highlightVisualBottom;

    expect(topGap, closeTo(kMessageContextMenuOverlayGap, 1.0));
    expect(bottomGap, closeTo(kMessageContextMenuOverlayGap, 1.0));
    expect(topGap, closeTo(bottomGap, 1.0));
  });

  testWidgets('ChatMessageBubble image message has equal top and bottom gaps', (tester) async {
    final msg = _imageMsg(id: 11, senderId: 1);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: RpgTheme.themeDataLight,
        home: Scaffold(
          body: MultiProvider(
            providers: [
              ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
              ChangeNotifierProvider<MessagingProvider>(
                create: (_) => MessagingProvider(),
              ),
              ChangeNotifierProvider<SettingsProvider>(
                create: (_) => SettingsProvider(),
              ),
            ],
            child: SizedBox(
              width: 390,
              height: 700,
              child: ChatMessageBubble(message: msg, isMine: true),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byType(MessageSwipeWrapper));
    await tester.pumpAndSettle();

    final highlight = tester.renderObject(
      find.byKey(const Key('context-menu-bubble-highlight')),
    ) as RenderBox;
    final emoji = tester.renderObject(
      find.byKey(const Key('context-menu-emoji-bar')),
    ) as RenderBox;
    final panel = tester.renderObject(
      find.byKey(const Key('context-menu-action-panel')),
    ) as RenderBox;

    final highlightTop = highlight.localToGlobal(Offset.zero).dy;
    final layoutHeight = highlight.size.height;
    expect(layoutHeight, closeTo(kMessageMediaBubbleHeight, 1.0));

    final highlightVisualTop = bubbleHighlightVisualTop(
      bubbleHighlightTop: highlightTop,
      layoutBubbleHeight: layoutHeight,
    );
    final highlightVisualBottom = bubbleHighlightVisualBottom(
      bubbleHighlightTop: highlightTop,
      layoutBubbleHeight: layoutHeight,
    );
    final emojiBottom = emoji.localToGlobal(Offset.zero).dy + emoji.size.height;
    final panelTop = panel.localToGlobal(Offset.zero).dy;

    final topGap = highlightVisualTop - emojiBottom;
    final bottomGap = panelTop - highlightVisualBottom;

    expect(topGap, closeTo(kMessageContextMenuOverlayGap, 2.0));
    expect(bottomGap, closeTo(kMessageContextMenuOverlayGap, 2.0));
    expect(topGap, closeTo(bottomGap, 2.0));
    expect(panelTop, greaterThan(highlightVisualBottom));
  });

  testWidgets('ChatMessageBubble long-press opens context menu overlay', (tester) async {
    final msg = _msg(id: 10, senderId: 1);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: RpgTheme.themeDataLight,
        home: Scaffold(
          body: MultiProvider(
            providers: [
              ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
              ChangeNotifierProvider<MessagingProvider>(
                create: (_) => MessagingProvider(),
              ),
              ChangeNotifierProvider<SettingsProvider>(
                create: (_) => SettingsProvider(),
              ),
            ],
            child: SizedBox(
              width: 390,
              height: 600,
              child: ChatMessageBubble(message: msg, isMine: true),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byType(MessageSwipeWrapper));
    await tester.pumpAndSettle();

    expect(find.text('Reply'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Pin'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byType(MessageContextMenuBubbleHighlight), findsOneWidget);
  });

  testWidgets('long-press entry shows four action labels and blur scrim', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: RpgTheme.themeDataLight,
        home: Scaffold(
          body: MultiProvider(
            providers: [
              ChangeNotifierProvider<SettingsProvider>(
                create: (_) => SettingsProvider(),
              ),
            ],
            child: Builder(
              builder: (ctx) => Center(
                child: GestureDetector(
                  onLongPress: () {
                    final box = ctx.findRenderObject() as RenderBox;
                    openMessageContextMenu(
                      context: ctx,
                      message: _msg(id: 10, senderId: 1),
                      bubbleRenderBox: box,
                      isMine: true,
                      currentUserId: 1,
                      onReply: () {},
                      onPin: () {},
                      onDelete: () {},
                      onReaction: (emoji, alreadyReacted) {},
                      bubblePreviewBuilder: (_) =>
                          MessageContextMenuBubbleHighlight(
                        message: _msg(id: 10, senderId: 1),
                        isMine: true,
                        maxWidth: 120,
                      ),
                    );
                  },
                  child: const Text('bubble'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.longPress(find.text('bubble'));
    await tester.pumpAndSettle();
    expect(find.text('Reply'), findsOneWidget);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Pin'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('rendered gaps match overlay constant with scale overflow', (tester) async {
    final bubbleKey = GlobalKey();
    final msg = _msg(id: 10, senderId: 1);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: RpgTheme.themeDataLight,
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: GestureDetector(
                onLongPress: () {
                  final box =
                      bubbleKey.currentContext!.findRenderObject() as RenderBox;
                  openMessageContextMenu(
                    context: ctx,
                    message: msg,
                    bubbleRenderBox: box,
                    isMine: true,
                    currentUserId: 1,
                    onReply: () {},
                    onPin: () {},
                    onDelete: () {},
                    onReaction: (_, _) {},
                    bubblePreviewBuilder: (_) =>
                        MessageContextMenuBubbleHighlight(
                      message: msg,
                      isMine: true,
                      maxWidth: 200,
                    ),
                  );
                },
                child: SizedBox(
                  key: bubbleKey,
                  width: 200,
                  height: 58,
                  child: ColoredBox(color: Colors.blue),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.longPress(find.byKey(bubbleKey));
    await tester.pumpAndSettle();

    final highlight = tester.renderObject(
      find.byKey(const Key('context-menu-bubble-highlight')),
    ) as RenderBox;
    final emoji = tester.renderObject(
      find.byKey(const Key('context-menu-emoji-bar')),
    ) as RenderBox;
    final panel = tester.renderObject(
      find.byKey(const Key('context-menu-action-panel')),
    ) as RenderBox;

    final layoutHeight = 58 - kContextMenuAnchorBottomMargin;
    final highlightTop = highlight.localToGlobal(Offset.zero).dy;
    final highlightVisualBottom = bubbleHighlightVisualBottom(
      bubbleHighlightTop: highlightTop,
      layoutBubbleHeight: layoutHeight,
    );
    final emojiBottom = emoji.localToGlobal(Offset.zero).dy + emoji.size.height;
    final panelTop = panel.localToGlobal(Offset.zero).dy;

    final highlightVisualTop = bubbleHighlightVisualTop(
      bubbleHighlightTop: highlightTop,
      layoutBubbleHeight: layoutHeight,
    );
    final topGap = highlightVisualTop - emojiBottom;
    final bottomGap = panelTop - highlightVisualBottom;

    expect(topGap, closeTo(kMessageContextMenuOverlayGap, 1.0));
    expect(bottomGap, closeTo(kMessageContextMenuOverlayGap, 1.0));
    expect(topGap, closeTo(bottomGap, 1.0));
    expect(emoji.size.height, kMessageContextMenuEmojiRowHeight);

    final emojiGlobal = emoji.localToGlobal(Offset.zero);
    final emojiTrailing = emojiGlobal.dx + emoji.size.width;
    final highlightTrailing =
        highlight.localToGlobal(Offset.zero).dx + highlight.size.width;
    expect(emojiTrailing, closeTo(highlightTrailing, 1.0));
  });
}
