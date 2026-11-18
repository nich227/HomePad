# Messaging and projection

How HomePad shows a member's iPhone content on the hub, what iOS allows, and what it does not.

Code: `Packages/HomePadMessaging` (targets `HomePadMessagingCore` and `HomePadMessaging`) and
`Extensions/MessagesExtension`.

## How projection works

The HomePad app on an iPhone (companion) describes its screens with a fixed set of templates and
sends them to the HomePad app on an iPad (hub) over `PeerChannelName.projection`. The hub renders
the templates. It never runs companion code and does not know the apps. Everything is read and
processed on the iPhone, and it works only while the iPhone is connected.

| Piece | Type | Side |
|---|---|---|
| Template vocabulary | `ProjectionTemplate`: `list`, `grid`, `nowPlaying`, `conversationList`, `conversation`, `information`, `agenda` | both |
| Limits | `ProjectionLimits`, checked by `ProjectionValidator` | both |
| Wire format | `ProjectionCodec`, `ProjectionFrame`, `HostToHubMessage`, `HubToHostMessage` | both |
| State | `ProjectionHostState` (companion), `ProjectionClientState` (hub) | pure reducers |
| Who may see what | `ProjectionVisibilityPolicy` | hub |
| Text summaries of a member's content | `ProjectedContextSummarizer`, `ProjectedContextSummary` | hub |
| Services | `ProjectionHost` (companion), `ProjectionClient` (hub) | iOS |

Messages on the wire:

- Companion to hub: `announce(apps)`, `setRoot`, `push`, `pop`, `update` (replaces the template
  with the same id), `withdraw(appID)`, `present(appID)`.
- Hub to companion: `hello` (send me everything), `launch(appID)`, `action(appID, actionID,
  payload)`, `reply(conversationID, text)`, `mediaCommand`.

Every frame has a protocol version, the sender's session id, and a sequence number. A frame is
rejected whole when the version is not supported, the message type or a template case is unknown,
a field is missing, the content is outside the limits, the sequence number does not increase, or
the sender has the wrong role. The companion owns navigation. The hub's back button sends the
reserved action `homepad.back` and the companion answers with `pop`.

Limits (defaults): 12 apps per companion, navigation depth 5, 24 list rows in 8 sections, 8 grid
buttons, 20 conversations, 40 bubbles, 12 information items, 24 agenda entries, titles 80
characters, subtitles 160, message text 2000, artwork 96 KB, one frame 256 KB.

## What works

| Feature | How |
|---|---|
| Incoming messages on the hub | A Shortcuts automation on the iPhone runs `RelayMessageToHomePadIntent` for each new message. The companion keeps it in memory and projects it. |
| Replying from the hub | The reply goes to the iPhone, which shows the system message sheet prefilled. The owner taps Send there. If the iPad's own Messages account belongs to the same member, the sheet opens on the iPad instead. |
| Calendar | EventKit, today through the next 7 days, read only. |
| Reminders | EventKit, open reminders that are overdue or due in the next 7 days. Tapping one on the hub toggles it complete on the iPhone. |
| Now Playing | `MPMusicPlayerController.systemMusicPlayer`: title, artist, album, artwork, position, play, pause, next, previous, restart. |
| Sending HomePad content in a conversation | The iMessage app extension inserts an interactive message that carries a `MessageDeepLink`. |
| Opening received HomePad content | Tapping the message offers "Open on HomePad", which opens the app with a `homepad://message` link. |
| Household notes | Text notes over `PeerChannelName.intercom`: a banner on the hub, a local notification on companions. |
| Siri and Shortcuts | `BeamToHomePadIntent`, `ShowOnHomePadIntent`, `RelayMessageToHomePadIntent`. |

## What the platform does not allow

- **Reading Messages.** iOS has no public API to read the iMessage or SMS database, list
  conversations, or observe incoming messages. HomePad cannot mirror the Messages inbox. The hub
  shows only messages that the Shortcuts automation handed over while the HomePad app was running
  on the iPhone. There is no history, no attachments, no group names, and no read state from
  Messages.
- **Sending a message without the person.** `MFMessageComposeViewController` always shows the
  message and waits for a tap on Send. HomePad has no path around that and does not want one.
- **Creating the automation for the person.** Neither App Intents nor the Shortcuts URL scheme can
  create a personal automation. The person follows `ShortcutsSetupGuideView` once.
- **Other apps' CarPlay scenes.** A third-party app cannot render another app's CarPlay or
  projected UI. Projection covers content the HomePad app can read itself.
- **Other apps' playback.** `systemMusicPlayer` reflects the Music app only. There is no public
  API to read what another app is playing.
- **The sender's phone number, unless the automation passes it.** Without a phone number or email,
  the reply sheet opens with an empty recipient.
- **Guaranteed delivery.** iOS can stop the app in the background, can turn an automation off
  after an update, and gives an intent a short time to run. The intent waits up to 8 seconds for a
  hub and then reports that none is nearby.

## Shortcuts automation setup

Done once on each member's iPhone. `ShortcutsSetupGuideView` shows the same steps and has a button
that opens the Shortcuts app.

1. Open Shortcuts, tap Automation, then the plus button.
2. Choose Message.
3. Choose a Sender or type text under Message Contains. Shortcuts needs at least one. Add several
   senders, or repeat the steps, to relay more people.
4. Choose Run Immediately and turn off Notify When Run. Tap Next.
5. Tap New Blank Automation, then Add Action. Search for "Relay Message to HomePad".
6. Set Message to Shortcut Input. Set Sender to Shortcut Input, then tap it and pick Sender.
   Optional: expand the action and set Phone or Email the same way so replies are addressed.
7. Tap Done and test with a message from another device.

The intent returns true when the message reached a hub. When no hub is reachable it keeps the
message in the iPhone's memory and returns false with a dialog that says so.

## Privacy rules

1. **Message text is memory-only.** `RelayedMessage.body` is a `MemoryOnly<String>`. `MemoryOnly`
   has no `Codable` conformance and declares the conformance unavailable, so a type that stores one
   cannot be encoded or saved. `MessageInbox`, `ProjectionClientState`, and `PendingReply` all store
   it. Printing or dumping a `MemoryOnly` shows a placeholder.
2. **Nothing is persisted on the hub.** The hub holds projected templates in
   `ProjectionClientState` only. They are dropped when the companion disconnects or the app stops.
   On the iPhone, relayed messages are also memory-only and expire after the retention time in
   Settings.
3. **Personal apps are for their owner.** Messages, Calendar, and Reminders are marked
   `requiresPersonalContent`. The policy, per app and viewer:

   | Viewer in front of the hub | Result |
   |---|---|
   | The owner, recognized by face (`isPersonalContentUnlocked`) | visible |
   | The owner's profile picked by hand, not verified | redacted: the app is listed with a lock, no content |
   | Another member, a guest, or nobody | hidden: not listed at all |
   | Companion not linked to a member | hidden |

   Now Playing is not personal and is visible to everyone.
4. **Previews are the owner's choice.** With "Show Message Previews" off, the conversation list
   template is built without message text, so the text does not leave the iPhone until the owner
   opens the conversation on the hub.
5. **No logging.** The package has no logging calls. Rejected frames are dropped without recording
   their content. Do not add logs that include template content, message text, or URLs with query
   strings.
6. **Links are checked.** `MessageDeepLink` accepts three kinds: beam a page (`http` or `https`,
   with a host, no embedded credentials), open an app, open a face. Pairing kinds are refused. An
   unknown or repeated parameter, an unknown kind, or another version is an error.
7. **Conversation ids are digests.** The id of a conversation is a SHA-256 prefix of the sender's
   phone number, email, or name, so those do not appear in template ids or action ids.

## Context summaries

`ProjectionClient.contextSummaries(limit:maxTextLength:)` gives the active member's projected
content as short plain text, for a caller that does not render templates (the app hands it to the
Assistant as context items). The package does not know that caller.

```swift
public func contextSummaries(limit: Int = 8, maxTextLength: Int = 140) -> [ProjectedContextSummary]

public struct ProjectedContextSummary: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable, CaseIterable { case message, calendarEvent, reminder, nowPlaying }
    public let id: String
    public let kind: Kind
    public let ownerProfileID: UUID
    public let title: String
    public let detail: String
}
```

**Who gets any.** The decision is `ProjectionClientState.contextSummaries(viewer:...)`. It reads
only apps that `entries(viewer:)` lists as visible, and only from a companion for which
`ProjectionVisibilityPolicy.showsPersonalContent` is true: the owner is the active member and
`isPersonalContentUnlocked` is true. That is the decision the Messages app gets, made by the same
`decide` function, and it is applied to Now Playing too, because here the track says what one
member is doing. Everyone else gets an empty array:

| In front of the hub | Result |
|---|---|
| The member, recognized by face, iPhone connected and projecting | their summaries |
| The member's profile picked by hand | empty |
| Another member | empty for this iPhone; their own iPhone's summaries if it is connected |
| A guest or nobody | empty |
| The member, but no iPhone connected, or every app turned off in Settings on the iPhone | empty |
| A companion not linked to a member | empty |

An app turned off in Settings on the iPhone is withdrawn, so the hub holds nothing of it.

**What each kind is made from.** The kind comes from the template, not from the app id.

| Kind | Template | `title` | `detail` | Left out |
|---|---|---|---|---|
| `message` | each row of a `conversationList` | the correspondent | the preview (the conversation's latest message) | the text, when Show Message Previews is off: `detail` is empty |
| `calendarEvent` | `agenda` entry of kind `event` | event name | time, then location | events whose end has passed on the hub's clock |
| `reminder` | `agenda` entry of kind `reminder` | reminder name | due time, then list name | completed reminders |
| `nowPlaying` | `nowPlaying` with `isPlaying` | track | artist, then album | a paused or idle player |

`list`, `grid`, `information`, and `conversation` templates give nothing. An open conversation's
bubbles are not read, so the preview setting decides what message text can appear.

**Order and limits.** Messages are newest first. Events and reminders are soonest first, undated
ones last, so an overdue reminder comes before one due later. The kinds take turns (message,
event, reminder, now playing, message, and so on), so a small `limit` keeps one of each before
it takes a second of any. `maxTextLength` applies to `title` and to `detail` separately, counts
characters as a person reads them (an emoji sequence is one), and clipped text ends with an
ellipsis. Text is folded onto one line first. The same item on two screens or from two iPhones
of one member is listed once.

**Identity.** `id` is `<device id>/<app id>/<kind>/<item id>`: the conversation id, the agenda
entry id, or the player's template id. It does not change when the text changes, so a new
message in a conversation and a new track keep the id of the one before.

**Times** are written in the hub's locale and time zone. `ProjectedContextTimeStyle` fixes them
in tests.

**Handling.** The strings are personal content that has left `MemoryOnly`. The type cannot be
given a `Codable` conformance. Do not save or log them.

Limits of the data:

- The conversation list does not say who wrote the latest message. After the member replies
  from the hub, the preview is their own reply, and `title` is still the correspondent.
- Only messages the Shortcuts automation relayed exist. This is not the Messages inbox.
- A repeating event appears once. All its occurrences share one id and the agenda keeps one.
- The iPhone rebuilds its screens when its data changes and once a minute. When iOS suspends
  the app there, the hub keeps the last copy until the link drops. Ended events are dropped
  here on the hub's clock, and nothing else is corrected.
- All-day dates are midnight in the iPhone's time zone. A hub in another time zone can show the
  day before or after.
- Now Playing covers the Music app only, and the hub learns of a change when the iPhone sends it.
- Content from a disconnected iPhone stays until the next peer check, which runs every 2 seconds.

## Settings

All preferences are in the Settings app. The package reads them through `HomePadSettings` and never
writes one. Descriptors: `MessagingSettings.descriptors`. Where a feature is off, the views show
text and `OpenSettingsButton`.

The iMessage extension reads one key, `messaging.suggestRecentPages`, from the app group defaults.
The app mirrors it there.

## Adding a projected app

1. Write a `@MainActor` class that conforms to `ProjectedAppProvider`.
2. Give it a `ProjectedApp` with a unique id, an SF Symbol, a tint, and
   `requiresPersonalContent: true` if it shows anything that belongs to the iPhone's owner.
3. Return a template from `template(id:)` for `rootTemplateID` and for every screen you push.
   Build templates from the existing cases. Use `projectionTruncated(to:)` so content fits the
   limits. A template outside the limits is not sent.
4. Call the `onChange` closure from `activate(onChange:)` when your data changes. The host asks
   for fresh templates and sends only the ones that changed.
5. Handle taps in `handle(actionID:payload:)` and return `.push`, `.showDetail`, `.pop`, or `.none`.
6. Pass the provider in `ProjectionHost(channel:settings:providers:)`. Supplying `providers`
   replaces the built-in Calendar, Reminders, and Now Playing, so include those you still want.

The hub needs no change for a new app. A new template case does need a hub change, and a hub that
does not know the case rejects the frame.

## App target wiring

```swift
// Once, where the app's other App Intents packages are listed.
struct HomePadAppIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [HomePadMessagingIntents.self] }
}

// In App.init(), not in a view: Shortcuts launches the app in the background with no scene.
settings.register(GeneralSettings.descriptors + MessagingSettings.descriptors)
let host = ProjectionHost(channel: channel, settings: settings)       // companion
HomePadIntentHandlers.shared.register(host: host)
HomePadIntentHandlers.shared.beam = { url in /* beam the page, return a HubCommandOutcome */ }
host.start()
HomePadAppShortcuts.updateAppShortcutParameters()
```

`HomePadAppShortcuts` lives in the app target (`HomePad/HomePadAppShortcuts.swift`). Declared in the
package, its phrases did not reach the app's `Metadata.appintents/extract.actionsdata`: the app's
copy listed the three intents with an empty `autoShortcuts`.
