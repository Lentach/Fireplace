// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Fireplace';

  @override
  String get settings => 'Settings';

  @override
  String get theme => 'Theme';

  @override
  String get language => 'Language';

  @override
  String get languagePolish => 'Polish';

  @override
  String get languageEnglish => 'English';

  @override
  String get privacyAndSafety => 'Privacy and Safety';

  @override
  String get blocked => 'Blocked';

  @override
  String get devices => 'Devices';

  @override
  String get resetPassword => 'Reset Password';

  @override
  String get deleteAccount => 'Delete Account';

  @override
  String get logout => 'Logout';

  @override
  String get chat => 'Chat';

  @override
  String get contacts => 'Contacts';

  @override
  String get profilePictureUpdated => 'Profile picture updated';

  @override
  String get uploadFailed => 'Upload failed';

  @override
  String get passwordUpdatedSuccessfully => 'Password updated successfully';

  @override
  String get passwordResetFailed => 'Password reset failed';

  @override
  String get accountDeletionFailed => 'Account deletion failed';

  @override
  String get loading => 'Loading…';

  @override
  String get devicesLoading => 'Loading…';

  @override
  String get privacySafetyTitle => 'Privacy & Safety';

  @override
  String get e2eEncryptionEnabled => 'End-to-end encryption is enabled';

  @override
  String get e2eEncryptionDescription =>
      'Your messages are encrypted using the Signal Protocol. Only you and the recipient can read them. Not even Fireplace servers can access your message content.';

  @override
  String get yourEncryptionKeys => 'Your encryption keys';

  @override
  String get yourEncryptionKeysDescription =>
      'Keys are stored securely on this device. If you switch devices or reinstall the app, a new set of keys will be generated and previous message history cannot be recovered.';

  @override
  String get singleDeviceEncryption => 'Single-device encryption';

  @override
  String get singleDeviceEncryptionDescription =>
      'Each device has its own encryption keys. Messages are tied to the device that sent or received them.';

  @override
  String get webKeyStorage => 'Web: key storage';

  @override
  String get webKeyStorageDescription =>
      'On web, keys are stored in the browser (encrypted with WebCrypto). Someone with access to this device could potentially read them. For maximum security, use the mobile app.';

  @override
  String get whatIsEncrypted => 'What is encrypted';

  @override
  String get whatIsEncryptedDescription =>
      'Text messages and link previews are end-to-end encrypted. Media files (images, voice messages, drawings) are not yet encrypted end-to-end.';

  @override
  String get serverStoresMetadata => 'What the server stores (metadata)';

  @override
  String get serverStoresMetadataDescription =>
      'To deliver messages, the server stores: who is in each conversation, when messages were sent, and delivery status. Message content is never visible to the server.';

  @override
  String get yourIdentityFingerprint => 'Your identity fingerprint';

  @override
  String get shareFingerprintHint =>
      'Share this with your contacts to verify your identity.';

  @override
  String get addInvitations => 'Add / Invitations';

  @override
  String get addUser => 'Add user';

  @override
  String get friendRequests => 'Friend requests';

  @override
  String friendRequestSentTo(String handle) {
    return 'Friend request sent to $handle';
  }

  @override
  String get addNewUserHint =>
      'Add new user by username#tag (e.g. username#1234). Your #tag is in Settings, next to your nickname. Each #tag is unique.';

  @override
  String get usernameTagPlaceholder => 'username#1234';

  @override
  String get addNewUser => 'Add new user';

  @override
  String get userNotFound => 'User not found';

  @override
  String get noPendingRequests => 'No pending requests';

  @override
  String get wantsToAddYouAsFriend => 'wants to add you as a friend';

  @override
  String get accept => 'Accept';

  @override
  String get reject => 'Reject';

  @override
  String friendAdded(String name) {
    return 'Friend added: $name';
  }

  @override
  String get requestRejected => 'Request rejected';

  @override
  String get encryptedMessage => 'Encrypted message';

  @override
  String get decryptionFailed => 'Decryption failed';

  @override
  String get encryptionNotInitialized => 'Encryption not initialized';

  @override
  String get blockUser => 'Block user';

  @override
  String get conversationDeletedByOther =>
      'Conversation deleted by the other user';

  @override
  String get noMessagesYet => 'No messages yet';

  @override
  String get cantMessageThisUser => 'You can\'t message this user';

  @override
  String get cantTypeToThisUser => 'You can\'t type to this user';

  @override
  String get recordingVoice => 'Recording voice…';

  @override
  String get typing => 'typing…';

  @override
  String get selectAConversation => 'Select a conversation';

  @override
  String get noConversationsYet => 'No chats yet';

  @override
  String get startNewChatToBegin => 'Start a new chat to begin';

  @override
  String get deleteConversationTitle => 'Delete Conversation?';

  @override
  String get deleteConversationConfirm =>
      'This will delete all messages in this conversation. You can re-open the chat later from Contacts.';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get voiceMessage => 'Voice message';

  @override
  String get image => 'Image';

  @override
  String get ping => 'Ping';

  @override
  String get unknown => 'Unknown';

  @override
  String get noBlockedUsers => 'No blocked users';

  @override
  String get unblock => 'Unblock';

  @override
  String get removeFriendTitle => 'Remove Friend?';

  @override
  String removeFriendConfirm(String name) {
    return 'Remove $name from your contacts? This will delete all conversation history.';
  }

  @override
  String get remove => 'Remove';

  @override
  String get noContactsYet => 'No contacts yet';

  @override
  String get addFriendsToStart => 'Add friends to start chatting';

  @override
  String get block => 'Block';

  @override
  String get imageFailedToLoad => 'Image failed to load';

  @override
  String get unsupportedMessageType => 'Unsupported message type';

  @override
  String get resetPasswordDialogTitle => 'Reset Password';

  @override
  String get oldPassword => 'Old Password';

  @override
  String get newPassword => 'New Password';

  @override
  String get passwordRequired => 'Password is required';

  @override
  String get passwordMinLength => 'Password must be at least 8 characters';

  @override
  String get passwordMustContain =>
      'Password must contain uppercase, lowercase, and number';

  @override
  String get oldPasswordRequired => 'Old password is required';

  @override
  String get resetButton => 'Reset';

  @override
  String get deleteAccountDialogTitle => 'Delete Account';

  @override
  String get deleteAccountWarning =>
      'This action is permanent and cannot be undone. All your messages and conversations will be deleted.';

  @override
  String get enterPasswordToConfirm => 'Enter password to confirm';

  @override
  String get clearingChat => 'Clearing…';
}
