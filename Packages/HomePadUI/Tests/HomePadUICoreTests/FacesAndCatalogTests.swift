import Foundation
import HomePadCore
import Testing
@testable import HomePadUICore

@Suite struct FaceTests {
    @Test func normalized_whenDuplicatesAndShuffled_thenCatalogOrder() {
        #expect(FacePager.normalized([.rainbow, .modular, .rainbow]) == [.modular, .rainbow])
        #expect(FacePager.normalized([]) == [.digital])
    }

    @Test func initialFace_whenLastFaceStillEnabled_thenRestoresIt() {
        #expect(FacePager.initialFace(lastFace: .flow, enabled: [.modular, .flow]) == .flow)
        #expect(FacePager.initialFace(lastFace: .flow, enabled: [.modular, .analog]) == .modular)
        #expect(FacePager.initialFace(lastFace: nil, enabled: [.analog]) == .analog)
    }

    @Test func faceFromStep_whenAtEnds_thenWraps() {
        let enabled: [FaceKind] = [.modular, .flow, .rainbow]
        #expect(FacePager.face(from: .rainbow, step: 1, in: enabled) == .modular)
        #expect(FacePager.face(from: .modular, step: -1, in: enabled) == .rainbow)
        #expect(FacePager.face(from: .flow, step: 1, in: enabled) == .rainbow)
        #expect(FacePager.face(from: .analog, step: 1, in: enabled) == .modular)
    }

    @Test func accentTint_whenProfile_thenFollowsActiveProfile() {
        #expect(FaceAccent.profile.tint(profileTint: .purple) == .purple)
        #expect(FaceAccent.profile.tint(profileTint: nil) == nil)
        #expect(FaceAccent.white.tint(profileTint: .red) == nil)
        let fixed: [FaceAccent] = [.green, .yellow, .orange, .red, .purple, .blue]
        #expect(fixed.map { $0.tint(profileTint: nil) } == [.green, .yellow, .orange, .red, .purple, .blue])
    }

    @Test func faceOptions_whenValuesOutOfRange_thenNormalized() {
        let options = FaceOptions(enabledFaces: [], photosAlbumName: "  Family ", photosShuffleMinutes: 0)
        #expect(options.enabledFaces == [.digital])
        #expect(options.photosAlbumName == "Family")
        #expect(options.photosShuffleMinutes == 1)
        #expect(FaceOptions().enabledFaces == FaceKind.allCases)
    }

    @Test func faceMetadata_whenQueried_thenMatchesCatalog() {
        #expect(FaceKind.homeModular.needsHome && FaceKind.homeCamera.needsHome && !FaceKind.flow.needsHome)
        #expect(FaceKind.fade.id == "fade")
        #expect(AnalogNumeralStyle.large.hours == [12, 3, 6, 9])
        #expect(AnalogNumeralStyle.all.hours.count == 12)
        #expect(AnalogNumeralStyle.none.hours.isEmpty)
        #expect(AnalogDialColor.green.tint == .green)
        #expect(AnalogDialColor.black.tint == nil)
    }

    @Test func photoRotation_whenTimePasses_thenAdvancesAndWraps() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        #expect(PhotoRotation.index(count: 0, at: start, shuffleMinutes: 5) == nil)
        #expect(PhotoRotation.index(count: 3, at: start, shuffleMinutes: 5) == 0)
        #expect(PhotoRotation.index(count: 3, at: start.addingTimeInterval(299), shuffleMinutes: 5) == 0)
        #expect(PhotoRotation.index(count: 3, at: start.addingTimeInterval(300), shuffleMinutes: 5) == 1)
        #expect(PhotoRotation.index(count: 3, at: start.addingTimeInterval(900), shuffleMinutes: 5) == 0)
        #expect(PhotoRotation.index(count: 3, at: start.addingTimeInterval(-300), shuffleMinutes: 0) == 1)
    }
}

@Suite struct CatalogTests {
    private let guest = AudienceContext(isGuest: true, isPersonalContentUnlocked: false, setupMode: false)
    private let manual = AudienceContext(isGuest: false, isPersonalContentUnlocked: false, setupMode: false)
    private let unlocked = AudienceContext(isGuest: false, isPersonalContentUnlocked: true, setupMode: false)
    private let guestSetup = AudienceContext(isGuest: true, isPersonalContentUnlocked: false, setupMode: true)

    @Test func visibility_whenGuest_thenOnlyGuestAppsShow() {
        let visible = HubApp.allCases.filter { VisibilityPolicy.visibility(of: $0, context: guest) == .visible }
        #expect(Set(visible) == [.clock, .timers, .home, .music, .mirror, .recipes, .weather, .beam, .settings])
        #expect(VisibilityPolicy.visibility(of: HubApp.projectedApps, context: guest) == .hidden)
        #expect(VisibilityPolicy.visibility(of: .alarms, context: guest) == .hidden)
    }

    @Test func visibility_whenProfilePickedByHand_thenPersonalAppsAreRedacted() {
        #expect(VisibilityPolicy.visibility(of: HubApp.projectedApps, context: manual) == .redacted)
        #expect(VisibilityPolicy.visibility(of: .projectedApps, context: manual) == .redacted)
        #expect(VisibilityPolicy.visibility(of: .alarms, context: manual) == .visible)
        #expect(!VisibilityPolicy.canOpen(.projectedApps, context: manual))
        #expect(VisibilityPolicy.canOpen(.timers, context: manual))
    }

    @Test func visibility_whenFaceUnlocked_thenPersonalAppsOpen() {
        #expect(VisibilityPolicy.visibility(of: HubApp.projectedApps, context: unlocked) == .visible)
        #expect(VisibilityPolicy.canOpen(.projectedApps, context: unlocked))
    }

    @Test func visibility_whenSetupModeOff_thenPeopleAndPairingHidden() {
        #expect(VisibilityPolicy.visibility(of: .people, context: unlocked) == .hidden)
        #expect(VisibilityPolicy.visibility(of: .pairing, context: guest) == .hidden)
        #expect(VisibilityPolicy.visibility(of: .people, context: guestSetup) == .visible)
        #expect(VisibilityPolicy.visibility(of: .pairing, context: guestSetup) == .visible)
    }

    @Test func widgetVisibility_whenMemberOnly_thenHiddenForGuests() {
        #expect(VisibilityPolicy.visibility(of: HubWidgetKind.nextAlarm, context: guest) == .hidden)
        #expect(VisibilityPolicy.visibility(of: HubWidgetKind.nextAlarm, context: manual) == .visible)
        #expect(VisibilityPolicy.visibility(of: HubWidgetKind.timers, context: guest) == .visible)
        #expect(VisibilityPolicy.visibility(for: .personal, context: guest) == .hidden)
        #expect(VisibilityPolicy.visibility(for: .personal, context: manual) == .redacted)
        #expect(VisibilityPolicy.visibility(for: .personal, context: unlocked) == .visible)
    }

    @Test func tapAction_whenPersonalItemIsLocked_thenUnlockOnlyWhileTheDeviceOffersIt() {
        #expect(VisibilityPolicy.tapAction(for: .personal, context: manual, isDeviceUnlockOffered: false) == TapAction.none)
        #expect(VisibilityPolicy.tapAction(for: .personal, context: manual, isDeviceUnlockOffered: true) == .requestUnlock)
        #expect(VisibilityPolicy.tapAction(for: .personal, context: unlocked, isDeviceUnlockOffered: true) == .open)
        #expect(VisibilityPolicy.tapAction(for: .personal, context: guest, isDeviceUnlockOffered: true) == TapAction.none)
        #expect(VisibilityPolicy.tapAction(for: .guest, context: guest, isDeviceUnlockOffered: false) == .open)
        #expect(VisibilityPolicy.tapAction(for: .member, context: manual, isDeviceUnlockOffered: true) == .open)
    }

    @Test func appToOpen_whenUnlockWorked_thenTheTappedAppOpensOtherwiseNothing() {
        #expect(VisibilityPolicy.appToOpen(afterUnlock: true, requested: .projectedApps, context: unlocked) == .projectedApps)
        #expect(VisibilityPolicy.appToOpen(afterUnlock: false, requested: .projectedApps, context: unlocked) == nil)
        #expect(VisibilityPolicy.appToOpen(afterUnlock: true, requested: .projectedApps, context: manual) == nil)
        #expect(VisibilityPolicy.appToOpen(afterUnlock: true, requested: nil, context: unlocked) == nil)
    }

    @Test func showsDeviceUnlock_whenPersonalizedButLockedAndOffered_thenTrue() {
        #expect(VisibilityPolicy.showsDeviceUnlock(context: manual, isDeviceUnlockOffered: true))
        #expect(!VisibilityPolicy.showsDeviceUnlock(context: manual, isDeviceUnlockOffered: false))
        #expect(!VisibilityPolicy.showsDeviceUnlock(context: unlocked, isDeviceUnlockOffered: true))
        #expect(!VisibilityPolicy.showsDeviceUnlock(context: guest, isDeviceUnlockOffered: true))
    }

    @Test func isListed_whenAnOptionalAppHasNothingBehindIt_thenItHasNoIcon() {
        #expect(VisibilityPolicy.isListed(.music, available: []))
        #expect(!VisibilityPolicy.isListed(.intercom, available: []))
        #expect(!VisibilityPolicy.isListed(.calendar, available: [.intercom]))
        #expect(VisibilityPolicy.isListed(.intercom, available: [.intercom]))
        #expect(VisibilityPolicy.visibility(of: HubApp.intercom, context: guest) == .hidden)
        #expect(VisibilityPolicy.visibility(of: HubApp.calendar, context: manual) == .redacted)
    }

    @Test func needsSetupHint_whenNobodyEnrolledAndSetupOff_thenTrue() {
        #expect(VisibilityPolicy.needsSetupHint(profileCount: 0, setupMode: false))
        #expect(!VisibilityPolicy.needsSetupHint(profileCount: 0, setupMode: true))
        #expect(!VisibilityPolicy.needsSetupHint(profileCount: 2, setupMode: false))
    }

    @Test func catalog_whenEnumerated_thenEveryEntryHasMetadata() {
        for app in HubApp.allCases {
            #expect(!app.symbolName.isEmpty)
            #expect(app.id == app.rawValue)
            #expect(app.requiresPersonalContent == (app.access == .personal))
            _ = app.tint
        }
        #expect(HubApp.allCases.filter(\.isSlot) == [.beam, .projectedApps, .people, .pairing, .intercom, .calendar])
        #expect(HubApp.allCases.filter(\.isOptional) == [.intercom, .calendar])
        #expect(HubApp.intercom.access == .member && HubApp.calendar.access == .personal)
        #expect(HubApp.clock.tint == nil && HubApp.home.tint != nil)
        for widget in HubWidgetKind.allCases {
            #expect(widget.id == widget.rawValue)
            #expect(!widget.requiresPersonalContent)
        }
        #expect(HubWidgetKind.allCases.map(\.app) == [.clock, .clock, .weather, .timers, .alarms, .music, .home, .home, .home, .photos])
    }
}
