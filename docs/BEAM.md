# Beam: sending pages to the hub

Beam puts a web page from an iPhone on the shared iPad. The same app runs on both devices. The
iPad is the hub and receives. The iPhone is the companion and sends.

A page can reach the hub in three ways. Each one ends in the same place: `BeamReceiver` checks the
address against the URL policy, decides whether to ask first, and only then gives the hub's browser
something to load.

## The three paths

| Path | Use it when | Needs | Hub behavior |
|---|---|---|---|
| Peer link | The iPhone is paired with the hub and both are on the same network. This is the main path and the one the share sheet uses. | Pairing, local network permission on both devices, HomePad on screen on the hub. | Asks or opens, depending on the rules below. |
| SharePlay | People want to browse the same page together, in a FaceTime call or a Messages SharePlay session the hub's Apple Account is part of. | The Group Activities capability, a session, SharePlay on in Settings. | Opens the session's page and follows navigation from every participant. |
| Handoff | The iPhone and the hub are signed in to the same Apple Account and the person picks up the activity on the hub. | Same Apple Account, Handoff on in both devices' system settings and in HomePad's settings, Bluetooth. | Opens the page. Picking it up is an action on the hub. |

There is a fourth entry point, the `homepad://beam?url=...` link. Any app or web page on the hub can
open it, so it always asks first.

### Peer link

The hub advertises a Bonjour service of type `_homepad._tcp`. The companion browses for it,
connects over TCP with TLS, and sends the page as a `BeamMessage` on the `beam` channel. The hub
answers with a receipt: opened, waiting for approval, declined, rate limited, or rejected with the
reason. The companion shows that answer.

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

**Asking first.** The hub asks before opening when the setting says Ask First, when nobody in front
of it is recognized, when it is the first page from that iPhone, or when the page came from a
`homepad://` link. Only an explicit Open on the hub counts toward an iPhone no longer being new.

**Cookies and sign-ins.** The browser uses a per-profile persistent store only while the active
profile's personal content is unlocked by a face match. In every other case, including guests and
manually picked profiles, it uses a store that is never written to disk. When the person in front
of the hub changes, the page is reloaded with the right store.

**Secrets at rest.** Pairings and the device's ID are Keychain items with
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly` in the app group, so the share extension reads the
same items. Nothing secret is written to `UserDefaults`, files, or logs. Logs never contain an
address, a title, or a message body.

**What is advertised.** The Bonjour record carries the hub's random ID, a format version, and the
hub name from Settings. The default name is "HomePad". The record is not trusted: it only tells a
companion which pairing to try.

## What people see

**On the hub.** A banner with the sender's name and the site when a page is waiting, with Open and
Not Now. The browser, with back, forward, reload, share, send to iPhone, and close. A list of recent
pages, kept in memory until the app quits. The Pairing screen in Setup Mode.

**On the iPhone.** A Beam screen to type or paste an address and send it, with the hub's answer. The
share sheet action Beam to HomePad in Safari and other apps. A banner when the hub sends a page back.
Scan Pairing Code and the list of paired hubs.

## Settings

Every preference is in the system Settings app under HomePad, in the Beam pane. The app has no
settings screens. `BeamSettings.descriptors` lists the rows.

| Key | Meaning | Default |
|---|---|---|
| `beam.receiveBeams` | Paired iPhones may send pages to this hub. | On. Nothing is received until an iPhone is paired. |
| `beam.approvalMode` | `askFirst` or `openImmediately`. | `askFirst` |
| `beam.hubName` | Name shown to paired iPhones and advertised on the network. | HomePad |
| `beam.companionName` | Name shown on the hub next to pages this iPhone sends. | iPhone |
| `beam.sharePlay` | Join and start browse-together sessions. | On |
| `beam.handoff` | Advertise on the iPhone, accept on the hub. | On |
| `beam.keepHistory` | Keep the recent pages list. | On |
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
