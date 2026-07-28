# Invitation-flow research: first-party product evidence

**Date:** 2026-07-28  
**Purpose:** Ground Fireplace's invitation redesign in product behavior that its owner documents publicly. This is not a claim that the products have equivalent data models.

## Reading rules

- **Observed** means the linked first-party source says it or its documented UI establishes it.
- **Not established** means the sources examined do not document the behavior. It is deliberately not filled in from memory, app experimentation, search-result summaries, or third-party tutorials.
- **Recommendation** is an inference for Fireplace, not a claim about another product.
- “Accept opens the chat” is a separate question from “accept makes chat possible.” The sources often establish the latter only.

## Evidence at a glance

| Product | Incoming surface | Receiver action and durable result | Mobile information architecture | Sender status / withdrawal evidence |
|---|---|---|---|---|
| Signal | A message request identifies the person by profile and can show mutual groups. [Signal Support](https://support.signal.org/hc/en-us/articles/360007459591-Signal-Profiles-and-Message-Requests) | Accept adds the person to Signal contacts and permits messages/calls; delete removes the conversation; block prevents contact and does not notify the blocked person. [Signal Support](https://support.signal.org/hc/en-us/articles/360007459591-Signal-Profiles-and-Message-Requests) | The examined article documents the decision card, not a dedicated mobile inbox route. | Not established by the examined support article. |
| Discord | A non-friend DM may be filtered to **Message Requests**; suspected bot DMs may go to a more hidden **Spam** folder. [Discord Support](https://support.discord.com/hc/en-us/articles/7924992471191-Message-Requests) | Approval is required before direct chat. Desktop supports accept/ignore; mobile supports accept/decline. [Discord Support](https://support.discord.com/hc/en-us/articles/7924992471191-Message-Requests) | DM list gains a Message Requests tab only while requests are pending, with a badge. [Discord Support](https://support.discord.com/hc/en-us/articles/7924992471191-Message-Requests) | Not established: the article does not document a sender-facing accepted/declined state or a sender withdrawal action. |
| Instagram | Meta publishes pages for managing message requests and controlling who can send them, but the retrievable first-party pages did not expose the operating steps. [Manage requests](https://help.instagram.com/585369912141614), [request controls](https://help.instagram.com/154475974694511) | Not established from accessible first-party body text. | Not established. | Not established. |
| Messenger | Meta documents a privacy control for who can send messages and message requests, but the retrievable page did not expose request mechanics. [Messenger Help](https://www.facebook.com/help/messenger-app/2258699540867663) | Not established from accessible first-party body text. | Not established. | Not established. |
| Snapchat | The directly retrievable official material documents block/privacy consequences, not a complete inbound-friend-request workflow. [Snapchat Support](https://help.snapchat.com/hc/en-us/articles/7012401093396-How-do-I-block-a-friend-on-Snapchat) | Blocking stops direct Snaps and Chats; the blocked user is not notified. [Snapchat Support](https://help.snapchat.com/hc/en-us/articles/7012401093396-How-do-I-block-a-friend-on-Snapchat) | Not established. | Not established. |
| Session | The first message to a new Account ID is a message request in a separate receiver section. [Session Support](https://sessionapp.zendesk.com/hc/en-us/articles/9347216955289-What-is-a-message-request) | Receiver accepts or denies; accepting moves the conversation into regular contacts, while blocking removes the request. [Session Support](https://sessionapp.zendesk.com/hc/en-us/articles/9347841807897-How-do-I-find-my-message-requests) | Requests appear above regular conversations; mobile finds the folder from the profile picture/settings. [Session Support](https://sessionapp.zendesk.com/hc/en-us/articles/9347841807897-How-do-I-find-my-message-requests) | Not established: the support material does not document a sender pending view, acknowledgement, or cancellation. |
| Matrix / Element | Element documents a **room invitation**, made from the room member list using a Matrix ID or email; Matrix specifies join and leave as the acceptance/rejection membership actions. [Element Help](https://element.io/en/help#chat5), [Matrix join](https://spec.matrix.org/latest/client-server-api/#post_matrixclientv3roomsroomidjoin), [Matrix leave](https://spec.matrix.org/latest/client-server-api/#post_matrixclientv3roomsroomidleave) | Joining accepts room membership; leaving rejects an outstanding invitation. [Matrix specification](https://spec.matrix.org/latest/client-server-api/#post_matrixclientv3roomsroomidleave) | Element documents configurable notification behavior for invites, not a mobile friend-request mailbox. [Element Help](https://element.io/en/help) | Not established by these sources. |

## Product findings

### Signal — the clearest consent-gated direct-contact model

#### Observed

- A Signal message request gives the receiver **block, delete, or accept** choices. For an individual request it shows the sender's name and photo; it can also expose shared groups detected locally, specifically to help the receiver decide whether to continue. [Signal Support: Profiles and Message Requests](https://support.signal.org/hc/en-us/articles/360007459591-Signal-Profiles-and-Message-Requests)
- **Accept** is not merely dismissal of a card: it allows profile visibility, optional read receipts, messages and calls, and adds the person to the recipient's Signal contact list. [Signal Support](https://support.signal.org/hc/en-us/articles/360007459591-Signal-Profiles-and-Message-Requests)
- **Delete** deletes the conversation. **Block** is materially stronger: it stops notifications for messages, calls, and group invites; prevents profile updates being shown; and the blocked contact is not told. [Signal Support](https://support.signal.org/hc/en-us/articles/360007459591-Signal-Profiles-and-Message-Requests)
- Signal says profile data is end-to-end encrypted using a profile key, and that mutual-group detection is performed on-device. [Signal Support](https://support.signal.org/hc/en-us/articles/360007459591-Signal-Profiles-and-Message-Requests)

#### Not established

- The source does **not** say what a sender sees after sending, whether the sender sees acceptance or denial, or whether the sender can withdraw an outstanding request.
- The source establishes that acceptance permits messaging/calling and adds a contact. It does **not** state that Signal automatically navigates the receiver into the conversation or shows a transient success message.

### Discord — a screened-message inbox with conditional mobile entry

#### Observed

- Discord may filter a DM from a non-friend into **Message Requests**, and may put a suspected bot DM in a more hidden **Spam** folder. Discord gives the purpose explicitly: screen unwanted DMs out of the normal DM list. [Discord Support: Message Requests](https://support.discord.com/hc/en-us/articles/7924992471191-Message-Requests)
- The receiver must approve a request before direct chat is possible. On desktop/web, the request view supports profile inspection (including shared servers) plus accept or ignore. The Spam view supports profile inspection plus accept or report; a message can be previewed and ignored. [Discord Support](https://support.discord.com/hc/en-us/articles/7924992471191-Message-Requests)
- Ignored requests cannot be retrieved. The requester may be able to send another request, depending on server and user Message Requests settings. [Discord Support](https://support.discord.com/hc/en-us/articles/7924992471191-Message-Requests)
- On mobile, the DM area exposes a **Message Requests** tab only when at least one request is pending. That tab lists received requests and permits profile viewing plus accept or decline. The client shows a notification badge for requests. [Discord Support](https://support.discord.com/hc/en-us/articles/7924992471191-Message-Requests)
- The screening behavior is configurable per server and globally. Discord further documents special regional/age-assurance constraints and a safety alert for some first DMs to teens. [Discord Support](https://support.discord.com/hc/en-us/articles/7924992471191-Message-Requests)

#### Not established

- Discord's article does not document a sender-facing “pending,” “accepted,” or “declined” state, a sender notification, or cancellation of a sent request.
- “Approve before being able to chat” establishes capability, not automatic navigation into an already-open chat. The source does not specify a success toast, sheet, or route transition.

### Instagram and Messenger — official help acknowledges the category, but is insufficiently observable here

#### Observed

- Instagram's official Help Center exposes a page titled **Manage message requests on Instagram** and a separate control for who can send message requests. [Instagram: manage requests](https://help.instagram.com/585369912141614), [Instagram: request controls](https://help.instagram.com/154475974694511)
- Messenger's official Help Center exposes a privacy page whose description says it controls who can send messages and message requests. [Messenger: control who can message you](https://www.facebook.com/help/messenger-app/2258699540867663)

#### Evidence limitation — do not turn this into false certainty

The first-party pages above returned their titles/descriptions but not their operative help text through the available reader. Therefore this research makes **no factual claim** about Meta's incoming placement, accept/delete controls, recipient navigation, sender acknowledgement, cancellation, or silent-decline behavior. Re-check the native mobile product or an accessible first-party article before treating either product as a behavioral precedent.

### Snapchat — use only its explicit block/privacy behavior

#### Observed

- Snapchat's official block article says a blocked user cannot send the receiver Snaps or Chats. It says the block prevents direct communication, removes the person from several social surfaces, hides the receiver's Snap Map location, and does not notify the blocked person (though they may infer it). [Snapchat Support: blocking](https://help.snapchat.com/hc/en-us/articles/7012401093396-How-do-I-block-a-friend-on-Snapchat)
- Snapchat distinguishes block from removing a friend: removal only takes the person off the Friends list and public content may remain visible, while blocking is the direct-contact stop. [Snapchat Support](https://help.snapchat.com/hc/en-us/articles/7012401093396-How-do-I-block-a-friend-on-Snapchat)

#### Evidence limitation

The directly retrievable official material does not document the complete friend-request lifecycle requested here: incoming request placement, explicit accept/decline labels, post-accept navigation, outgoing state, or request withdrawal. Do not invent those details from third-party screenshots.

### Session — the closest documented “first message becomes consent gate” flow

#### Observed

- The first message to a new Session Account ID is sent as a **message request** and appears in a separate section on the receiver's client. Session calls the construct akin to a friend request and says the separation is intended to prevent continual spam. [Session Support: What is a message request?](https://sessionapp.zendesk.com/hc/en-us/articles/9347216955289-What-is-a-message-request)
- The receiver has accept or deny. Requests from new IDs are shown in their own area above regular messages, allowing visual differentiation from existing conversations and groups. [Session Support: finding requests](https://sessionapp.zendesk.com/hc/en-us/articles/9347841807897-How-do-I-find-my-message-requests)
- Acceptance moves the conversation to the regular contacts area. Blocking removes the request. The folder is also reachable from settings: profile picture on mobile, left-side settings icon on desktop. [Session Support](https://sessionapp.zendesk.com/hc/en-us/articles/9347841807897-How-do-I-find-my-message-requests)

#### Not established

- Session's support material does not document what the original sender sees after sending, whether acceptance/denial is signalled to the sender, or whether a pending outbound request can be withdrawn.
- “Moves to regular contacts” is persistent-state feedback. It does not establish that Session auto-opens the chat or uses a toast after acceptance.

### Matrix / Element — model the protocol as room membership, not a generic social friend request

#### Observed

- Element documents inviting a person **to a room** from the room member list, via Matrix ID or email. It also says someone without a Matrix ID can preview the room when room policy permits it. [Element Help: inviting a contact](https://element.io/en/help#chat5)
- Matrix's first-party specification defines a room join endpoint and a leave endpoint; the leave endpoint explicitly leaves a room **or rejects an outstanding invitation**. [Matrix Client-Server API: join](https://spec.matrix.org/latest/client-server-api/#post_matrixclientv3roomsroomidjoin), [leave/reject](https://spec.matrix.org/latest/client-server-api/#post_matrixclientv3roomsroomidleave)
- Element documents notification preferences that separately include **invites**, alongside one-to-one chats, group chats, and calls. [Element Help: notifications](https://element.io/en/help)

#### Not established

- These first-party sources describe room membership and invitation, not a durable bilateral contact-request state. They do not establish a sender withdrawal UX, an acceptance notification, a post-join route transition, or a mobile contact-request mailbox.
- The distinction matters: importing room-invite behavior into a friendship model would create incorrect expectations about who gains access to what.

### WhatsApp — strong comparator for privacy posture, not for this state machine

#### Observed

- WhatsApp says its privacy settings let people choose what they share and “who can talk to you,” and offers **Silence unknown callers** to screen out spam/unknown contacts from ringing. [WhatsApp Privacy](https://www.whatsapp.com/privacy)

#### Evidence limitation

The examined WhatsApp first-party material does not document a pending contact/message-request acceptance workflow comparable to Signal, Discord, or Session. Treat it as privacy framing only; do not use it to infer sender status, accept/decline semantics, routing, or cancellation.

## Cross-product patterns

### Observed patterns

1. **Separate the untrusted inbound flow from normal conversations.** Discord moves non-friend DMs to a separate request folder (and potentially a deeper Spam folder); Session gives new-ID messages a separate area above normal conversations. [Discord](https://support.discord.com/hc/en-us/articles/7924992471191-Message-Requests), [Session](https://sessionapp.zendesk.com/hc/en-us/articles/9347841807897-How-do-I-find-my-message-requests)
2. **Let the receiver decide with meaningful context.** Signal shows profile information and locally detected mutual groups; Discord exposes profile/shared-server inspection. [Signal](https://support.signal.org/hc/en-us/articles/360007459591-Signal-Profiles-and-Message-Requests), [Discord](https://support.discord.com/hc/en-us/articles/7924992471191-Message-Requests)
3. **Acceptance changes durable permission or placement.** Signal acceptance permits messages/calls and adds a contact; Session acceptance moves the conversation to regular contacts; Matrix join changes membership. [Signal](https://support.signal.org/hc/en-us/articles/360007459591-Signal-Profiles-and-Message-Requests), [Session](https://sessionapp.zendesk.com/hc/en-us/articles/9347841807897-How-do-I-find-my-message-requests), [Matrix](https://spec.matrix.org/latest/client-server-api/#post_matrixclientv3roomsroomidjoin)
4. **Decline, ignore, delete, and block are not interchangeable.** Signal separates delete from a non-notifying, notification-suppressing block; Discord's ignored request is unrecoverable but may be resent; Session documents block as removal of the request. [Signal](https://support.signal.org/hc/en-us/articles/360007459591-Signal-Profiles-and-Message-Requests), [Discord](https://support.discord.com/hc/en-us/articles/7924992471191-Message-Requests), [Session](https://sessionapp.zendesk.com/hc/en-us/articles/9347841807897-How-do-I-find-my-message-requests)
5. **Mobile makes requests an explicit, conditional destination.** Discord surfaces a pending-only tab and badge; Session places requests above normal messages and supplies a settings/profile entry point. [Discord](https://support.discord.com/hc/en-us/articles/7924992471191-Message-Requests), [Session](https://sessionapp.zendesk.com/hc/en-us/articles/9347841807897-How-do-I-find-my-message-requests)

### Observed gaps worth respecting

- Across the accessible Signal, Discord, Session, and Matrix/Element material, sender-facing status and sender withdrawal are largely undocumented. That is evidence of a **documentation gap**, not evidence that those products conceal or lack the behavior.
- The sources establish durable outcomes far more often than they establish animation, toast, or route behavior. Do not convert a permission change into an unsupported claim of automatic chat opening.

## Anti-patterns to avoid

1. **Do not let a pending request look like a normal, usable chat.** The strongest comparable flows deliberately separate it until consent. [Discord](https://support.discord.com/hc/en-us/articles/7924992471191-Message-Requests), [Session](https://sessionapp.zendesk.com/hc/en-us/articles/9347841807897-How-do-I-find-my-message-requests)
2. **Do not make “Decline” secretly mean “Block.”** Receiver safety needs a clearly stronger escalation with documented consequences; Signal and Snapchat make that distinction explicit. [Signal](https://support.signal.org/hc/en-us/articles/360007459591-Signal-Profiles-and-Message-Requests), [Snapchat](https://help.snapchat.com/hc/en-us/articles/7012401093396-How-do-I-block-a-friend-on-Snapchat)
3. **Do not promise an outgoing accepted/declined status unless Fireplace defines the privacy contract.** Existing first-party evidence here is too thin to borrow that semantics casually.
4. **Do not couple acceptance to an automatic route change by assumption.** The sources establish enabled contact/chat or inbox placement, not a universal “accept and jump into chat” rule.
5. **Do not imitate Matrix room invitations as if they were friendship.** A room-membership grant and a bilateral messaging/contact relationship are different permissions. [Element](https://element.io/en/help#chat5), [Matrix](https://spec.matrix.org/latest/client-server-api/#post_matrixclientv3roomsroomidjoin)

## Recommendations for Fireplace (inference, not borrowed product facts)

1. **Expose two first-class pending views:** incoming requests needing a decision, and outgoing requests the sender can account for. Keep both out of the normal conversation list until the relationship state permits a conversation.
2. **Make the receiver's decision explicit and safe:** `Accept`, a quiet `Decline`, and a clearly stronger `Block` action. Show identity/context before consent; never require opening a writable chat to inspect it.
3. **Treat acceptance as a durable state transition, then make that transition visible in the destination list.** Do not rely on a toast as the only proof of success. Do not auto-open the conversation unless Fireplace deliberately chooses and specifies that navigation contract.
4. **Give outgoing pending requests an honest, reversible state.** If Fireplace implements withdrawal, remove it from the recipient's pending inbox and show the sender that it was withdrawn; do not fabricate an “accepted”/“declined” notification policy without deciding its privacy implications.
5. **Use mobile IA that is discoverable but not permanent chrome:** a badged, conditional requests entry near Contacts is appropriate; the requests screen should preserve the distinction between incoming and outgoing rather than making users hunt through normal chats.

## Source-quality note

The evidence is intentionally uneven. Signal, Discord, Session, Matrix, and Element provided directly readable first-party material. Meta's Instagram/Messenger Help pages and Snapchat's inbound-friend-request material did not yield operational text through the available reader, so they are reported as gaps rather than padded with common knowledge. WhatsApp is included only as a directly sourced privacy contrast, not as an invitation-flow precedent.
