import Foundation
import HomePadAssistant
import HomePadAssistantCore
import HomePadBeam
import HomePadBeamCore
import HomePadCore
import HomePadMessaging
import HomePadMessagingCore
import HomePadUI
import HomePadUICore

/// The Assistant's hands in the hub. Each action goes to the service that owns it, and the
/// context the Assistant may use is read from those same services. Who may ask for what is
/// decided by the Assistant before it calls in; the checks here are the hub's own rules.
@MainActor
final class HubAssistantBridge: AssistantActions, AssistantHubContext {
    private let session: HouseholdSession
    private let settings: HomePadSettings
    private let environment: HubEnvironment
    private let navigator: HubNavigator
    private let receiver: BeamReceiver
    private let intercom: HouseholdIntercom
    private let projection: ProjectionClient
    private let link: PeerLink

    init(
        session: HouseholdSession,
        settings: HomePadSettings,
        environment: HubEnvironment,
        navigator: HubNavigator,
        receiver: BeamReceiver,
        intercom: HouseholdIntercom,
        projection: ProjectionClient,
        link: PeerLink
    ) {
        self.session = session
        self.settings = settings
        self.environment = environment
        self.navigator = navigator
        self.receiver = receiver
        self.intercom = intercom
        self.projection = projection
        self.link = link
    }

    private var audience: AudienceContext {
        AudienceContext(
            isGuest: session.isGuest,
            isPersonalContentUnlocked: session.isPersonalContentUnlocked,
            setupMode: settings[GeneralSettings.setupMode]
        )
    }

    private var temperatureUnit: TemperatureUnit {
        HubPreferences(settings: settings).temperatureUnit
            .resolved(localeUsesFahrenheit: Locale.current.measurementSystem == .us)
    }

    // MARK: Timers

    func startTimer(name: String?, duration: TimeInterval) async -> Result<AssistantTimer, AssistantActionError> {
        let timers = environment.timers
        guard let timer = timers.add(name: name ?? String(localized: "Timer"), duration: duration) else {
            switch timers.lastError {
            case .limitReached: return .failure(.limitReached)
            case .invalidDuration: return .failure(.invalid(.durationOutOfRange))
            default: return .failure(.unavailable)
            }
        }
        return .success(summary(of: timer))
    }

    func pauseTimer(name: String?) async -> Result<AssistantTimer, AssistantActionError> {
        guard let timer = timer(named: name) else { return .failure(.notFound(name ?? "")) }
        guard timer.isRunning else { return .failure(.unavailable) }
        environment.timers.pause(timer.id)
        guard let paused = environment.timers.engine.timers.first(where: { $0.id == timer.id }) else {
            return .failure(.unavailable)
        }
        return .success(summary(of: paused))
    }

    func cancelTimer(name: String?) async -> Result<AssistantTimer, AssistantActionError> {
        guard let timer = timer(named: name) else { return .failure(.notFound(name ?? "")) }
        let canceled = summary(of: timer)
        environment.timers.remove(timer.id)
        return .success(canceled)
    }

    func timers() async -> Result<[AssistantTimer], AssistantActionError> {
        .success(environment.timers.engine.activeTimers.map(summary(of:)))
    }

    /// The timer with this name, or with no name the one started last.
    private func timer(named name: String?) -> HubTimer? {
        let active = environment.timers.engine.activeTimers
        guard let name else { return active.max { $0.createdAt < $1.createdAt } }
        return NameMatch.best(for: name, in: active) { [$0.name] }
    }

    private func summary(of timer: HubTimer) -> AssistantTimer {
        var isPaused = false
        if case .paused = timer.state {
            isPaused = true
        }
        return AssistantTimer(
            id: timer.id,
            name: timer.name,
            remaining: environment.timers.engine.remaining(for: timer),
            isPaused: isPaused
        )
    }

    // MARK: Screen

    func show(named name: String) async -> Result<AssistantDestination, AssistantActionError> {
        if let face = NameMatch.best(for: name, in: navigator.enabledFaces, names: { [$0.displayName] }),
           navigator.showFace(face) {
            return .success(.face(face.displayName))
        }
        guard let app = NameMatch.best(for: name, in: HubApp.allCases, names: { [$0.displayName] }) else {
            return .failure(.notFound(name))
        }
        guard navigator.open(app, context: audience) else {
            return .failure(app.requiresPersonalContent ? .personalContentLocked : .unavailable)
        }
        return .success(.app(app.displayName))
    }

    func setNightMode(_ isOn: Bool) async -> Result<Bool, AssistantActionError> {
        navigator.setNightMode(isOn)
        return .success(isOn)
    }

    func screenSummary() async -> Result<String, AssistantActionError> {
        var parts = [String(localized: "The hub is showing \(navigator.screenTitle).")]
        let running = environment.timers.engine.activeTimers.count
        if running > 0 {
            parts.append(String(localized: "\(running) timers are set."))
        }
        if let playing = environment.music.nowPlaying, playing.isPlaying {
            parts.append(String(localized: "\(playing.title) by \(playing.artist) is playing."))
        }
        return .success(parts.joined(separator: " "))
    }

    // MARK: Home

    func runScene(named name: String) async -> Result<String, AssistantActionError> {
        let home = environment.home
        guard home.access == .ready else { return .failure(.unavailable) }
        guard HomeControlPolicy.mayRunScenes(activation: session.activation, profiles: session.profiles) else {
            return .failure(.needsRecognizedMember)
        }
        guard let scene = NameMatch.best(for: name, in: home.snapshot.scenes, names: { [$0.name] }) else {
            return .failure(.notFound(name))
        }
        await home.runScene(id: scene.id)
        return home.lastError == nil ? .success(scene.name) : .failure(.unavailable)
    }

    func setThermostat(targetCelsius: Double) async -> Result<AssistantThermostat, AssistantActionError> {
        let home = environment.home
        guard home.access == .ready, let thermostat = home.snapshot.thermostats.first else {
            return .failure(.unavailable)
        }
        guard ThermostatMath.celsiusRange.contains(targetCelsius) else {
            return .failure(.invalid(.temperatureOutOfRange))
        }
        await home.setTargetTemperature(celsius: targetCelsius, thermostatID: thermostat.id)
        guard home.lastError == nil else { return .failure(.unavailable) }
        return .success(AssistantThermostat(name: thermostat.name, targetCelsius: targetCelsius))
    }

    func setAccessory(named name: String, isOn: Bool) async -> Result<AssistantAccessory, AssistantActionError> {
        let home = environment.home
        guard home.access == .ready else { return .failure(.unavailable) }
        let found = NameMatch.best(for: name, in: home.snapshot.accessories) {
            [$0.name, "\($0.roomName) \($0.name)"]
        }
        guard let accessory = found else { return .failure(.notFound(name)) }
        guard accessory.isReachable else { return .failure(.unavailable) }
        guard HomeControlPolicy.mayOperate(accessory, turningOn: isOn, isGuest: session.isGuest) else {
            return .failure(.needsHouseholdMember)
        }
        await home.setPower(isOn, accessoryID: accessory.id)
        guard home.lastError == nil else { return .failure(.unavailable) }
        return .success(AssistantAccessory(name: accessory.name, isOn: isOn))
    }

    // MARK: Weather, pages, notes

    func weatherSummary() async -> Result<String, AssistantActionError> {
        guard let weather = environment.weather.snapshot else { return .failure(.unavailable) }
        return .success(text(for: weather))
    }

    private func text(for weather: WeatherSnapshot) -> String {
        let unit = temperatureUnit
        let now = unit.rounded(fromCelsius: weather.temperatureCelsius)
        let high = unit.rounded(fromCelsius: weather.highCelsius)
        let low = unit.rounded(fromCelsius: weather.lowCelsius)
        return String(localized: "\(weather.locationName): \(weather.conditionText), \(now) degrees, high \(high), low \(low).")
    }

    func openWebPage(_ url: URL) async -> Result<URL, AssistantActionError> {
        guard let link = BeamDeepLink.beamLink(for: url, title: nil), receiver.handle(url: link) else {
            return .failure(.invalid(.notAWebPage))
        }
        return .success(url)
    }

    func sendHouseholdNote(_ text: String) async -> Result<AssistantNoteReceipt, AssistantActionError> {
        let recipients = await link.connectedPeers().count
        switch await intercom.send(text: text) {
        case .sent: return .success(AssistantNoteReceipt(recipientCount: recipients))
        case .invalid: return .failure(.invalid(.emptyNote))
        case .disabled, .nobodyConnected: return .failure(.unavailable)
        }
    }

    // MARK: Context

    var hubState: AssistantHubState {
        AssistantHubState(
            hubName: settings[BeamSettings.hubName],
            screenTitle: navigator.screenTitle,
            isNightMode: navigator.isNightMode,
            usesFahrenheit: temperatureUnit == .fahrenheit
        )
    }

    /// Everything the hub knows that could help an answer. Items from a member's iPhone carry
    /// that member as their owner; the Assistant drops them unless that member is unlocked.
    func contextItems() async -> [AssistantContextItem] {
        var items: [AssistantContextItem] = []
        let engine = environment.timers.engine
        for timer in engine.activeTimers {
            let minutes = Int((engine.remaining(for: timer) / 60).rounded(.up))
            items.append(AssistantContextItem(
                id: "timer-\(timer.id.uuidString)",
                kind: .timer,
                title: timer.name,
                detail: String(localized: "\(minutes) minutes left")
            ))
        }
        if let weather = environment.weather.snapshot {
            items.append(AssistantContextItem(id: "weather", kind: .weather, title: text(for: weather)))
        }
        if let thermostat = environment.home.snapshot.thermostats.first {
            let unit = temperatureUnit
            let current = unit.rounded(fromCelsius: thermostat.currentCelsius)
            let target = unit.rounded(fromCelsius: thermostat.targetCelsius)
            items.append(AssistantContextItem(
                id: "thermostat-\(thermostat.id)",
                kind: .home,
                title: thermostat.name,
                detail: String(localized: "\(current) degrees inside, set to \(target)")
            ))
        }
        if let playing = environment.music.nowPlaying {
            items.append(AssistantContextItem(id: "now-playing", kind: .nowPlaying, title: playing.title, detail: playing.artist))
        }
        for summary in projection.contextSummaries() {
            items.append(AssistantContextItem(
                id: summary.id,
                kind: Self.kind(of: summary.kind),
                ownerID: summary.ownerProfileID,
                title: summary.title,
                detail: summary.detail
            ))
        }
        return items
    }

    private static func kind(of kind: ProjectedContextSummary.Kind) -> AssistantContextItem.Kind {
        switch kind {
        case .calendarEvent: .calendarEvent
        case .reminder: .reminder
        case .nowPlaying: .nowPlaying
        }
    }
}

/// Finds the thing a spoken or typed name refers to: an exact match first, then a name that
/// contains what was said or is contained in it ("the weather face" finds Weather).
enum NameMatch {
    static func best<Item>(for spoken: String, in items: [Item], names: (Item) -> [String]) -> Item? {
        let wanted = fold(spoken)
        guard !wanted.isEmpty else { return nil }
        if let exact = items.first(where: { names($0).contains { fold($0) == wanted } }) {
            return exact
        }
        return items.first { item in
            names(item).contains { name in
                let folded = fold(name)
                return !folded.isEmpty && (folded.contains(wanted) || wanted.contains(folded))
            }
        }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
