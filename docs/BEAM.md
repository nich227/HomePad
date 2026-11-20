# Beam: sending pages to the hub

Beam puts a web page from an iPhone on the shared iPad. The same app runs on both devices. The
iPad is the hub and receives. The iPhone is the companion and sends.

A page can reach the hub in three ways. Each one ends in the same place: `BeamReceiver` checks the
address against the URL policy, works out whose page it is, decides whether to ask first, and only
then opens it as a page in that person's browser session. The browser is described in
[The hub's browser](#the-hubs-browser).

## The three paths

| Path | Use it when | Needs | Hub behavior |
|---|---|---|---|
| Peer link | The iPhone is paired with the hub and both are on the same network. This is the main path and the one the share sheet uses. | Pairing, local network permission on both devices, HomePad on screen on the hub. | The page belongs to the member the iPhone was paired for. It asks or opens when that person is in front of the hub, and waits unseen until then. |
| SharePlay | People want to browse the same page together, in a FaceTime call or a Messages SharePlay session the hub's Apple Account is part of. | The Group Activities capability, a session, SharePlay on in Settings. | Opens the session's page for the person in front of the hub and follows navigation from every participant. |
| Handoff | The iPhone and the hub are signed in to the same Apple Account and the person picks up the activity on the hub. | Same Apple Account, Handoff on in both devices' system settings and in HomePad's settings, Bluetooth. | Opens the page for the person in front of the hub. Picking it up is an action on the hub. |

There is a fourth entry point, the `homepad://beam?url=...` link. Any app or web page on the hub can
open it, so it always asks first. It asks the person in front of the hub, and the page is theirs.

### Peer link

The hub advertises a Bonjour service of type `_homepad._tcp`. The companion browses for it,
connects over TCP with TLS, and sends the page as a `BeamMessage` on the `beam` channel. The hub
answers with a receipt: opened, waiting for approval, waiting for its owner, expired, declined, rate
limited, or rejected with the reason. The companion shows that answer, and a later receipt for the
same page replaces a "waiting" answer. "Waiting for its owner" reads on the iPhone as "It is waiting
for you at the hub and opens when the hub sees you."

The peer link is also the transport for other features. It implements `PeerChannel` from
HomePadCore, so anything that takes `any PeerChannel` can use it. Frames can carry up to 1 MiB.

### SharePlay

`BeamTogetherActivity` is a `GroupActivity` that holds one page address. `SharePlayCoordinator`
watches for sessions, joins them, and keeps everyone on the same page with `GroupSessionMessenger`.
Each navigation carries a sequence number. The highest wins, and a tie goes to the participant whose
ID sorts last, so every device settles on the same page with no device in charge. A person who joins
late is sent the current page. Nothing is screen shared: each device loads the page itself.

The hub applies the same URL policy to every address a session sends. An address that fails is
ignored.

On the hub a session has one page. It opens as a new page in the session of the person in front,
and later navigations from other participants load in that page and bring it to the front. The
navigation that is sent out is the one of the page in front, including a switch to another open
page, so while a session is active the address of whatever page is in front is shared with it. When
the person in front signs out, the hub leaves the session, so the next person is not shown what the
session browses. The hub never shows the system sheet for inviting people: on a hub the Browse
Together button appears only while a call is under way that can take the page.

### Handoff

While the companion's beam screen shows a valid address, it advertises an `NSUserActivity` of type
`com.kevster.HomePad.beam` with the address. The hub accepts that activity and the system web
browsing activity.

## Pairing

Pairing gives one iPhone and one hub a shared secret. It needs someone at the hub.

1. On the hub, with Setup Mode on, open Pairing and choose whose iPhone it is. The hub shows a QR
   code. The code is valid for two minutes and for one iPhone.
2. On the iPhone, open HomePad and choose Scan Pairing Code, or point the Camera app at the code.
3. The iPhone finds the hub on the network, connects with the secret from the code, and both sides
   store the pairing in the Keychain.

The QR code text is `homepad://pair?c=` followed by base64url data: a version byte, the hub's random
ID, the expiry time, the 32 byte secret, and the hub's name. The secret is the only sensitive part.
The hub decides which household member the iPhone belongs to. The iPhone cannot claim one.

To remove an iPhone, use Remove in the hub's Pairing screen. That iPhone can no longer connect. The
others are not affected.

## Security model

**What can reach the hub.** The hub opens a listening socket only while all of these hold: HomePad
is the active scene, and either Receive Beams is on and at least one iPhone is paired, or a pairing
code is on screen. In every other state there is no socket. The socket accepts connections from the
local link only.

**Who can connect.** The listener uses TLS 1.2 with pre-shared keys (Network.framework's
`sec_protocol_options_add_pre_shared_key`). It prefers `TLS_ECDHE_PSK_WITH_CHACHA20_POLY1305_SHA256`,
which gives forward secrecy, and also offers `TLS_PSK_WITH_AES_256_GCM_SHA384`. A device that does
not hold an installed key cannot finish the handshake, and nothing it sends reaches the app. TLS 1.3
is not used because the system's TLS 1.3 does not accept an external pre-shared key.

**One key per iPhone.** Each pairing has its own 32 byte random secret. The TLS key, the TLS key
identity, and a hello key are derived from it with HKDF-SHA256, salted with the hub's ID. The
listener holds one key per paired iPhone, so removing an iPhone removes only its key.

**The hello.** TLS proves the peer holds some installed key, but the system does not say which one.
So the first frame on every connection is a hello with the device's ID and an HMAC over that ID made
with the hello key from the same pairing. The hub checks the HMAC against the record stored for the
claimed ID. So a paired iPhone cannot pose as a different paired iPhone. Until the hello is
accepted, frames are limited to 4 KiB, nothing is delivered to subscribers, and the connection is
closed after 10 seconds. The hub stamps every message with the authenticated sender; a sender field
inside a message is ignored.

**What a beam can do.** An address must be `http` or `https`, at most 2,048 bytes, with a host and
with no user name or password. `javascript:`, `file:`, `data:`, and custom schemes are rejected.
Addresses on the hub itself or the local network are rejected unless Allow Local Network Addresses is
on. The same check applies to every main frame navigation inside the browser, so a public page
cannot redirect the hub to an address a beam could not have named. The app never injects or runs
script in a page. Each paired iPhone can send six beams in 30 seconds; more are refused.

**Whose page it is.** A page from a paired iPhone belongs to the household member the iPhone was
paired for. A page from an iPhone paired for nobody, from a member who has since been removed, or
from Handoff, SharePlay, a `homepad://` link, or the recents list belongs to the person in front of
the hub at that moment, or to the guest when nobody is recognized. Only the owner is ever shown the
page, its title, its address, or the question about it.

**Asking first.** The question is put to the owner, and only while the owner is in front of the hub.
The hub asks before opening when the setting says Ask First, when it is the first page from that
iPhone, when the page came from a `homepad://` link, or when the page belongs to a guest and came
from an iPhone. Only an explicit Open on the hub counts toward an iPhone no longer being new.

**Cookies and sign-ins.** A page gets its store when it opens and keeps it until it closes. It
gets the member's persistent store only if the member's personal content is unlocked by a face
match at that moment. In every other case, including guests, manually picked profiles, and a
member the camera has lost sight of, it gets a store that is never written to disk. A page that a
link opens in a new window shares the store of the page the link was on. Nothing reloads an open
page when the lock state changes, so a page a member signed in to stays as it is, signed in and
visible, while they step away for the grace period. Sign-ins in the persistent store survive a
sign out. Open pages do not.

**Secrets at rest.** Pairings and the device's ID are Keychain items with
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly` in the app group, so the share extension reads the
same items. Nothing secret is written to `UserDefaults`, files, or logs. Logs never contain an
address, a title, or a message body.

**What is advertised.** The Bonjour record carries the hub's random ID, a format version, and the
hub name from Settings. The default name is "HomePad". The record is not trusted: it only tells a
companion which pairing to try.

## What people see

**On the hub.** A banner with the sender's name and the site when a page is waiting for the person
in front, with Open and Not Now. The browser, described below. The Pairing screen in Setup Mode.

**On the iPhone.** A Beam screen to type or paste an address and send it, with the hub's answer. The
share sheet action Beam to HomePad in Safari and other apps. A banner when the hub sends a page back.
Scan Pairing Code and the list of paired hubs.

## The hub's browser

The hub's browser is a session per person. `BrowserSessions` and `BeamIntake` in `HomePadBeamCore`
hold the rules. `BeamReceiver` applies them to the household session and owns the web pages.
`BeamBrowserView` draws the whole browser for the person in front.

### Owners and sessions

An owner is a household member or the guest. Each owner has a session: the open pages, the one in
front, and that owner's recent pages. Pages open only in the session of the person in front of the
hub. Everything `BeamReceiver` publishes about pages (`pages`, `frontPage`, `current`, `pending`,
`recents`) is read for the person `HouseholdSession.activeProfile` names at that moment and is
empty for anyone else. There is one guest session, shared by whoever is unrecognized until they
leave.

### Pages

| Rule | Value |
|---|---|
| Open pages per session | 6 (`BrowserSessions.defaultPageLimit`). Every open page is a live web view, so the cap bounds memory and keeps the switcher readable. |
| When a seventh opens | The oldest page that is not in front closes. |
| A beam that is already open | Comes to the front. No second page. |
| A link that asks for a new window | Opens as another page of the same session, in front, within the cap. The page that opened it gets no handle to it. |
| A recipe (`kind == .recipe`) | Is never a browser page. It is handed off through `current` for the app to route to the recipe reader. `closeBrowser()` ends the hand-off. |
| Recent pages per owner | 50, newest first, in memory only. Off when Keep Recent Pages is off. |

The person can bring a page to the front, close one, and close all. `closeBrowser()` takes the
browser off the screen (`current` becomes `nil`) and leaves the pages open.

### A page whose owner is somewhere else

A beam from member A's iPhone while member B or a guest is in front of the hub does not open, and
nothing about it is shown. It is held for A, and A's iPhone is told "waiting for you at the hub".
When A is next in front of the hub the held beams are decided, oldest first: each opens, or the
banner asks, as the approval rules say at that moment. A question A did not answer before leaving
is hidden again and comes back with A.

| Rule | Value |
|---|---|
| How long a beam is held | 30 minutes from arrival (`BeamIntake.defaultWaitingLifetime`), whether or not it has been offered. Then it is dropped and the sender is told it expired. |
| How many are held per owner | 6 (`BeamIntake.defaultWaitingLimit`), the same as the page cap, so everything held can open at once. A seventh drops the oldest and its sender is told. |
| The same page from the same iPhone again | Not held twice. The sender is told where the first one stands. |
| Held beams | In memory only. They are gone when the app quits. |

### Sign out

`HouseholdSession` decides when someone signs out, once, for every package, and says so by
changing `audienceGeneration`. The browser closes pages when that value changes and at no other
time. The rules are in the description of `HouseholdSession`. In short:

| What happens at the hub | Pages |
|---|---|
| The camera loses sight of the person, or sees a face it cannot judge, such as a head turned away | Stay open and on screen for the Stay Signed In After Stepping Away time (2 minutes by default). Personal content elsewhere on the hub locks at once. |
| The same person comes back within that time | Nothing changes. |
| That time passes | Close. |
| The hub is locked, someone switches profiles by hand, or another member is recognized | Close at once. |
| The camera judges a face and it is not the member's | Close at once. |
| Stay Signed In After Stepping Away is Off | Close as soon as the camera loses sight of the person. |

When pages close, every page of that person closes. Each web view is told to stop loading, close
any media presentation, pause all media, and load an empty document. Then it is taken off screen
and released. Nothing of the session stays on screen. A member's recent pages and held beams stay
for their return, and their persistent cookie store keeps its sign-ins. A guest's whole session
is forgotten: pages, recents, and questions, and its store was never on disk. The hub leaves a
SharePlay session it was in.

While a member lingers they are still the active profile, so the browser keeps showing their
pages, a beam from their iPhone still opens, and a page that opens then gets the store that is
never written to disk. A guest and a member picked by hand linger in the same way. For them any
face coming back continues the session, because the hub cannot tell them from anyone else it does
not recognize.

`BeamReceiver` follows the household session with Observation, so the close happens on the next
main actor turn after the session changes. Until then the views already show nothing of a person
who is no longer the active profile, because they read for the active person.

While the camera is not running, for example with face recognition off, the household session
never sees anyone leave. A guest's or a hand-picked member's pages then stay until someone closes
them, locks the hub, or the active person changes.

### Locked to the app

The browser has no address field. Pages arrive by beam and a person moves on by following links.
Each page is a `WKWebView` with a navigation delegate and a UI delegate that answer every
question the web view asks. The decisions about navigations are in `BeamNavigationPolicy`.

| Way out | How it is closed |
|---|---|
| Other URL schemes (`tel:`, `mailto:`, App Store, custom schemes) | A main frame navigation must pass the URL policy, which allows only `http` and `https`. Frames may load only `http`, `https`, `about`, `blob`, and `data`. |
| Universal links | The system offers an address a person tapped to the app that claims it. It does not do that for a load the app starts. So a link or script navigation to another site is cancelled and loaded again by the app itself. Form posts, back, forward, and reload are left as they are. |
| New windows and pop-ups | The delegate never creates a window. What asked for one becomes a page of the same session, or nothing. |
| Downloads | A navigation marked as a download is cancelled. A response the web view cannot show, or one marked as an attachment, is cancelled. The delegate never answers "download", and cancels a download if one starts anyway. |
| File pickers, photo library, camera for uploads | The open panel delegate method answers with no file, so no picker is shown. |
| Camera and microphone | The media capture delegate method answers "deny", so there is no prompt. |
| Motion sensors | The device orientation and motion delegate method answers "deny". |
| Location | The geolocation delegate method answers "deny". |
| JavaScript dialogs | None are shown. An alert returns at once. A confirm is answered "no" and a prompt gets no text. |
| The long-press menu on links and images (open, share, save, copy) | The context menu delegate method answers with no configuration, and link previews are off. |
| The menu on selected text (Copy, Paste, Look Up, Translate, Share, Search Web) | The web view refuses every menu and keyboard shortcut action and removes the standard menus. Typing and selecting still work, so forms can be filled in. |
| Share sheet | The Share button is gone. "Send to my iPhone" stays and goes over the peer link. |
| Print | No print action exists in the browser. |
| Picture in Picture | Off (`allowsPictureInPictureMediaPlayback`). |
| AirPlay of page media | Off (`allowsAirPlayForMediaPlayback`). |
| The system's full screen video player | Video plays inline (`allowsInlineMediaPlayback`). |
| Data detectors (phone numbers, addresses, dates that open other apps) | Off. |
| Writing Tools and inline predictions | Off. |
| Dragging a link, image, or selection to another app | The web view turns off the drag interactions it finds in its own view hierarchy each time it comes on screen. |
| AR Quick Look files (`.usdz`, `.reality`) | Navigations to them are cancelled, because the system viewer has a share button. |
| SharePlay invitation sheet | Not shown on a hub. |

Not closed:

- **Apple Pay and password AutoFill from the keyboard.** Both are system interface that needs the
  iPad's own authentication. WebKit has no switch for either.
- **A form that submits to another site with GET.** Form submissions are not loaded again by the
  app, so the system could offer that address to an app that claims it.

Closed on paper and not yet seen working on a device, because they depend on how the web view
behaves inside:

- That refusing every action leaves no item in the text menu. If one remains, turning text
  interaction off (`WKPreferences.isTextInteractionEnabled`) removes the menu with certainty and
  may stop typing in form fields.
- That the drag interactions are found and stay off.
- That a navigation the app loads again is not offered to another app.

The companion's browse-together page uses the same web view, so it is locked in the same way.

## Settings

Every preference is in the system Settings app under HomePad, in the Beam pane. The app has no
settings screens. `BeamSettings.descriptors` lists the rows.

| Key | Meaning | Default |
|---|---|---|
| `beam.receiveBeams` | Paired iPhones may send pages to this hub. | On. Nothing is received until an iPhone is paired. |
| `beam.approvalMode` | `askFirst` or `openImmediately`, applied when the page's owner is in front of the hub. | `askFirst` |
| `beam.hubName` | Name shown to paired iPhones and advertised on the network. | HomePad |
| `beam.companionName` | Name shown on the hub next to pages this iPhone sends. | iPhone |
| `beam.sharePlay` | Join and start browse-together sessions. | On |
| `beam.handoff` | Advertise on the iPhone, accept on the hub. | On |
| `beam.keepHistory` | Keep each person's recent pages list. | On |
| `beam.allowLocalAddresses` | Let the hub open pages hosted on the local network. | Off |

## Platform limits

- **Local network permission.** iOS asks each device once for permission to use the local network.
  If the person declines, the hub cannot be found and the peer link does not work. The app shows
  this and offers a button to Settings. The share extension is expected to share the app's
  permission; that has not been checked on a device.
- **The hub must be on screen.** iOS suspends an app shortly after it leaves the foreground, and the
  listener is closed when the scene is inactive by design. A beam sent while HomePad is not on screen
  fails with "the hub could not be reached".
- **Share extension lifetime.** A share extension lives only while its sheet is open and has a small
  memory budget. It makes at most three connection tries, then waits six seconds for the hub's
  answer. It cannot wait for someone at the hub to approve.
- **Handoff.** Both devices must be signed in to the same Apple Account, with Handoff and Bluetooth
  on. The hub shows the activity as a system Handoff icon; the person has to tap it. A page being
  read in Safari on the iPhone is offered to the hub's Safari, not to HomePad, because the system web
  browsing activity goes to the default browser unless the receiving app has an associated domain for
  that site.
- **SharePlay.** The app needs the Group Activities capability. A session exists only inside a
  FaceTime call or a Messages SharePlay conversation. Apple's documentation describes starting
  SharePlay by bringing devices together for iPhones; it does not list iPad, so do not count on that
  gesture with the hub.
- **No "hold near" trigger.** A third-party app cannot be launched or notified because an iPhone is
  held near an iPad. The closest public options do not fit: NFC background tag reading opens only
  universal links, not custom URL schemes, so an NFC tag on the hub's stand would need a website and
  an associated domain; Nearby Interaction needs the app running on both devices first. Beam uses
  the share sheet and the Beam screen instead.
- **TLS 1.2.** The peer link is pinned to TLS 1.2 because that is where the system supports
  pre-shared keys.

## Verified on a Mac, not on devices

The link code was run end to end on macOS: discovery, the TLS handshake, pairing, messages in both
directions, refusal of a device with the wrong secret, revocation, and the listener closing in each
state where it should. The iOS build compiles. None of this has run on an iPad or iPhone yet, and
SharePlay, Handoff, the camera scanner, and the web view have only been compiled.

The browser session rules (owners, the page cap, held beams, sign out, the store a page gets, the
navigation policy) are unit tested on the iOS simulator. The web view has only been compiled, and
each delegate method was checked against the iOS 27.2 headers and found in the built binary.
What it does has not been seen running: that a long press shows nothing, that the text menu is
empty, that a shut down page is silent, and that a reloaded navigation is not offered to another
app.
