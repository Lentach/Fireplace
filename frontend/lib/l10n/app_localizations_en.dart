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
  String get webPushEnableTitle => 'Enable push notifications';

  @override
  String get webPushEnableSubtitle =>
      'Required on iOS after adding app to Home Screen';

  @override
  String get webPushEnabled => 'Push notifications enabled';

  @override
  String get webPushPermissionDenied => 'Push permission denied';

  @override
  String get webPushInstallRequired =>
      'Add Fireplace to Home Screen first (Safari -> Share -> Add to Home Screen)';

  @override
  String get webPushNotSupported =>
      'Push is not supported in this browser/session';

  @override
  String get webPushNoChanges => 'Push is already enabled';

  @override
  String get webPushEnableFailed => 'Failed to enable push';

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
  String get settingsAppVersion => 'App version';

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
      'All messages are end-to-end encrypted (text, images, voice, links). Only you and the recipient can read them.';

  @override
  String get serverStoresMetadata => 'What the server stores (metadata)';

  @override
  String get serverStoresMetadataDescription =>
      'To deliver messages, the server stores: who is in each conversation, when messages were sent, and delivery status. Message content is never visible to the server.';

  @override
  String get localMessageCache => 'Local message cache';

  @override
  String get localMessageCacheDescription =>
      'For reliability, this device may keep decrypted message previews and downloaded voice audio locally. Clearing this cache does not delete your encryption keys or server history.';

  @override
  String get clearLocalMessageCache => 'Clear local message cache';

  @override
  String get yourIdentityFingerprint => 'Your identity fingerprint';

  @override
  String get shareFingerprintHint =>
      'This is a unique representation of your encryption key.';

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
  String get chatMessageHint => 'Type a message...';

  @override
  String get chatComposerSendTooltip => 'Send';

  @override
  String get chatComposerSendSemantics => 'Send message';

  @override
  String get chatDateToday => 'Today';

  @override
  String get chatDateYesterday => 'Yesterday';

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
  String get attachment => 'Attachment';

  @override
  String get attachmentOptionPhoto => 'Photo';

  @override
  String get attachmentOptionDocument => 'Document';

  @override
  String get actionTileTimer => 'Timer';

  @override
  String get actionTileDisappearingMessages => 'Disappearing messages';

  @override
  String get disappearingTimerTitle => 'Disappearing messages';

  @override
  String get disappearingTimerExplainerLine1 =>
      'Messages are removed after they are read.';

  @override
  String get disappearingTimerExplainerLine2 =>
      'The countdown starts when someone opens the chat.';

  @override
  String get disappearingTimerExplainerLine3 =>
      'Only new messages use the timer you set here.';

  @override
  String get disappearingTimerRangeHint =>
      '5 seconds to 30 days, or all zeros to turn off';

  @override
  String get disappearingTimerSetTimer => 'Set timer';

  @override
  String get disappearingTimerTurnOff => 'Turn off';

  @override
  String disappearingTimerSummarySemantics(String summary) {
    return 'Selected duration: $summary';
  }

  @override
  String disappearingComposerBanner(String duration) {
    return 'Disappearing · $duration';
  }

  @override
  String disappearingComposerBannerSemantics(String duration) {
    return 'Disappearing messages, $duration';
  }

  @override
  String conversationDisappearingTimerHint(String duration) {
    return 'Disappearing messages: $duration';
  }

  @override
  String get conversationLastMessageEphemeralPreRead => 'Disappears after read';

  @override
  String conversationLastMessageEphemeralRemaining(String duration) {
    return 'Disappears in $duration';
  }

  @override
  String get disappearingTimerDaysLabel => 'Days';

  @override
  String get disappearingTimerHoursLabel => 'Hours';

  @override
  String get disappearingTimerMinutesLabel => 'Minutes';

  @override
  String get disappearingTimerSecondsLabel => 'Seconds';

  @override
  String get disappearingTimerApply => 'Apply';

  @override
  String get disappearingTimerOff => 'Off';

  @override
  String get disappearingTimerOutOfRange =>
      'Timer must be between 5 seconds and 30 days, or all zeros to turn off.';

  @override
  String disappearingTimerDays(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '1 day',
    );
    return '$_temp0';
  }

  @override
  String disappearingTimerHours(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hours',
      one: '1 hour',
    );
    return '$_temp0';
  }

  @override
  String disappearingTimerMinutes(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count minutes',
      one: '1 minute',
    );
    return '$_temp0';
  }

  @override
  String disappearingTimerSeconds(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count seconds',
      one: '1 second',
    );
    return '$_temp0';
  }

  @override
  String get actionTileGif => 'GIF';

  @override
  String get actionTileAntiQuantumNote => 'Anti-Quantum Note';

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

  @override
  String get gifNoResults => 'No GIFs found';

  @override
  String get gifSearchHint => 'Search GIFs...';

  @override
  String get gifLoadError => 'Could not load GIFs';

  @override
  String get antiQuantumNoteTitle => 'Anti-Quantum Note';

  @override
  String get antiQuantumNoteHint => 'Write your secret message...';

  @override
  String get antiQuantumNoteTtl2h => '2h';

  @override
  String get antiQuantumNoteTtl6h => '6h';

  @override
  String get antiQuantumNoteTtl12h => '12h';

  @override
  String get antiQuantumNoteGenerateAndSend => '🔗 Generate & Send';

  @override
  String get antiQuantumNoteFooter =>
      'Encrypted client-side · Key never leaves your device';

  @override
  String get antiQuantumNoteSent => 'Anti-Quantum Note sent';

  @override
  String antiQuantumNoteSendFailed(String error) {
    return 'Failed to send note: $error';
  }

  @override
  String get documentDownloaded => 'Document downloaded';

  @override
  String get documentDownloadFailed => 'Failed to download document';

  @override
  String get documentDownloadConfirmTitle => 'Download document?';

  @override
  String get documentDownloadConfirmMessage =>
      'Do you want to download this file?';

  @override
  String get download => 'Download';

  @override
  String get snackbarCouldNotReadFile => 'Could not read file';

  @override
  String get snackbarUploadingImage => 'Uploading image…';

  @override
  String get snackbarImageSent => 'Image sent!';

  @override
  String get snackbarUploadingDocument => 'Uploading document…';

  @override
  String get snackbarDocumentSent => 'Document sent!';

  @override
  String get snackbarNoActiveConversation => 'No active conversation';

  @override
  String get snackbarOpenConversationFirst => 'Open a conversation first';

  @override
  String get snackbarChatHistoryDeleted => 'Chat history deleted';

  @override
  String get snackbarFailedToSendImage => 'Failed to send image';

  @override
  String get snackbarMicrophonePermissionRequired =>
      'Microphone permission required';

  @override
  String get snackbarMicrophonePermissionDenied =>
      'Microphone permission denied';

  @override
  String get snackbarVoiceRecordingRequiresSecureContext =>
      'Voice recording needs HTTPS or localhost. Use https:// or open from localhost.';

  @override
  String get snackbarFailedToStartRecording => 'Failed to start recording';

  @override
  String get snackbarHoldLongerForVoiceMessage =>
      'Hold longer to record a voice message';

  @override
  String get snackbarVoiceRecordingCanceled => 'Voice recording canceled';

  @override
  String get voiceRecordingSlideToCancel => '← Slide to cancel';

  @override
  String get voiceRecordingSlideUpToLock => '↑ Slide up to lock';

  @override
  String get voiceRecordingLocked => 'Locked — tap Send when done';

  @override
  String get voiceRecordingCancelLocked => 'Cancel recording';

  @override
  String voiceRecordingSemanticsLabel(String time) {
    return 'Recording voice message, $time. Swipe left to cancel.';
  }

  @override
  String voiceRecordingLockedSemantics(String time) {
    return 'Locked voice recording, $time. Tap Send to send or Cancel to discard.';
  }

  @override
  String get snackbarFailedToReadRecording => 'Failed to read recording';

  @override
  String get snackbarFailedToSendVoiceMessage => 'Failed to send voice message';

  @override
  String get snackbarAudioNoLongerAvailable => 'Audio no longer available';

  @override
  String get snackbarFailedToLoadAudio => 'Failed to load audio';

  @override
  String get snackbarLocalMessageCacheCleared => 'Local message cache cleared';

  @override
  String get snackbarFailedToClearLocalMessageCache =>
      'Failed to clear local message cache';

  @override
  String friendAcceptedYourRequest(String name) {
    return '$name accepted your friend request';
  }

  @override
  String get themeOptionLight => 'Warm paper (light)';

  @override
  String get themeOptionDark => 'Dark gray + teal accent';

  @override
  String get themeOptionBlue => 'Telegram-style blue (dark)';

  @override
  String get themeOptionTealStone => 'Teal + stone (modern light)';

  @override
  String get rotateDeviceTitle => 'Rotate your device';

  @override
  String get rotateDeviceMessage => 'Fireplace works in portrait mode only.';

  @override
  String get messageActionReply => 'Reply';

  @override
  String get messageActionEdit => 'Edit';

  @override
  String get messageActionPin => 'Pin';

  @override
  String get messageActionDelete => 'Delete';

  @override
  String get messageDeleteDialogTitle => 'Delete message?';

  @override
  String get messageDeleteForMe => 'Delete for me';

  @override
  String get messageDeleteForEveryone => 'Delete for everyone';

  @override
  String get messageEditComingSoon => 'Edit is coming soon';

  @override
  String get messagePinRequiresSentMessage =>
      'Wait until the message is sent before pinning';

  @override
  String get snackbarPinnedMessageUnavailable =>
      'Message is no longer available';

  @override
  String get snackbarE2eAskSenderResend =>
      'Some messages could not be unlocked. Ask your contact to send a new message.';

  @override
  String get pinnedMessageUnpinTooltip => 'Unpin';

  @override
  String get pinnedMessageBannerSemantics => 'Pinned message';
}
