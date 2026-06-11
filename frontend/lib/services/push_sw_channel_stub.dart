/// Non-web — there is no push service worker; messages are never deliverable.
class PushSwChannel {
  /// Returns `true` only when the message reached the push SW (never here).
  Future<bool> postMessage(Map<String, Object?> message) async => false;
}

PushSwChannel createPushSwChannel() => PushSwChannel();
