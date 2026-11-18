# Face recognition

HomePad recognizes household members with the hub's front camera so it can show each person their
own layout and content. It works for any number of enrolled people. It does not use Face ID or
`LocalAuthentication`, because Face ID knows one person per device and a shared screen needs
several.

The code is in `Packages/HomePadFace`:

| Target | Holds | Tested |
|---|---|---|
| `HomePadFaceCore` | Every decision: matching, enrollment, stabilizing, liveness, proximity, alignment math, settings keys | Unit tests on the iOS simulator, 100% line coverage |
| `HomePadFace` | Camera, Vision, Core ML, Keychain, SwiftUI views | Compiled for a device. Not run on one yet |

Read "Security model" before you rely on this for anything. In short: it is convenience
personalization, not authentication.

## How it works

### One frame

1. `FaceCameraPipeline` runs an `AVCaptureSession` on the front camera. It prefers the TrueDepth
   camera and attaches an `AVCaptureDepthDataOutput` through an `AVCaptureDataOutputSynchronizer`.
   Without TrueDepth it uses the wide front camera and no depth.
2. `FaceAnalyzer` runs `VNDetectFaceRectanglesRequest`, picks the primary face (the largest one
   that is reasonably centered), then runs `VNDetectFaceLandmarksRequest` and
   `VNDetectFaceCaptureQualityRequest` on that face only.
3. The analyzer derives five points from the landmarks (two eyes, nose tip, two mouth corners),
   fits a similarity transform to the standard 112 x 112 template, and renders the aligned crop with
   Core Image.
4. A `FaceEmbedder` turns the crop into a vector. `FaceEmbedding` scales it to unit length.
5. The analyzer samples the depth map inside the face box and reduces it to `FaceDepthStatistics`.
6. The frame leaves the capture queue as a `FaceFrameObservation`: pose, capture quality, face
   size, the embedding, depth statistics, eye openness. It holds no pixels.

Frames and crops exist only while one frame is analyzed. Nothing writes them to disk, and the
package logs nothing.

### Recognition

`RecognitionEngine` handles each observation on the main actor:

- `FaceMatcher` compares the embedding with every stored template. A match needs a similarity at
  or above the model's threshold and a margin over the second-best person.
- `RecognitionStabilizer` wants 3 matching frames in the last 5 before it recognizes someone. It
  drops them after 3 consecutive misses, or when the lock delay passes without a match. If two
  profiles keep alternating, it locks and stays locked until one of them wins cleanly.
- `LivenessTracker` decides whether the matched face is a real face. See "Liveness".
- `ProximityEstimator` turns the face size into near or far, with hysteresis.

The result is one of four outcomes, and `HouseholdSessionDriver` applies it to `HouseholdSession`:

| Outcome | Meaning | Session call |
|---|---|---|
| `unlocked(id)` | Enrolled face, liveness established | `faceRecognized(profileID:proximity:at:)` |
| `personalized(id)` | Enrolled face, liveness not established | `faceMatchedWithoutLiveness(profileID:proximity:)` |
| `unknownPerson` | A face that is not enrolled, cannot be told apart, or looks like a spoof | `unknownFacePresent(proximity:)` |
| `nobody` | No face for the lock delay | `presenceLost()` |

`personalized` changes the layout and keeps personal content locked. The session records it as a
camera match, which is what Touch ID can later confirm (see "Touch ID as the second step"). When
that person leaves, the session ends the camera match. A profile that someone picked by hand
stays.

### Enrollment

`FaceEnrollmentView` first shows what will happen and asks for consent. The camera starts only
after the person agrees. Then `EnrollmentSession` collects two samples for each of five head
poses: straight, left, right, up, and down. It rejects a sample when:

- the capture quality is too low,
- the head is between poses or turned too far,
- the depth check says the surface is flat,
- the face does not look like the earlier samples of this session,
- the face matches another household member's template (three in a row block the enrollment).

The finished `FaceTemplate` holds the embeddings, the pose of each, the model ID, and a creation
date. Enrolling again replaces the old template.

### Liveness

The face model has no liveness check. A photo of an enrolled face produces a matching embedding.
`LivenessEvaluator` is what stands between a photo and personal content.

With depth (TrueDepth camera, face within about 0.2 to 1.2 m):

- A printed photo or a screen is a plane, even when it is tilted. The evaluator fits a plane to the
  depth readings of the face and measures what is left over.
- A real face has relief: the nose is closer to the camera than the cheeks.
- Two flat frames mark the face as a suspected spoof, and it is treated as an unknown person. Two
  frames with relief mark it as live.
- Depth is taken unfiltered on purpose. A screen often leaves holes in the depth map, and the holes
  are evidence. Too many of them give "indeterminate", not "live".

Without depth (no TrueDepth camera, or the person is too far away) the result is indeterminate. A
blink or a smooth head turn seen across frames is recorded as a passed challenge. A replayed video
passes that challenge, so by default it does not unlock anything.

Liveness evidence belongs to one matched person. It is collected only on frames that match that
person and is dropped when the matched person changes or everyone leaves. A real person standing
next to a photo of someone else does not vouch for the photo.

### Touch ID as the second step

An iPad without a TrueDepth camera can match a face but cannot prove the face is live, so the
match only personalizes. On such an iPad, Touch ID can finish the job in two steps:

1. The camera picks who. A match without proven liveness becomes a camera match in the session.
2. Touch ID confirms that someone enrolled on this iPad is present. That unlocks the
   camera-matched member's personal content until they leave.

**The limit.** Touch ID reports only that some enrolled finger matched. It cannot tell household
members apart. So after the camera recognizes a member, any fingerprint enrolled on this iPad
unlocks that member's personal content. It confirms that someone who can unlock this iPad is
present, not which person. A photo of a member plus any enrolled finger is enough. Enroll only
fingers of people who may see every member's personal content, or turn the setting off.

`DeviceBiometricUnlockPolicy` offers the unlock only when all of these hold:

| Condition | Why |
|---|---|
| "Unlock with Touch ID" is on | The household chose it |
| The device's biometry is Touch ID | An iPad with Face ID hardware has a depth camera, and the liveness check decides there. With no biometrics there is nothing to ask |
| No depth camera is in use | Same reason |
| A camera match is waiting | A fingerprint cannot pick the member. It is never offered for a profile picked by hand |

It also needs "Personalize Without Depth Check" to be on. With that setting off, a face without
proven liveness is a guest, so no camera match exists to confirm.

`DeviceBiometricUnlock.unlock()` runs one attempt:

- It prompts with the biometrics-only policy and hides the passcode fallback. The iPad passcode
  does not unlock a member's content here.
- It uses a new `LAContext` each time, so an earlier success is never reused.
- After the prompt returns, it checks that the same camera match is still waiting. If the person
  left, someone else was matched, or someone switched by hand while the prompt was up, an
  accepted finger unlocks nothing.

| Outcome | What happens |
|---|---|
| `confirmed` | The member's personal content unlocks until they leave |
| `failed` | Nothing changes. The button shows "Fingerprint not recognized" and can be tried again |
| `canceled` | Nothing changes and nothing is shown |
| `lockedOut` | Nothing changes. Touch ID is off until the iPad is unlocked with its passcode, and the unlock is not offered until then |
| `notAvailable` | Nothing changes. No prompt was shown, or the camera match was gone when it returned |

How long a confirmation lasts:

- It ends when the member leaves, when a stranger takes their place, and when another member is
  matched. It never carries over to another member.
- A single frame that matches a different enrolled member ends it too, even though the stabilizer
  keeps showing the first member. The fingerprint vouched for whoever stood there before.
- A single frame with no face, an unusable face, or no match does not end it. The stabilizer
  absorbs those frames and the session is not told.

After a confirmation `service.lastDecision` still reads `.personalized`, because the camera alone
has not proven anything. Read `session.isPersonalContentUnlocked` to decide what to show.
`RecognitionIndicatorView` shows a Touch ID glyph next to the member's name while the unlock is
offered, when it is given the `DeviceBiometricUnlock` object.

The simulator cannot exercise this. It has no camera, so no camera match ever exists and the
unlock is never offered.

### Power

The hub runs for hours, so the camera slows down when nobody is there:

| Mode | When | Capture | Analysis |
|---|---|---|---|
| Idle | No face for 10 s | 5 fps | 2 fps |
| Active | A face is in view | 15 fps | 8 fps |
| Preview | The mirror or an enrollment is on screen | 30 fps | 8 fps |

The camera stops when the app goes to the background and starts again when it comes back. It also
stops when recognition is turned off in Settings, unless the mirror is on screen.

### The mirror

An iPad runs one capture session on the front camera at a time, so the Mirror app shows this
package's camera instead of opening its own. `FaceMirrorView(service:)`, or
`service.makeMirrorPreview()`, is the mirrored, aspect-fill preview. The app calls
`service.setMirrorActive(true)` when the mirror opens and `setMirrorActive(false)` when it closes.

`CameraDemand.plan` decides what the camera does:

| Mirror | Recognition (started and turned on in Settings) | Camera | Frames analyzed |
|---|---|---|---|
| Off | Off | Stopped | No |
| Off | On | Running | Yes |
| On | Off | Running at the preview rate | No |
| On | On | Running at the preview rate | Yes |

In the background the camera is stopped in every case. With the mirror on and recognition off,
frames go to the preview layer and nowhere else: Vision and the face model do not run, and nobody
is recognized.

To show the mirror's state, read `cameraState`:

| State to show | Value |
|---|---|
| Running | `.running` |
| Camera permission denied | `.failed(.notAuthorized)` |
| No camera | `.failed(.noFrontCamera)` |
| Not available for another reason | `.interrupted(_)`, `.failed(.cannotAddInput)`, `.failed(.cannotAddOutput)` |
| Starting or closed | `.stopped` |

`cameraAuthorization` tells `.denied` (the person can change it in Settings) from `.restricted`
(they cannot).

### Where the viewer is

`service.facePosition` is the center of the primary face as the person would see themselves in a
mirror filling the screen: `x` and `y` in 0...1 with the origin at the top-left. A person who
moves to their own left moves `x` toward 0. It is `nil` when no face is in view or frames are not
analyzed.

The position is taken from the camera image after the image is turned upright relative to
gravity, and then flipped horizontally. That matches the screen whenever the interface follows the
way the device is held, which is the case for a hub on a stand. If the interface is locked to a
different orientation than the device is held in, or the iPad lies flat, the position follows
gravity and not the interface.

`FacePositionSmoother` applies a low-pass filter, reports a new position only after the face moved
at least 1% of the frame, and keeps the last position through a dropout of one or two frames.

## Security model

State this to users the way it is stated here.

- **This is not Face ID.** Matching runs in the app's process, not in the Secure Enclave. A
  compromised app process can read templates and results.
- **The camera-only path can be spoofed.** Without depth, a photo or a video of an enrolled person
  can produce a match. That is why a match without established liveness only personalizes and
  never unlocks personal content. The setting "Personalize Without Depth Check" turns even that
  off.
- **Touch ID does not identify the member.** On an iPad without Face ID hardware, a camera match
  plus any fingerprint enrolled on the iPad unlocks that member's personal content. A photo of the
  member and an enrolled finger are enough. See "Touch ID as the second step".
- **The depth check covers flat spoofs only.** It separates flat surfaces from surfaces with
  face-like relief. It does not detect a mask, a sculpted face, or a curved print. It was written
  from first principles and has not been tested against real spoof attempts on a device.
- **Thresholds are not calibrated for this household.** The match threshold comes from the model's
  publisher, and the liveness, quality, and proximity thresholds are estimates. All of them need
  checking on the target iPad. See "Calibration".
- **Twins and close relatives can match each other.** The margin rule turns some of those cases
  into "unknown person", not all of them.
- **A wrong match shows one person's content to another.** For content that matters, turn on
  "Personal Content Needs Paired iPhone Nearby" in the General settings, which adds a second
  factor.
- **Templates are sensitive.** An embedding cannot be turned back into a photo by ordinary means,
  but it identifies a person and should be treated as biometric data.

What the design does to limit harm:

- Templates are Keychain items with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, not
  synchronizable. They are not in iCloud Keychain and are not restored to another device.
- A failed or uncertain result always falls toward the guest experience.
- Templates made by one model are never compared with embeddings from another. The model ID is
  part of every embedding and every template.

## The bundled model

The app bundles `HomePad/Models/FaceEmbedder.mlpackage`: SFace from the OpenCV Model Zoo, converted
to Core ML. `docs/FACE_MODEL.md` describes the model and how it was converted and verified.
`HomePad/Models/NOTICE.md` holds the license notice.

- License: Apache-2.0, as stated in the model's directory in the OpenCV Model Zoo. `NOTICE.md`
  also records what was not verified about the model's origin.
- Contract: one 112 x 112 image in, 128 floats named `embedding` out. The normalization is inside
  the model. The output is not unit length, so `FaceEmbedding` normalizes it.
- `CoreMLFaceEmbedder` recognizes this contract from the loaded model's input and output shapes and
  selects the SFace profile. The model ID becomes `sface.FaceEmbedder.128` and the match policy
  becomes `MatchPolicy.sFace`.
- `MatchPolicy.sFace` uses the publisher's cosine threshold of 0.363 for "same person", plus a
  margin of 0.05 over the second-best person. The margin is this app's addition.

**The threshold was not calibrated here and accuracy was not measured here.** The publisher
measured 0.363 with its own face detector and alignment. This app aligns with Vision landmarks, so
treat 0.363 as a starting point. The "Match Strictness" setting moves it without a rebuild.

### Alignment is an approximation

The model expects five landmarks at fixed positions in the crop:

| Point | x | y |
|---|---|---|
| Eye on the left of the image | 38.2946 | 51.6963 |
| Eye on the right of the image | 73.5318 | 51.5014 |
| Nose tip | 56.0252 | 71.7366 |
| Mouth corner on the left of the image | 41.5493 | 92.3655 |
| Mouth corner on the right of the image | 70.7299 | 92.2041 |

Vision does not report these five points, so `FacePoints.derived` builds them:

- Eye centers are the centroids of the eye outlines. The pupil is the fallback.
- The nose tip is the nose-crest point farthest from the midpoint between the eyes.
- The mouth corners are the outer-lip points farthest apart along the line through the eyes.

Points are assigned by position in the upright image, not by Vision's landmark names. The eye with
the smaller x goes to the first slot. That keeps the crop upright and unflipped for any interface
orientation and for mirrored images. Core tests cover mirrored and rolled input.

All five points are used when Vision returns them. The two eyes alone are the fallback. These
points differ a little from the ones the publisher's detector returns, which shifts the crop
slightly and is one reason the threshold needs checking.

### When no model is bundled

`FaceEmbedderFactory` falls back to `FeaturePrintFaceEmbedder`, which uses
`VNGenerateImageFeaturePrintRequest` on the crop. A generic image feature print is trained to tell
images apart, not people. It is there so the app runs end to end during development. It has its
own model ID and a stricter policy, and `PeopleSetupView` shows a warning while it is active. Do
not ship with it.

## Using another model

`CoreMLFaceEmbedder` works with any Core ML model that takes one image, or one image-shaped tensor,
and returns one float vector. Examples are MobileFaceNet or ArcFace (112 x 112 in, 512 out) and
FaceNet (160 x 160 in, 512 out).

1. Check the license. Many public ArcFace weights are for non-commercial research only.
2. Convert the model with `Scripts/convert-face-model.py`. The script bakes the normalization into
   an image input, so the app passes a plain pixel buffer. It has not been run. Read its header
   first.
3. Name the result `FaceEmbedder.mlpackage` and put it in the app target. Xcode compiles it to
   `FaceEmbedder.mlmodelc`.
4. Set the model's code generation language to None in Xcode. Otherwise Xcode generates a class
   named `FaceEmbedder`, which hides the `FaceEmbedder` protocol in app code.
5. Calibrate. A model that is not SFace gets `MatchPolicy.conservativeDefault`, which is strict
   and untested for that model. Pass your own policy:

```swift
let embedder = await FaceEmbedderFactory.loadDefault(
    configuration: .init(matchPolicy: MatchPolicy(
        minimumSimilarity: 0.5,
        minimumMargin: 0.08,
        duplicateSimilarity: 0.5,
        enrollmentConsistencySimilarity: 0.3
    ))
)
```

For a model with a tensor input, set `profile` with the right `EmbedderPreprocessing` (`.signedUnit`,
`.unitRange`, `.raw`, `.imageNet`, or your own scale, mean, and deviation).

A new model means a new model ID. Existing templates then match nothing, and everyone enrolls
again.

## Settings

All preferences are in the system Settings app under HomePad, in the "Face Recognition" pane. The
app reads them and never writes them. `FaceSettings.descriptors` lists them for the Settings
bundle.

| Key | Title | Control | Default | Options |
|---|---|---|---|---|
| `face.recognitionEnabled` | Recognize Faces | Toggle | On | |
| `face.indeterminateLivenessPersonalizes` | Personalize Without Depth Check | Toggle | On | |
| `face.touchIDUnlock` | Unlock with Touch ID | Toggle | On | |
| `face.matchStrictness` | Match Strictness | Choice | `standard` | `relaxed`, `standard`, `strict` |
| `face.lockDelaySeconds` | Lock After Face Is Lost | Choice | `3` | `1`, `3`, `5`, `10`, `30` |
| `face.nearDistance` | Show More Detail When | Choice | `standard` | `closer`, `standard`, `farther` |

Adding people and enrolling faces are setup tasks, not preferences. They are in `PeopleSetupView`,
which the app shows while Setup Mode is on.

## Privacy and App Store

This section describes what the code does. It is not legal advice.

**Camera usage string.** The app's `Info.plist` needs `NSCameraUsageDescription`. Say what the
camera is for, for example: "HomePad uses the front camera to recognize household members who set
up face recognition. Images are analyzed on this iPad and are not saved or sent anywhere."

**Touch ID needs no usage string.** `NSFaceIDUsageDescription` is for Face ID only: the
`LAContext.h` header describes it as the message shown "when the app is trying to use Face ID for
the first time", and names no key for Touch ID. This package never evaluates a Face ID policy. On
an iPad with Face ID it only calls `canEvaluatePolicy` to learn the sensor type and then does not
offer the unlock.

**On-device only.** Frames, crops, embeddings, and templates stay on the device. The package has no
network code. Under Apple's definition, data that is processed only on the device is not
"collected", so the privacy nutrition label does not list face data for this feature. That
changes if any other part of the app ever sends face data off the device.

**Biometric data.** A face template is biometric data under several laws, for example the Illinois
Biometric Information Privacy Act, the Texas and Washington biometric laws, and the GDPR in
Europe, which treats biometric data used for identification as a special category. Some of them
require written consent and a retention and deletion policy even when the data never leaves the
device. Get legal review before you distribute the app beyond your own household.

**Consent.** `FaceEnrollmentView` explains the feature and asks for agreement before the camera
starts. The person who enrolls must be the person who agrees. A parent or guardian decides for a
child. The camera also sees people who never enrolled, such as guests. Their faces are analyzed
for a match and discarded, and nothing about them is stored.

**Deletion.** `PeopleSetupView` deletes one person's face data on request. Removing a person
deletes their template, whoever removes them. `FaceRecognitionService.deleteAllFaceData()` deletes
every template. Deleting the app removes the app's data, but Keychain items can survive an app
deletion on the same device, so offer "delete all face data" somewhere a person can find it before
they uninstall.

**App Review.** Three guidelines apply:

- 2.5.13: apps that use facial recognition for account authentication must use
  `LocalAuthentication` where possible, and must offer another method for users under 13. This
  feature personalizes a shared screen and does not sign anyone in to an account. Describe it that
  way in the review notes, and do not call it authentication or security in the app or its
  marketing.
- 2.5.14: apps must ask for consent and give a clear visual indication when they record or log user
  activity, including camera use. The system shows the green camera indicator, and
  `RecognitionIndicatorView` shows what the hub currently sees.
- 5.1.2(vi): data from depth and facial mapping tools, including the Camera APIs, may not be used
  for marketing, advertising, or use-based data mining.

**Multitasking camera access.** The pipeline turns on `isMultitaskingCameraAccessEnabled` when the
device supports it, so the camera keeps running when HomePad shares the screen with another app.

## Using it from the app

```swift
let settings = HomePadSettings()
settings.register(GeneralSettings.descriptors + FaceSettings.descriptors)
let session = HouseholdSession(store: try FileProfileStore.applicationSupport())

let embedder = await FaceEmbedderFactory.loadDefault()
let faces = FaceRecognitionService(session: session, settings: settings, embedder: embedder)
let touchID = DeviceBiometricUnlock(session: session, settings: settings, service: faces)
await faces.start()
```

- `start()` asks for recognition. The camera then follows the "Recognize Faces" setting and the
  app's foreground state without further calls. The first call shows the system camera prompt.
- Call `settings.refresh()` when the scene becomes active, so a change made in Settings is picked
  up.
- `DeviceBiometricUnlockButton(unlock:)` is the Touch ID button. It shows only while
  `touchID.isOffered` is true. Other views can read `isOffered` and call `unlock()` themselves.
- `PeopleSetupView(session:service:)` is the setup screen.
  `RecognitionIndicatorView(service:session:unlock:)` is the status capsule. `FaceEnrollmentView(profile:service:onFinish:)` is presented by
  `PeopleSetupView` and can also be presented directly.

## Calibration

None of the numeric thresholds has been checked on a device. Before trusting the feature, check
these on the target iPad, in the room where it will stand:

| What | Where | How to check |
|---|---|---|
| Match threshold and margin | `MatchPolicy.sFace`, "Match Strictness" | Enroll everyone. Log similarity for known same-person and different-person pairs in a debug build, and pick a threshold between the two groups. Do not ship the logging. |
| Yaw sign | `FaceAnalyzer.Configuration.yawSign` | During enrollment, turn left. If the right-hand arc fills, flip the sign. |
| Pose buckets | `HeadPoseBucketing` | Check that a comfortable head turn reaches each bucket. |
| Capture quality bounds | `EnrollmentPolicy`, `RecognitionEngineConfiguration` | Check typical `faceCaptureQuality` values in the room's light. |
| Depth liveness | `DepthLivenessPolicy` | Compare plane residual and center relief for real faces against a printed photo, a phone, and a tablet, at several distances. |
| Near and far | `ProximityPolicy`, "Show More Detail When" | Check the face size fraction at the distances that should count as near. |
| Frame rates | `FrameRatePolicy` | Measure energy use and time to recognition. |

## Not verified

- Nothing in `HomePadFace` has run on a device or in a simulator. It compiles for iOS.
- The depth liveness thresholds, the capture quality bounds, and the proximity bounds are
  estimates.
- Recognition accuracy with Vision-derived alignment has not been measured.
- The mapping from the capture rotation angle to image orientation follows the API documentation
  and has not been checked in all four interface orientations.
- The mirror preview, the preview frame rate, and the direction of `facePosition` have not been
  seen on a device.
- The Touch ID unlock has not run on a device. Its decision flow is unit-tested with a fake
  prompt. The real prompt, the hidden fallback button, and the lockout path are untested.

## Sources

- [App Review Guidelines, sections 2.5.13, 2.5.14, and 5.1.2(vi)](https://developer.apple.com/app-store/review/guidelines/), read 2026-11-17
- `docs/FACE_MODEL.md` and `HomePad/Models/NOTICE.md` in this repository, for the SFace contract, thresholds, and license
- Vision header `VNObservation.h` in the iOS 27.2 SDK, for the yaw, pitch, roll, and capture quality definitions
- AVFoundation headers `AVCaptureSession.h` and `AVCaptureDevice.h` in the iOS 27.2 SDK, for multitasking camera access and the rotation coordinator
- LocalAuthentication headers `LAContext.h`, `LAError.h`, and `LAPublicDefines.h` in the iOS 27.2 SDK, for the biometrics-only policy, the fallback button, the error codes, and `NSFaceIDUsageDescription`
