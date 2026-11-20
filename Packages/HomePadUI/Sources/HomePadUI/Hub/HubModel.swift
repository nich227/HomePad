import Foundation
import HomePadCore
import HomePadUICore
import Observation
import SwiftUI

/// View state of the hub shell that is not navigation: whose layout is showing, the face in
/// view, Night Mode, Do Not Disturb, and the live pill.
@MainActor
@Observable
final class HubModel {
    private(set) var owner: LayoutOwner = .guest
    private(set) var layout: HomeScreenLayout
    /// The face the pager is resting on. Bound to the pager's scroll position.
    var face: FaceKind?
    private(set) var night: NightAppearance = .day
    /// Do Not Disturb, while it is on. In memory only.
    private(set) var quiet: QuietTime?
    /// The screen brightness set from the control center, 0...1.
    private(set) var brightness: Double = 1
    var helloDismissed = false
    /// The live pill is open as a card.
    var isPillExpanded = false
    /// How wide the status in the top trailing corner is, so the pill beside it can stay clear.
    var statusWidth: CGFloat = 0
    /// Where on the canvas the open app's icon is, so the app grows from it and shrinks back.
    var appAnchor = UnitPoint.center
    /// The member the hub just recognized, shown in the pill for a moment.
    private(set) var recognizedName: String?

    @ObservationIgnored private let layoutStore: any LayoutStore
    @ObservationIgnored let screen = ScreenController()
    /// Night Mode switched by hand. In memory only, and gone at the next start or end hour.
    @ObservationIgnored private var nightOverride: NightOverride?
    @ObservationIgnored private(set) var lastInteraction = Date()
    /// True while a finger is down in a drag that began where a swipe opens the control center
    /// or the assistant. Whatever is under the finger leaves that drag alone.
    @ObservationIgnored var dragStartsOverlay = false
    @ObservationIgnored private var lastSummary: HubStatusSummary?
    @ObservationIgnored private var welcomeFinished = false
    @ObservationIgnored private var recognizedUntil: Date?

    init(layoutStore: any LayoutStore) {
        self.layoutStore = layoutStore
        // The stored layout is read in `adopt`, once the view is on screen, so that building
        // the view again does not touch the disk.
        layout = .defaultLayout(for: .guest)
    }

    /// Switches to another person's layout and the face they used last.
    func adopt(owner: LayoutOwner, enabledFaces: [FaceKind]) {
        self.owner = owner
        layout = layoutStore.layout(for: owner)
        face = FacePager.initialFace(lastFace: layout.lastFace, enabled: enabledFaces)
    }

    /// Keeps the resting face valid when faces are turned on or off in Settings.
    func reconcileFace(enabledFaces: [FaceKind]) {
        let current = face ?? layout.lastFace
        face = FacePager.initialFace(lastFace: current, enabled: enabledFaces)
    }

    func rememberFace(_ kind: FaceKind) {
        guard layout.lastFace != kind else { return }
        layout.lastFace = kind
        try? layoutStore.save(layout, for: owner)
    }

    func step(_ step: Int, enabledFaces: [FaceKind]) {
        guard let face else { return }
        self.face = FacePager.face(from: face, step: step, in: enabledFaces)
    }

    func move(itemID: String, onto targetID: String) {
        layout.move(itemID: itemID, onto: targetID)
        try? layoutStore.save(layout, for: owner)
    }

    /// Any touch counts as someone using the hub.
    func touch(at date: Date = Date()) {
        lastInteraction = date
    }

    /// Returns true the first time it is called, so the owner is told exactly once.
    func markWelcomeFinished() -> Bool {
        guard !welcomeFinished else { return false }
        welcomeFinished = true
        return true
    }

    /// `forced` shows Night Mode regardless of the schedule. Only UI tests set it, and the
    /// control center's switch still turns it off.
    func updateNight(schedule: NightSchedule, ambient: AmbientLightHint?, now: Date, calendar: Calendar, forced: Bool = false) {
        var appearance = NightModePolicy.appearance(schedule: schedule, now: now, calendar: calendar, ambient: ambient, override: nightOverride)
        if forced, NightModePolicy.active(nightOverride, now: now) == nil {
            appearance = .night(brightness: NightModePolicy.dimBrightness)
        }
        if appearance != night {
            night = appearance
        }
        if case .night(let brightness) = appearance {
            screen.setNightBrightness(brightness)
        } else {
            screen.setNightBrightness(nil)
        }
        if let quiet, !quiet.isActive(at: now) {
            self.quiet = nil
        }
        if let recognizedUntil, recognizedUntil <= now {
            self.recognizedUntil = nil
            recognizedName = nil
        }
    }

    /// The control center's switch: the opposite of what is showing, until the next start or
    /// end hour.
    func toggleNight(schedule: NightSchedule, ambient: AmbientLightHint?, now: Date, calendar: Calendar) {
        nightOverride = NightModePolicy.toggled(from: night, schedule: schedule, now: now, calendar: calendar)
        updateNight(schedule: schedule, ambient: ambient, now: now, calendar: calendar)
    }

    /// Night Mode asked for by name from outside the shell. The same as the switch when it is
    /// a change, and nothing when it is not.
    func setNight(_ isNight: Bool, schedule: NightSchedule, ambient: AmbientLightHint?, now: Date, calendar: Calendar, forced: Bool) {
        nightOverride = NightModePolicy.override(setting: isNight, from: night, existing: nightOverride, schedule: schedule, now: now, calendar: calendar)
        updateNight(schedule: schedule, ambient: ambient, now: now, calendar: calendar, forced: forced)
    }

    func toggleQuiet(schedule: NightSchedule, now: Date, calendar: Calendar) {
        quiet = QuietTime.toggled(from: quiet, schedule: schedule, now: now, calendar: calendar)
    }

    func isQuiet(at date: Date = Date()) -> Bool {
        quiet?.isActive(at: date) ?? false
    }

    /// Reads the screen's brightness, so the control center's slider starts where the screen is.
    func readBrightness() {
        if let current = screen.brightness {
            brightness = current
        }
    }

    func setBrightness(_ value: Double) {
        brightness = min(max(value, 0), 1)
        screen.setBrightness(brightness)
    }

    /// Shows the member's avatar and name in the pill for a moment.
    func confirmRecognition(of name: String, at date: Date = Date()) {
        recognizedName = name
        recognizedUntil = date.addingTimeInterval(LivePill.recognitionSeconds)
    }

    /// Returns the summary when it differs from the last one handed out, ignoring its timestamp,
    /// or when the last one is about to go stale.
    func summaryIfChanged(_ summary: HubStatusSummary) -> HubStatusSummary? {
        if let lastSummary {
            var comparable = summary
            comparable.updatedAt = lastSummary.updatedAt
            let age = summary.updatedAt.timeIntervalSince(lastSummary.updatedAt)
            if comparable == lastSummary, age < HubStatusSummary.freshFor / 2 { return nil }
        }
        lastSummary = summary
        return summary
    }
}
