# Kiosk Lock

Kiosk Lock keeps the iPad on HomePad. To reach the Home Screen, someone taps the lock in HomePad
and enters the iPad passcode. Face ID and Touch ID do not satisfy the prompt.

## What iPadOS allows

An app cannot block the Home gesture by itself. iPadOS offers two mechanisms:

| Mechanism | Who starts it | How it ends | Needs |
|---|---|---|---|
| Autonomous Single App Mode | The app, when the Settings toggle is on | The app releases it after the iPad passcode is entered | A supervised iPad with a profile that names `com.kevster.HomePad` |
| Guided Access | A person, by triple-clicking the top button | Triple-click, then the Guided Access passcode | Nothing. Works on any iPad |

HomePad uses Single App Mode when the iPad permits it. When the iPad refuses, HomePad stays
unlocked and, while Setup Mode is on, shows a hint to start Guided Access by hand. If someone
starts Guided Access, HomePad treats the iPad as locked and does not ask for anything else.

The Guided Access passcode is set under Settings > Accessibility > Guided Access > Passcode
Settings. It is separate from the iPad passcode, although you can choose the same digits.

## Set up Single App Mode

Supervising an iPad erases it. Back it up first.

1. Install Apple Configurator on a Mac and connect the iPad with a cable.
2. Select the iPad, choose Prepare, pick Manual Configuration, check Supervise devices, and leave
   MDM enrollment off. Finish the assistant. The iPad restarts as a supervised device.
3. In Apple Configurator choose Add > Profiles and pick `Config/HomePadKiosk.mobileconfig`.
4. Install HomePad on the iPad and set an iPad passcode if there is none.
5. Open Settings > Apps > HomePad > Kiosk Lock and turn on Require Passcode to Leave HomePad.
6. Open HomePad. A lock button appears in the corner once the iPad is locked to the app.

## Leaving HomePad

1. Tap the lock button and enter the iPad passcode.
2. HomePad shows a countdown. Swipe to the Home Screen before it ends.
3. HomePad locks again when you come back, or when the countdown ends if nobody left.

To stop locking altogether, leave HomePad as above and turn the setting off.

## Safeguards

- HomePad never locks an iPad that has no passcode, because there would be nothing to check.
- If the passcode is removed while the iPad is locked, the next unlock tap releases the lock.
- Turning the setting off while locked releases the lock on the next activation.
- A supervised iPad can always be released from Apple Configurator or by removing the profile.

## Files

| Path | Holds |
|---|---|
| `Packages/HomePadKiosk/Sources/HomePadKioskCore/KioskMachine.swift` | The state machine and the Settings rows |
| `Packages/HomePadKiosk/Sources/HomePadKioskCore/KioskLockController.swift` | Follows the setting and performs lock, unlock, and relock |
| `Packages/HomePadKiosk/Sources/HomePadKiosk/LiveKioskSystem.swift` | Single App Mode and the passcode-only prompt |
| `Packages/HomePadKiosk/Sources/HomePadKiosk/KioskLockOverlay.swift` | The lock button, countdown, and hints |
| `Config/HomePadKiosk.mobileconfig` | The profile that permits Single App Mode for HomePad |
