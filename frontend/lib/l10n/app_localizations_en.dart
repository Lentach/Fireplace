// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

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
  String get uninstallWarning =>
      'Uninstalling or clearing site data permanently erases your message history — to refresh, just fully close and reopen the app.';

  @override
  String get chat => 'Chats';

  @override
  String get contacts => 'Contacts';

  @override
  String get uploadFailed => 'Upload failed';

  @override
  String get passwordUpdatedSuccessfully => 'Password updated successfully';

  @override
  String get passwordResetFailed => 'Password reset failed';

  @override
  String get accountDeletionFailed => 'Account deletion failed';

  @override
  String get devicesLoading => 'Loading…';

  @override
  String get settingsAppVersion => 'App version';

  @override
  String get settingsAboutFireplace => 'About Fireplace';

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
      'This device may keep downloaded voice audio locally. Clearing this cache removes downloaded audio only; it does not delete readable message history, media keys, encryption keys, sessions, or browser storage.';

  @override
  String get clearLocalMessageCache => 'Clear downloaded audio cache';

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
  String get emojiPickerSemantics => 'Emoji picker';

  @override
  String get emojiPickerSearchHint => 'Search emoji';

  @override
  String get emojiPickerNoRecents => 'No recent emoji';

  @override
  String emojiPickerEmojiOptionSemantics(String emoji) {
    return 'Emoji $emoji';
  }

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
  String get attachmentOptionDocument => 'Document';

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
  String get authTagline => 'Messages only two people can read';

  @override
  String get authLoginTab => 'LOGIN';

  @override
  String get authRegisterTab => 'REGISTER';

  @override
  String get authUsernameHint => 'Username';

  @override
  String get authUsernameRequired => 'Username is required';

  @override
  String get authPasswordHint => 'Password';

  @override
  String get authPasswordHintRegister => 'Password (min 8 chars)';

  @override
  String get authLoginButton => 'Login';

  @override
  String get authCreateAccountButton => 'Create Account';

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
  String get antiQuantumNoteTitle => 'Anti-Quantum Note';

  @override
  String get antiQuantumNoteHint => 'Write your secret message...';

  @override
  String get antiQuantumNoteTtl1h => '1h';

  @override
  String get antiQuantumNoteTtl6h => '6h';

  @override
  String get antiQuantumNoteTtl12h => '12h';

  @override
  String get antiQuantumNoteTtl24h => '24h';

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
  String get antiQuantumNoteCardSubtitle => 'One-time read · Tap to open';

  @override
  String antiQuantumNoteCardCountdown(String time) {
    return 'Self-destructs in $time';
  }

  @override
  String get antiQuantumNoteCardDestroyed => 'This note has self-destructed';

  @override
  String get antiQuantumNoteBurnedTitle => 'Note destroyed';

  @override
  String get antiQuantumNoteBurnedSubtitle => 'it was read';

  @override
  String get privacyAntiQuantumNoteTitle => 'Anti-Quantum Notes';

  @override
  String get privacyAntiQuantumNoteDescription =>
      'Notes are encrypted on your device before upload — the server stores only unreadable ciphertext, and the decryption key travels solely inside the link\'s #fragment, which browsers never send to any server. A note can be revealed exactly once, then it is permanently deleted. Unopened notes self-destruct when their timer (1h–24h) runs out, and the chat message disappears with them.';

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
  String get saveImage => 'Save image';

  @override
  String get copyImage => 'Copy image';

  @override
  String get imageSaved => 'Image saved';

  @override
  String get imageSaveFailed => 'Failed to save image';

  @override
  String get imageCopied => 'Image copied';

  @override
  String get imageCopyFailed => 'Failed to copy image';

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
  String get messageTooLong => 'Message is too long to send';

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
  String get snackbarNoMicrophoneFound => 'No microphone found';

  @override
  String get snackbarVoiceRecordingRequiresSecureContext =>
      'Voice recording needs HTTPS or localhost. Use https:// or open from localhost.';

  @override
  String get snackbarFailedToStartRecording => 'Failed to start recording';

  @override
  String get snackbarVoiceRecordingCanceled => 'Voice recording canceled';

  @override
  String get voiceRecordingSendVoiceTooltip => 'Send voice message';

  @override
  String get voiceRecordingSendVoiceSemantics => 'Send voice message';

  @override
  String get voiceRecordingDiscard => 'Discard recording';

  @override
  String voiceRecordingSemanticsLabel(String time) {
    return 'Recording voice message, $time.';
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
  String get appearance => 'Appearance';

  @override
  String appearanceSummary(String theme, String background) {
    return '$theme · $background';
  }

  @override
  String get appearanceColorTheme => 'COLOR THEME';

  @override
  String get appearanceThemeLight => 'Warm Paper';

  @override
  String get appearanceThemeTeal => 'Teal Stone';

  @override
  String get appearanceThemeDark => 'Wire';

  @override
  String get appearanceThemeBlue => 'Blue';

  @override
  String get appearanceThemeCosmic => 'Cosmic';

  @override
  String get themeOptionLight => 'Warm paper with ember accents';

  @override
  String get themeOptionDark => 'Neutral charcoal with teal accents';

  @override
  String get themeOptionBlue => 'Deep blue messenger palette';

  @override
  String get themeOptionTealStone => 'Cool stone with modern teal';

  @override
  String get themeOptionCosmic => 'Dark space with ice-blue light';

  @override
  String get appearanceChatBackground => 'CHAT BACKGROUND';

  @override
  String get appearanceBackgroundThemeDefault => 'Theme default';

  @override
  String get appearanceBackgroundThemeDefaultSubtitle =>
      'Follows the selected color theme';

  @override
  String get appearanceBackgroundThemeDefaultCosmicSubtitle =>
      'Animated starfield for Cosmic';

  @override
  String get appearanceBackgroundPlain => 'Plain';

  @override
  String get appearanceBackgroundPlainSubtitle => 'Solid themed chat surface';

  @override
  String get appearanceBackgroundGlyphs => 'Hieroglyphs';

  @override
  String get appearanceBackgroundGlyphsSubtitle => 'Temple-column pattern';

  @override
  String get appearanceBackgroundStarfield => 'Starfield';

  @override
  String get rotateDeviceTitle => 'Rotate your device';

  @override
  String get rotateDeviceMessage => 'Fireplace works in portrait mode only.';

  @override
  String get messageActionReply => 'Reply';

  @override
  String get messageActionCopy => 'Copy';

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
  String get messageEditedLabel => 'edited';

  @override
  String get messageEditingTitle => 'Editing message';

  @override
  String get messagePinRequiresSentMessage =>
      'Wait until the message is sent before pinning';

  @override
  String get messageReactionMoreEmoji => 'More emoji reactions';

  @override
  String get messageReactionSelected => 'selected';

  @override
  String get messageReactionNotSelected => 'not selected';

  @override
  String messageReactionSemantics(Object emoji, Object state) {
    return 'Reaction $emoji, $state';
  }

  @override
  String get snackbarPinnedMessageUnavailable =>
      'Message is no longer available';

  @override
  String get snackbarMessageCopied => 'Message copied';

  @override
  String get composerAttachmentRemoveTooltip => 'Remove attachment';

  @override
  String get snackbarPastedImageTooLarge => 'Image is too large (max 20 MB)';

  @override
  String get snackbarPastedImageUnsupported =>
      'This image type can\'t be pasted';

  @override
  String get snackbarPastedImageUnavailable =>
      'Couldn\'t read the pasted image';

  @override
  String get pinnedMessageUnpinTooltip => 'Unpin';

  @override
  String get pinnedMessageBannerSemantics => 'Pinned message';

  @override
  String get userCardAbout => 'About';

  @override
  String get userCardMyProfile => 'My profile';

  @override
  String get userCardEditAbout => 'Edit About';

  @override
  String get userCardAddPhoto => 'Add photo';

  @override
  String get userCardPhotoLimitReached => 'Photo limit reached';

  @override
  String get userCardSetMainPhoto => 'Set as main photo';

  @override
  String get userCardDeletePhoto => 'Delete this photo';

  @override
  String get userCardSave => 'Save';

  @override
  String get userCardCancel => 'Cancel';

  @override
  String get userCardBack => 'Back';

  @override
  String get userCardNotificationsOn => 'Notifications on';

  @override
  String get userCardMuteOneHour => 'Mute for 1 hour';

  @override
  String get userCardMuteEightHours => 'Mute for 8 hours';

  @override
  String get userCardMuteOneWeek => 'Mute for 1 week';

  @override
  String get userCardMuteForever => 'Mute forever';

  @override
  String get userCardMessage => 'Message';

  @override
  String get userCardMute => 'Mute';

  @override
  String get userCardMuted => 'Muted';

  @override
  String get userCardCopyTag => 'Copy tag';

  @override
  String get userCardManagePhotos => 'Manage photos';

  @override
  String userCardPhotoOfCount(Object index, Object count) {
    return 'Photo $index of $count';
  }

  @override
  String get userCardMainPhotoHint =>
      'This is your main photo — contacts see it in chats.';

  @override
  String get userCardAboutHint => 'A few words about you';

  @override
  String get userCardSharedMedia => 'Shared media';

  @override
  String get userCardDragReorderHint =>
      'Hold and drag to reorder — the first photo is your main photo.';

  @override
  String get settingsChatBackground => 'Chat background';

  @override
  String get userCardCopyHandle => 'Copy username and tag';

  @override
  String userCardCopiedHandle(Object handle) {
    return 'Copied $handle';
  }

  @override
  String get userCardNotificationsMuted => 'Notifications muted';

  @override
  String userCardBlockTitle(Object handle) {
    return 'Block $handle?';
  }

  @override
  String get userCardBlockConfirm =>
      'You will no longer be able to message this contact.';

  @override
  String get userCardDeletePhotoTitle => 'Delete photo?';

  @override
  String get userCardDeletePhotoConfirm =>
      'This permanently deletes this profile photo.';

  @override
  String get userCardSafety => 'Safety';

  @override
  String get userCardRemoveContact => 'Remove contact';

  @override
  String get messageReadMore => 'Read more';

  @override
  String get messageShowLess => 'Show less';
}
