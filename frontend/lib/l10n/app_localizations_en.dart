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
      'Add Umbra to Home Screen first (Safari -> Share -> Add to Home Screen)';

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
  String get devicesExplainer =>
      'Devices linked to this account. A new device can only be added from this, the primary device.';

  @override
  String get devicesNotEnrolled =>
      'Device linking is not enabled for this account yet.';

  @override
  String get devicesEnableLinking => 'Enable linking';

  @override
  String get devicesLinkADevice => 'Link a device';

  @override
  String get devicesLinkThisDevice => 'Link this device';

  @override
  String get devicesAlreadyEnrolled =>
      'Another installation of this account already enabled linking. Devices can only be added from that device.';

  @override
  String get devicesEnrollFailed => 'Could not enable linking. Try again.';

  @override
  String get devicesChainInvalid =>
      'The device list could not be verified. Try again later.';

  @override
  String get devicesRevokedBadge => 'revoked';

  @override
  String get devicesRevokeAction => 'Remove device';

  @override
  String get devicesRevokeTitle => 'Remove this device?';

  @override
  String get devicesRevokeExplainer =>
      'It will be signed out and will stop receiving new messages. Messages already on that device are not erased.';

  @override
  String get devicesRevokeFailed => 'Could not remove that device. Try again.';

  @override
  String get deviceRevokedNotice =>
      'This device was removed from your account. Your messages on it were kept — to keep chatting here, sign in and link this device again.';

  @override
  String get deviceMismatchTitle => 'This device was removed from the account';

  @override
  String get deviceMismatchBody =>
      'This device\'s encryption keys belong to a device that was removed from your account, so it stopped sending and receiving encrypted messages. To keep chatting here, link this device again from your other device. Nothing changed on your other devices.';

  @override
  String get deviceMismatchAction => 'Link this device';

  @override
  String get devicesPrimaryBadge => 'primary';

  @override
  String get devicesThisDeviceKeyless =>
      'This device holds no keys yet. Link it to your primary device.';

  @override
  String get linkPrimaryTitle => 'Link a device';

  @override
  String get linkPrimaryExplainer =>
      'On the new device choose “Link this device”, then type the code it shows here.';

  @override
  String get linkPrimaryCodeLabel => 'Code from the new device';

  @override
  String get linkPrimaryContinue => 'Continue';

  @override
  String get linkSasHeading => 'Compare the codes';

  @override
  String get linkSasExplainer =>
      'Both devices must show the same code. Approve only if they match exactly.';

  @override
  String get linkApprove => 'Approve';

  @override
  String get linkCancel => 'Cancel';

  @override
  String get linkWaitingForDevice => 'Waiting for the new device…';

  @override
  String get linkPrimaryDone => 'The device has been linked.';

  @override
  String get linkInvalidCode =>
      'Invalid code. Copy it exactly from the new device.';

  @override
  String get linkNoDak =>
      'No authorization key on this device. Linking is only possible from the device that enabled linking.';

  @override
  String get linkFailed => 'Linking failed';

  @override
  String get linkStaleVersionRetry =>
      'The device list changed mid-flight — re-signing…';

  @override
  String get linkNewTitle => 'Link this device';

  @override
  String get linkNewExplainer =>
      'Show this code on your primary device: choose “Link a device” there and type the code (or scan the QR).';

  @override
  String get linkNewWaitingHello => 'Waiting for your primary device…';

  @override
  String get linkNewCopy => 'Copy code';

  @override
  String get linkNewCopied => 'Code copied';

  @override
  String get linkNewCompleting => 'Linking…';

  @override
  String get linkNewRebinding => 'Switching the session to the new device…';

  @override
  String get linkNewDone => 'This device is linked and ready.';

  @override
  String get linkNewAborted => 'Linking aborted';

  @override
  String get linkNewRetry => 'Try again';

  @override
  String get linkAbortReasonExpired => 'The code expired.';

  @override
  String get linkAbortReasonCancelled =>
      'Linking was cancelled on the other device.';

  @override
  String get linkAbortReasonBadBlob =>
      'Verification failed. Every key was removed from this device.';

  @override
  String get settingsAppVersion => 'App version';

  @override
  String get settingsAboutFireplace => 'About';

  @override
  String get settingsSectionPreferences => 'PREFERENCES';

  @override
  String get settingsSectionSecurity => 'SECURITY';

  @override
  String get settingsSectionSession => 'SESSION';

  @override
  String get privacySafetyTitle => 'Privacy & Safety';

  @override
  String get e2eEncryptionEnabled => 'End-to-end encryption is enabled';

  @override
  String get e2eEncryptionDescription =>
      'Your messages are encrypted using the Signal Protocol. Only you and the recipient can read them. Not even Umbra servers can access your message content.';

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
  String get deleteAllLocalHistoryTitle =>
      'Delete all messages stored on this device';

  @override
  String get deleteAllLocalHistoryDescription =>
      'Permanently deletes all messages stored on this device, including downloaded voice notes. It does not delete your account, messages on the other person\'s device, or your encryption keys and sessions. This cannot be undone: the server only ever held ciphertext it cannot read, so there is no copy to restore from.';

  @override
  String get deleteAllLocalHistoryButton =>
      'Permanently delete all local messages';

  @override
  String get deleteAllLocalHistoryDialogTitle =>
      'Permanently delete all local messages?';

  @override
  String get deleteAllLocalHistoryDialogBody =>
      'This permanently deletes every message and downloaded voice note stored on this device. It cannot be undone — the server only ever held ciphertext it cannot read, so there is no copy to restore from. Your account, encryption keys, and sessions are not affected.';

  @override
  String get deleteAllLocalHistoryConfirm => 'Delete permanently';

  @override
  String get yourIdentityFingerprint => 'Your identity fingerprint';

  @override
  String get shareFingerprintHint =>
      'This is a unique representation of your encryption key.';

  @override
  String get invitations => 'Invitations';

  @override
  String get invitationsWaitingForYou => 'Waiting for you';

  @override
  String get invitationsSent => 'Sent';

  @override
  String get invitationsNothingWaiting => 'Nothing waiting for you';

  @override
  String get invitationsNoneSent => 'No sent invitations';

  @override
  String get inviteByHandleHint =>
      'Invite someone by username#tag. Your own #tag is in Settings, next to your nickname.';

  @override
  String get usernameTagPlaceholder => 'username#1234';

  @override
  String get sendInvitation => 'Send invitation';

  @override
  String get invitationFindUser => 'Find user';

  @override
  String get userNotFound => 'User not found';

  @override
  String get invitationWantsToConnect => 'Wants to connect';

  @override
  String get invitationWaitingForResponse => 'Waiting for response';

  @override
  String get invitationAccepted => 'Invitation accepted';

  @override
  String get invitationChatReady => 'Chat ready';

  @override
  String get invitationChatNeedsRetry => 'Chat setup needs retry';

  @override
  String get invitationOpenChat => 'Open chat';

  @override
  String get invitationCreateChat => 'Create chat';

  @override
  String get invitationDone => 'Done';

  @override
  String get invitationDecline => 'Decline';

  @override
  String get accept => 'Accept';

  @override
  String get invitationStatusPending => 'Pending';

  @override
  String get invitationSendFailed => 'Could not send the invitation';

  @override
  String get invitationAcceptFailed => 'Could not accept the invitation';

  @override
  String get invitationDeclineFailed => 'Could not decline the invitation';

  @override
  String get invitationChatSetupFailed => 'Could not set up the chat';

  @override
  String get invitationFailedUserNotFound => 'That user no longer exists';

  @override
  String get invitationFailedSelf => 'You cannot invite yourself';

  @override
  String get invitationFailedBlocked => 'You cannot invite this user';

  @override
  String get invitationFailedAlreadyFriends => 'You are already connected';

  @override
  String get invitationFailedDuplicate => 'Invitation already sent';

  @override
  String get invitationFailedInvalidPayload =>
      'Something was wrong with that request';

  @override
  String get invitationFailedNotFriends =>
      'You are not connected with this user';

  @override
  String invitationSemanticIncoming(String name) {
    return '$name, invitation received, wants to connect';
  }

  @override
  String invitationSemanticOutgoing(String name) {
    return '$name, invitation sent, waiting for response';
  }

  @override
  String invitationSemanticAcceptedReady(String name) {
    return '$name, invitation accepted, chat ready';
  }

  @override
  String invitationSemanticAcceptedNotReady(String name) {
    return '$name, invitation accepted, chat setup needs retry';
  }

  @override
  String get encryptedMessage => 'Encrypted message';

  @override
  String get decryptionFailed => 'Decryption failed';

  @override
  String get decryptingMessage => 'Decrypting…';

  @override
  String get messageNoLongerStoredOnThisDevice =>
      'This message is no longer stored on this device.';

  @override
  String get messageSentBeforeDeviceLinked =>
      'Sent before this device was linked.';

  @override
  String get devicesSyncingNote => 'Syncing your devices…';

  @override
  String get encryptionNotInitialized => 'Encryption not initialized';

  @override
  String get identityDamagedTitle => 'Encryption keys missing on this device';

  @override
  String get identityDamagedBody =>
      'Signed in on a new device or browser? Your account already has encryption keys elsewhere, and this device does not have them. If this is your usual device, its stored keys were lost. Either way nothing was regenerated automatically — doing that silently would destroy your ability to read your history.';

  @override
  String get identityDamagedAction => 'Start fresh';

  @override
  String get messageRetrySend => 'Retry';

  @override
  String get authStatusSavedSessionUnreadable =>
      'Could not read the saved session from this device. Your sign-in may still be there — restart the app to try again.';

  @override
  String get authStatusRegisterSucceeded =>
      'Account created. Sign in to continue.';

  @override
  String get authStatusServerUnreachable =>
      'Cannot reach the server. Check your connection and try again.';

  @override
  String get authStatusUnexpectedError =>
      'Something went wrong. Please try again.';

  @override
  String get identityDamagedRecoveryFailed =>
      'Could not create new encryption keys. Try again.';

  @override
  String get identityAlertShowDetails => 'Details';

  @override
  String get identityAlertHideDetails => 'Hide details';

  @override
  String get identityDamagedConfirmTitle => 'Start with new keys?';

  @override
  String get identityDamagedConfirmBody =>
      'A new identity will be created and your contacts will re-key automatically. Messages you have already opened on this device stay readable. Any message this device never decrypted can never be recovered.';

  @override
  String get identityDamagedConfirmAction => 'Create new keys';

  @override
  String get peerIdentityMarkVerifiedAction => 'Fingerprints match';

  @override
  String get peerIdentityVerifyMenuAction => 'Verify security keys';

  @override
  String get peerIdentityFingerprintDialogTitle => 'Verify security keys';

  @override
  String peerIdentityFingerprintDialogDescription(String name) {
    return 'Compare these fingerprints with $name over another channel. They must match.';
  }

  @override
  String peerIdentityFingerprintPeerLabel(String name) {
    return '$name\'s fingerprint';
  }

  @override
  String get peerIdentityFingerprintNoStoredKey =>
      'No stored identity key is available for this contact.';

  @override
  String peerIdentityFingerprintChangedNotice(String name) {
    return '$name\'s keys have changed. Compare the NEW fingerprint below — the previous one is shown only so you can see what changed.';
  }

  @override
  String peerIdentityFingerprintServedNotice(String name) {
    return 'This key came from the server and no message from $name has confirmed it yet. Comparing it out of band is the only check there is.';
  }

  @override
  String peerIdentityFingerprintNewLabel(String name) {
    return '$name\'s new fingerprint';
  }

  @override
  String get peerIdentityFingerprintPreviousLabel =>
      'Previously trusted fingerprint';

  @override
  String peerIdentityFingerprintOfferChanged(String name) {
    return 'Nothing was confirmed: $name\'s key changed while this was open, so it is not the one you just compared. Compare the fingerprint below again before confirming.';
  }

  @override
  String peerIdentityFingerprintUnchangedNotice(String name) {
    return '$name\'s key has not changed since you last accepted it. Confirm below to dismiss this warning.';
  }

  @override
  String peerIdentityFingerprintOfferUnavailable(String name) {
    return '$name\'s current key could not be loaded, so there is nothing to compare yet. Check your connection and open this again.';
  }

  @override
  String peerIdentityChangedTimelineRow(String name) {
    return '$name\'s security keys have changed — usually a sign-in from a new device or browser. Tap to verify.';
  }

  @override
  String get ownIdentityReplacedTitle => 'New encryption keys on your account';

  @override
  String get ownIdentityReplacedBody =>
      'Another sign-in uploaded new encryption keys for your account — usually a new device, browser, or reinstall. If this wasn\'t you, change your password immediately.';

  @override
  String get ownIdentityReplacedDismissAction => 'Got it';

  @override
  String get identityResetPendingTitle =>
      'Someone asked to reset your encryption keys';

  @override
  String identityResetPendingBody(String remaining) {
    return 'If this wasn\'t you, cancel now — otherwise your account gets new encryption keys in $remaining and your message history becomes unreadable.';
  }

  @override
  String get identityResetCancelAction => 'Cancel it';

  @override
  String identityResetHoursLeft(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours hours',
      one: '1 hour',
    );
    return '$_temp0';
  }

  @override
  String identityResetMinutesLeft(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes minutes',
      one: '1 minute',
      zero: 'under a minute',
    );
    return '$_temp0';
  }

  @override
  String get identityResetAnyMoment => 'any moment now';

  @override
  String get identityUploadLockedTitle =>
      'Your new encryption keys were not published';

  @override
  String get identityUploadLockedBody =>
      'This device made new keys, but the account still uses the previous ones, so other people cannot reach you securely. Start a reset to publish these keys — it takes 72 hours and everyone signed in is notified.';

  @override
  String get identityResetStartAction => 'Start reset';

  @override
  String get recoveryKeyTitle => 'Recovery key';

  @override
  String get recoveryKeySubtitle => 'Get back in faster if you lose your keys';

  @override
  String get recoveryKeyExplainer =>
      'If you ever lose access to your encryption keys, getting new ones takes 72 hours — a deliberate delay, so nobody else can quietly take over your account without you having time to stop it. A recovery key shortens that wait to 1 hour. It never skips the wait, and everyone signed in is still notified.\n\nThe words are shown once and never stored on this device — keeping them here would lose them to the very thing they protect against. Write them down somewhere safe and offline.';

  @override
  String get recoveryKeyGenerateAction => 'Generate recovery key';

  @override
  String get recoveryKeyShownOnceWarning =>
      'These words are shown once. Save them before continuing — generating a new key replaces this one.';

  @override
  String get recoveryKeyCopyAction => 'Copy words';

  @override
  String get recoveryKeyCopied => 'Recovery key copied';

  @override
  String get recoveryKeySavedAction => 'I saved it';

  @override
  String get recoveryKeySaved => 'Recovery key saved';

  @override
  String get recoveryKeySaveFailed =>
      'Could not save the recovery key — nothing was stored, so those words will not work. Please try again.';

  @override
  String get recoveryPhrasePromptTitle => 'Do you have a recovery key?';

  @override
  String get recoveryPhrasePromptBody =>
      'Entering your 12 words shortens the wait from 72 hours to 1. Everyone signed in is notified either way, and the reset can still be cancelled.';

  @override
  String get recoveryPhrasePromptHint => 'twelve words separated by spaces';

  @override
  String get recoveryPhraseMalformed =>
      'That does not look like a complete 12-word recovery key. Check for typos.';

  @override
  String get recoveryPhraseUseAction => 'Use recovery key';

  @override
  String get recoveryPhraseNoneAction => 'I don\'t have one';

  @override
  String get identityResetStarted =>
      'Reset started. Everyone signed in has been told, and it can be cancelled until the countdown ends.';

  @override
  String get identityResetPhraseTooNew =>
      'Reset started. Your recovery key was correct, but it was created less than 3 days ago, so it cannot shorten the wait this time — the full 72 hours apply. There is no need to enter it again.';

  @override
  String get identityResetAlreadyRunning =>
      'A reset is already running for this account. The countdown at the top of the screen shows how long is left.';

  @override
  String get identityResetCooldown =>
      'A reset was cancelled recently, so a new one cannot start for up to 24 hours. If someone else keeps cancelling it, change your password to sign them out first.';

  @override
  String get identityResetPhraseRejected =>
      'Those 12 words did not match the recovery key stored for this account. You can try again, or start the reset without it and wait 72 hours.';

  @override
  String get identityResetPhraseLocked =>
      'Too many recovery-key attempts. Try again in about an hour, or start the reset without the key and wait 72 hours.';

  @override
  String get identityResetNoAnswer =>
      'No answer from the server, so nothing was started. Check your connection and try again.';

  @override
  String get identityFingerprintUnavailable => 'Fingerprint unavailable.';

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
  String get chatComposerEmojiTooltip => 'Emoji';

  @override
  String get chatComposerEmojiSemantics => 'Open emoji picker';

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
  String get contactNetworkLocalNode => 'LOCAL NODE';

  @override
  String get contactNetworkYouLocalNode => 'You, local node';

  @override
  String contactNetworkSemantic(num count) {
    return 'Contact network, $count contacts';
  }

  @override
  String contactNetworkNodes(String count) {
    return 'NODES $count';
  }

  @override
  String get contactNetworkShowList => 'List view';

  @override
  String get contactNetworkShowMap => 'Network view';

  @override
  String get contactNetworkOpenChatHint => 'Open chat';

  @override
  String get contactNetworkAddSlot => 'add';

  @override
  String get contactNetworkAddSlotSemantic => 'Add a contact';

  @override
  String contactNetworkPendingRequests(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count friend requests waiting',
      one: '1 friend request waiting',
    );
    return '$_temp0';
  }

  @override
  String get contactsSearchHint => 'Search contacts';

  @override
  String get contactsSearchNoResults => 'No matching contacts';

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
  String sessionEndedReason(String reason) {
    return 'signed out: $reason';
  }

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
  String get antiQuantumNoteRevealWarning =>
      'This note can be read only once. Revealing it destroys it permanently — for everyone, forever.';

  @override
  String get antiQuantumNoteRevealConfirm => 'Reveal & destroy';

  @override
  String get antiQuantumNoteRevealLoading => 'Decrypting…';

  @override
  String get antiQuantumNoteRevealedHeader =>
      'Message revealed · now permanently destroyed';

  @override
  String get antiQuantumNoteRevealedFooter =>
      'This note has been deleted from the server. Only this screen still shows it.';

  @override
  String get antiQuantumNoteRevealClose => 'Close';

  @override
  String get antiQuantumNoteRevealRetry => 'Try again';

  @override
  String get antiQuantumNoteRevealDestroyedBody =>
      'This note has already been read and destroyed. Nothing can bring it back.';

  @override
  String get antiQuantumNoteRevealExpiredTitle => 'Note expired';

  @override
  String get antiQuantumNoteRevealExpiredBody =>
      'This note expired and destroyed itself before being read.';

  @override
  String get antiQuantumNoteRevealCorruptBody =>
      'The note was destroyed, but it could not be decrypted. The link may be damaged.';

  @override
  String get antiQuantumNoteRevealInvalidLinkTitle => 'Damaged link';

  @override
  String get antiQuantumNoteRevealInvalidLinkBody =>
      'This link is missing a valid decryption key. The note has not been destroyed.';

  @override
  String get antiQuantumNoteRevealNetworkErrorTitle => 'No connection';

  @override
  String get antiQuantumNoteRevealNetworkErrorBody =>
      'The server could not be reached. Check your connection and try again.';

  @override
  String get privacyAntiQuantumNoteTitle => 'Anti-Quantum Notes';

  @override
  String get privacyAntiQuantumNoteLead =>
      'Self-destructing messages with their own second layer of encryption — even the link keeps the secret.';

  @override
  String get privacyAntiQuantumNotePointDevice =>
      'Encrypted on your device before upload — the server stores only unreadable ciphertext.';

  @override
  String get privacyAntiQuantumNotePointKey =>
      'The decryption key travels solely inside the link\'s #fragment, which browsers never send to any server.';

  @override
  String get privacyAntiQuantumNotePointOnce =>
      'A note can be revealed exactly once — then it is permanently deleted.';

  @override
  String get privacyAntiQuantumNotePointTimer =>
      'Unopened notes self-destruct when their timer (1h–24h) runs out, and the chat message disappears with them.';

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
  String get snackbarAllLocalHistoryDeleted =>
      'All messages stored on this device were permanently deleted';

  @override
  String get snackbarFailedToDeleteAllLocalHistory =>
      'Some messages could not be removed from this device. Try again.';

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
  String get appearanceThemeLight => 'Alabaster';

  @override
  String get appearanceThemeTeal => 'Turquoise';

  @override
  String get appearanceThemeDark => 'Graphite';

  @override
  String get appearanceThemeBlue => 'Azure';

  @override
  String get appearanceThemeCosmic => 'Cosmos';

  @override
  String get themeOptionLight => 'Light warm ivory with ember accents';

  @override
  String get themeOptionDark => 'Dark neutral graphite with teal accents';

  @override
  String get themeOptionBlue => 'Deep dark blue with azure accents';

  @override
  String get themeOptionTealStone => 'Light cool stone with turquoise accents';

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
  String get rotateDeviceMessage => 'Umbra works in portrait mode only.';

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

  @override
  String get chatPickerTitle => 'Choose a friend';

  @override
  String get chatPickerSubtitle => 'Pick a node to start chatting';

  @override
  String get chatPickerEmptyTitle => 'No friends yet';

  @override
  String get chatPickerEmptyDescription => 'Add a friend to start a chat.';

  @override
  String get chatPickerOpenTooltip => 'New chat';

  @override
  String get chatPickerInviteButton => 'Invite someone';

  @override
  String get videoMessage => 'Video';

  @override
  String get videoTooLarge => 'Video is too large (max 20 MB)';

  @override
  String get videoTooLong => 'Video is too long (max 60 seconds)';

  @override
  String get videoUnsupportedFormat => 'Unsupported video format (MP4 only)';

  @override
  String get attachmentUnsupportedFileType => 'Unsupported file type';

  @override
  String get chatScrollToBottomSemantics => 'Scroll to newest messages';

  @override
  String get avatarOpenProfileSemantics => 'Open profile';
}
