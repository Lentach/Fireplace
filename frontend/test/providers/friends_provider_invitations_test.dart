import 'package:fireplace/models/invitation_state.dart';
import 'package:fireplace/providers/friends_provider.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> friendRequestJson({
  required int id,
  required int senderId,
  required String senderName,
  required int receiverId,
  required String receiverName,
  int? conversationId,
  bool? chatReady,
}) {
  return {
    'id': id,
    'sender': {'id': senderId, 'username': senderName},
    'receiver': {'id': receiverId, 'username': receiverName},
    'status': 'pending',
    'createdAt': '2026-07-28T12:00:00.000Z',
    'conversationId': conversationId,
    'chatReady': ?chatReady,
  };
}

void main() {
  group('FriendsProvider invitation state', () {
    test('tracks send, accept, and decline actions until their result', () {
      final provider = FriendsProvider();

      provider.sendFriendRequest(2);
      expect(provider.sendActionFor(2), InvitationActionStatus.inFlight);
      provider.onFriendRequestFailed({
        'action': 'send',
        'requestId': null,
        'recipientId': 2,
        'reason': 'duplicate_request',
      });
      expect(provider.sendActionFor(2), isNull);
      expect(provider.consumeInvitationFailure()?.action, InvitationAction.send);

      provider.acceptFriendRequest(10);
      expect(provider.invitationActionFor(10), InvitationActionStatus.inFlight);
      provider.onFriendRequestFailed({
        'action': 'accept',
        'requestId': 10,
        'recipientId': null,
        'reason': 'accept_failed',
      });
      expect(provider.invitationActionFor(10), isNull);
      expect(
        provider.consumeInvitationFailure()?.action,
        InvitationAction.accept,
      );

      provider.rejectFriendRequest(11);
      expect(provider.invitationActionFor(11), InvitationActionStatus.inFlight);
      provider.onFriendRequestFailed({
        'action': 'reject',
        'requestId': 11,
        'recipientId': null,
        'reason': 'reject_failed',
      });
      expect(provider.invitationActionFor(11), isNull);
      expect(
        provider.consumeInvitationFailure()?.action,
        InvitationAction.decline,
      );
    });

    test('decline keeps its row until rejected and failure leaves it in place', () {
      final provider = FriendsProvider();
      final request = friendRequestJson(
        id: 10,
        senderId: 2,
        senderName: 'bob',
        receiverId: 1,
        receiverName: 'alice',
      );
      provider.onFriendRequestsList([request]);

      provider.rejectFriendRequest(10);
      expect(provider.invitationActionFor(10), InvitationActionStatus.inFlight);
      expect(provider.friendRequests, hasLength(1));

      provider.onFriendRequestFailed({
        'action': 'reject',
        'requestId': 10,
        'recipientId': null,
        'reason': 'reject_failed',
      });
      expect(provider.invitationActionFor(10), isNull);
      expect(provider.friendRequests, hasLength(1));

      provider.rejectFriendRequest(10);
      provider.onFriendRequestRejected(request);
      expect(provider.invitationActionFor(10), isNull);
      expect(provider.friendRequests, isEmpty);
    });

    test('reciprocal accept resolves identity and direction by peer user id', () {
      final provider = FriendsProvider();
      final emitted = <Map<String, dynamic>>[];
      provider.setEmitCallback(
        (event, data) => emitted.add({'event': event, 'data': data}),
      );
      provider.setCurrentUserId(1);
      provider.onFriendRequestsList([
        friendRequestJson(
          id: 41,
          senderId: 2,
          senderName: 'bob',
          receiverId: 1,
          receiverName: 'alice',
        ),
      ]);

      provider.acceptFriendRequest(41);
      provider.sendFriendRequest(2);
      expect(provider.invitationActionFor(41), InvitationActionStatus.inFlight);
      expect(provider.sendActionFor(2), InvitationActionStatus.inFlight);

      provider.onFriendRequestAccepted(
        friendRequestJson(
          id: 99,
          senderId: 1,
          senderName: 'alice',
          receiverId: 2,
          receiverName: 'bob',
          conversationId: 77,
          chatReady: true,
        ),
      );

      final outcome = provider.acceptedOutcomeForPeer(2);
      expect(provider.sendActionFor(2), isNull);
      expect(provider.invitationActionFor(41), isNull);
      expect(provider.friendRequests, isEmpty);
      expect(provider.acceptedOutcomesFor(InvitationDirection.outgoing), [outcome]);
      expect(outcome?.direction, InvitationDirection.outgoing);
      expect(outcome?.requestId, 99);
      expect(outcome?.conversationId, 77);
      expect(provider.consumePendingFriendAccepted()?.peerUserId, 2);
      expect(emitted.where((event) => event['event'] == 'friendRequestSent'), isEmpty);
    });

    test('reciprocal accept still toasts the original sender whose row the payload does not name', () {
      // Alice invited Bob (row #41). Bob then invited Alice, so the backend
      // auto-accepted and returned the BRAND-NEW Bob->Alice row #99. From Alice's
      // seat the payload reads sender=bob/receiver=alice, so any payload-role gate
      // would decide she is the accepter and swallow her "Bob accepted your
      // invitation" toast. Her locally resolved direction is outgoing, and that is
      // what must drive it.
      final provider = FriendsProvider();
      provider.setCurrentUserId(1);
      provider.onSentRequestsList([
        friendRequestJson(
          id: 41,
          senderId: 1,
          senderName: 'alice',
          receiverId: 2,
          receiverName: 'bob',
        ),
      ]);

      provider.onFriendRequestAccepted(
        friendRequestJson(
          id: 99,
          senderId: 2,
          senderName: 'bob',
          receiverId: 1,
          receiverName: 'alice',
          conversationId: 77,
          chatReady: true,
        ),
      );

      expect(provider.sentRequests, isEmpty);
      expect(provider.acceptedOutcomeForPeer(2)?.direction, InvitationDirection.outgoing);
      final accepted = provider.consumePendingFriendAccepted();
      expect(accepted?.name, 'bob');
      expect(accepted?.peerUserId, 2);
      expect(accepted?.conversationId, 77);
      expect(accepted?.chatReady, isTrue);
    });

    test('the plain accepter gets no sender toast', () {
      final provider = FriendsProvider();
      provider.setCurrentUserId(1);
      provider.onFriendRequestsList([
        friendRequestJson(
          id: 41,
          senderId: 2,
          senderName: 'bob',
          receiverId: 1,
          receiverName: 'alice',
        ),
      ]);
      provider.acceptFriendRequest(41);

      provider.onFriendRequestAccepted(
        friendRequestJson(
          id: 41,
          senderId: 2,
          senderName: 'bob',
          receiverId: 1,
          receiverName: 'alice',
          conversationId: 77,
          chatReady: true,
        ),
      );

      expect(provider.acceptedOutcomeForPeer(2)?.direction, InvitationDirection.incoming);
      expect(provider.consumePendingFriendAccepted(), isNull);
    });

    test('friendRequestSent atomically adds the sent row without later duplicates', () {
      final provider = FriendsProvider();
      provider.setCurrentUserId(1);
      final request = friendRequestJson(
        id: 12,
        senderId: 1,
        senderName: 'alice',
        receiverId: 2,
        receiverName: 'bob',
      );

      provider.sendFriendRequest(2);
      provider.onFriendRequestSent(request);
      expect(provider.sendActionFor(2), isNull);
      expect(provider.sentRequests.map((entry) => entry.id), [12]);

      provider.onSentRequestsList([request]);
      expect(provider.sentRequests.map((entry) => entry.id), [12]);
    });

    test('accepted swap preserves sections and emits no refetch', () {
      final incoming = FriendsProvider();
      final emitted = <Map<String, dynamic>>[];
      var notifications = 0;
      incoming.setEmitCallback(
        (event, data) => emitted.add({'event': event, 'data': data}),
      );
      incoming.setCurrentUserId(1);
      final request = friendRequestJson(
        id: 20,
        senderId: 2,
        senderName: 'bob',
        receiverId: 1,
        receiverName: 'alice',
      );
      incoming.onFriendRequestsList([request]);
      incoming.addListener(() => notifications++);
      incoming.acceptFriendRequest(20);
      emitted.clear();
      notifications = 0;

      incoming.onFriendRequestAccepted(
        friendRequestJson(
          id: 20,
          senderId: 2,
          senderName: 'bob',
          receiverId: 1,
          receiverName: 'alice',
          conversationId: null,
          chatReady: false,
        ),
      );

      final incomingOutcome = incoming.acceptedOutcomeForPeer(2);
      expect(notifications, 1);
      expect(emitted, isEmpty);
      expect(incoming.friendRequests, isEmpty);
      expect(incoming.sentRequests, isEmpty);
      expect(
        incoming.acceptedOutcomesFor(InvitationDirection.incoming),
        [incomingOutcome],
      );
      expect(incomingOutcome?.chatReady, isFalse);
      incoming.clearAcceptedOutcome(2);
      expect(incoming.acceptedOutcomeForPeer(2), isNull);

      final sender = FriendsProvider();
      sender.setCurrentUserId(2);
      sender.onSentRequestsList([request]);
      sender.onFriendRequestAccepted(
        friendRequestJson(
          id: 20,
          senderId: 2,
          senderName: 'bob',
          receiverId: 1,
          receiverName: 'alice',
          conversationId: 88,
          chatReady: true,
        ),
      );

      final outgoingOutcome = sender.acceptedOutcomeForPeer(1);
      expect(sender.friendRequests, isEmpty);
      expect(sender.sentRequests, isEmpty);
      expect(sender.acceptedOutcomesFor(InvitationDirection.outgoing), [
        outgoingOutcome,
      ]);
      expect(outgoingOutcome?.conversationId, 88);
      expect(sender.consumePendingFriendAccepted()?.conversationId, 88);
    });

    test('scoped failures clear only their matching key and reset chat retry', () {
      final provider = FriendsProvider();
      provider.sendFriendRequest(2);
      provider.acceptFriendRequest(10);
      provider.rejectFriendRequest(11);

      provider.onFriendRequestFailed({
        'action': 'accept',
        'requestId': 10,
        'recipientId': null,
        'reason': 'accept_failed',
      });
      expect(provider.invitationActionFor(10), isNull);
      expect(provider.invitationActionFor(11), InvitationActionStatus.inFlight);
      expect(provider.sendActionFor(2), InvitationActionStatus.inFlight);

      provider.setCurrentUserId(1);
      provider.onFriendRequestsList([
        friendRequestJson(
          id: 21,
          senderId: 3,
          senderName: 'carol',
          receiverId: 1,
          receiverName: 'alice',
        ),
      ]);
      provider.onFriendRequestAccepted(
        friendRequestJson(
          id: 21,
          senderId: 3,
          senderName: 'carol',
          receiverId: 1,
          receiverName: 'alice',
          conversationId: null,
          chatReady: false,
        ),
      );
      provider.ensureInvitationChat(3);
      expect(provider.acceptedOutcomeForPeer(3)?.retrying, isTrue);

      provider.onFriendRequestFailed({
        'action': 'ensure_chat',
        'requestId': null,
        'recipientId': 3,
        'reason': 'not_friends',
      });
      final failure = provider.consumeInvitationFailure();
      expect(provider.acceptedOutcomeForPeer(3)?.retrying, isFalse);
      expect(provider.acceptedOutcomeForPeer(3)?.retryToken, isNull);
      expect(failure?.action, InvitationAction.ensureChat);
      expect(failure?.recipientId, 3);
    });

    test('chat retry ignores stale attempt results', () {
      final provider = FriendsProvider();
      final emitted = <Map<String, dynamic>>[];
      provider.setEmitCallback(
        (event, data) => emitted.add({'event': event, 'data': data}),
      );
      provider.setCurrentUserId(1);
      provider.onFriendRequestsList([
        friendRequestJson(
          id: 30,
          senderId: 2,
          senderName: 'bob',
          receiverId: 1,
          receiverName: 'alice',
        ),
      ]);
      provider.onFriendRequestAccepted(
        friendRequestJson(
          id: 30,
          senderId: 2,
          senderName: 'bob',
          receiverId: 1,
          receiverName: 'alice',
          conversationId: null,
          chatReady: false,
        ),
      );

      provider.ensureInvitationChat(2);
      provider.ensureInvitationChat(2);
      final firstToken = (emitted[0]['data'] as Map<String, dynamic>)['correlationId'];
      final secondToken = (emitted[1]['data'] as Map<String, dynamic>)['correlationId'];
      expect(secondToken, isNot(firstToken));

      provider.onInvitationChatReady({
        'peerUserId': 2,
        'correlationId': secondToken,
        'conversationId': 70,
        'chatReady': true,
      });
      provider.onInvitationChatReady({
        'peerUserId': 2,
        'correlationId': firstToken,
        'conversationId': null,
        'chatReady': false,
      });

      final outcome = provider.acceptedOutcomeForPeer(2);
      expect(outcome?.chatReady, isTrue);
      expect(outcome?.conversationId, 70);
      expect(outcome?.retrying, isFalse);
      expect(outcome?.retryToken, isNull);
    });

    test('invitation snapshots load only after both lists and reset fresh', () {
      final provider = FriendsProvider();
      expect(provider.hasLoadedInvitationsOnce, isFalse);

      provider.onFriendRequestsList([]);
      expect(provider.hasLoadedInvitationsOnce, isFalse);
      provider.onSentRequestsList([]);
      expect(provider.hasLoadedInvitationsOnce, isTrue);

      provider.onConnect(false);
      expect(provider.hasLoadedInvitationsOnce, isFalse);
    });

    test('reconnect preserves outcomes but fresh connect removes them', () {
      final provider = FriendsProvider();
      provider.setCurrentUserId(1);
      provider.onFriendRequestsList([
        friendRequestJson(
          id: 40,
          senderId: 2,
          senderName: 'bob',
          receiverId: 1,
          receiverName: 'alice',
        ),
      ]);
      provider.onSentRequestsList([]);
      provider.onFriendRequestAccepted(
        friendRequestJson(
          id: 40,
          senderId: 2,
          senderName: 'bob',
          receiverId: 1,
          receiverName: 'alice',
          conversationId: null,
          chatReady: false,
        ),
      );
      provider.ensureInvitationChat(2);
      provider.sendFriendRequest(3);
      provider.acceptFriendRequest(4);
      expect(provider.acceptedOutcomeForPeer(2)?.retryToken, isNotNull);
      expect(provider.sendActionFor(3), InvitationActionStatus.inFlight);
      expect(provider.invitationActionFor(4), InvitationActionStatus.inFlight);

      provider.onConnect(true);
      final outcomeAfterReconnect = provider.acceptedOutcomeForPeer(2);
      expect(outcomeAfterReconnect, isNotNull);
      expect(outcomeAfterReconnect?.retrying, isFalse);
      expect(outcomeAfterReconnect?.retryToken, isNull);
      expect(provider.sendActionFor(3), isNull);
      expect(provider.invitationActionFor(4), isNull);
      expect(provider.hasLoadedInvitationsOnce, isTrue);

      provider.onConnect(false);
      expect(provider.acceptedOutcomeForPeer(2), isNull);
      expect(provider.hasLoadedInvitationsOnce, isFalse);
    });
  });
}
