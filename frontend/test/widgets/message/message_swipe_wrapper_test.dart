import 'package:fireplace/widgets/message_swipe_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('swipe left triggers onSwipeReply', (tester) async {
    var replyCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageSwipeWrapper(
            isMine: true,
            onSwipeReply: () => replyCount++,
            onLongPress: () {},
            child: const SizedBox(width: 200, height: 40),
          ),
        ),
      ),
    );
    await tester.drag(find.byType(MessageSwipeWrapper), const Offset(-80, 0));
    await tester.pumpAndSettle();
    expect(replyCount, 1);
  });

  testWidgets('swipe right does not call delete (no callback exists)', (tester) async {
    var replyCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageSwipeWrapper(
            isMine: true,
            onSwipeReply: () => replyCount++,
            onLongPress: () {},
            child: const SizedBox(width: 200, height: 40),
          ),
        ),
      ),
    );
    await tester.drag(find.byType(MessageSwipeWrapper), const Offset(80, 0));
    await tester.pumpAndSettle();
    expect(replyCount, 0);
  });

  testWidgets('sub-threshold left swipe does not trigger onSwipeReply', (tester) async {
    var replyCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageSwipeWrapper(
            isMine: true,
            onSwipeReply: () => replyCount++,
            onLongPress: () {},
            child: const SizedBox(width: 200, height: 40),
          ),
        ),
      ),
    );
    // -40px is below the 60px reply threshold: an accidental nudge, not a
    // deliberate reply swipe. Reply must NOT fire.
    await tester.drag(find.byType(MessageSwipeWrapper), const Offset(-40, 0));
    await tester.pumpAndSettle();
    expect(replyCount, 0);
  });
}
