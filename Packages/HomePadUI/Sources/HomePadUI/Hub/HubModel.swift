import Foundation
import HomePadCore
import HomePadUICore
import Observation

/// View state of the hub shell that is not navigation: whose layout is showing, the face in
/// view, and night mode.
@MainActor
@Observable
final class HubModel {
    private(set) var owner: LayoutOwner = .guest
    private(set) var layout: HomeScreenLayout
    /// The face the pager is resting on. Bound to the pager's scroll position.
    var face: FaceKind?
    private(set) var night: NightAppearance = .day
    var showsSwitcher = false
    var helloDismissed = false
    var liveCameraID: String?

    @ObservationIgnored private let layoutStore: any LayoutStore
    @ObservationIgnored let screen = ScreenController()
    @ObservationIgnored private var wakeUntil: Date?
    @ObservationIgnored private(set) var lastInteraction = Date()
    @ObservationIgnored private var lastSummary: HubStatusSummary?

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

    /// Any touch counts as someone using the hub, and wakes it for a moment at night.
    func touch(at date: Date = Date()) {
        lastInteraction = date
        wakeUntil = NightModePolicy.wakeDeadline(from: date)
    }

    func updateNight(schedule: NightSchedule, ambient: AmbientLightHint?, now: Date, calendar: Calendar) {
        let appearance = NightModePolicy.appearance(schedule: schedule, now: now, calendar: calendar, ambient: ambient, wakeUntil: wakeUntil)
        if appearance != night {
            night = appearance
        }
        if case .night(let brightness) = appearance {
            screen.setNightBrightness(brightness)
        } else {
            screen.setNightBrightness(nil)
        }
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
