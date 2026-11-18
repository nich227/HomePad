import Foundation
import HomePadCore
import HomePadMessagingCore
import Observation

/// The companion side of projection. It serves this iPhone's projected apps to every connected
/// hub, keeps their navigation stacks, and carries out what a hub asks for.
@MainActor
@Observable
public final class ProjectionHost {
    /// Hubs this iPhone is connected to right now.
    public private(set) var connectedHubs: [PeerDevice] = []
    /// The apps being projected, after the Settings switches were applied.
    public private(set) var projectedApps: [ProjectedApp] = []
    /// The Messages app, for presenting replies that wait for the owner.
    public let messages: MessagesAppProvider

    @ObservationIgnored private let channel: any PeerChannel
    @ObservationIgnored private let settings: HomePadSettings
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let codec = ProjectionCodec()
    @ObservationIgnored private var state: ProjectionHostState
    @ObservationIgnored private var providers: [any ProjectedAppProvider]
    @ObservationIgnored private var peers: [UUID: PeerDevice] = [:]
    @ObservationIgnored private var dirtyApps: Set<String> = []
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var lastFullFlush = Date.distantPast
    /// How often every app's screens are rebuilt even without a change notice, so that events
    /// that have ended and messages past retention drop off.
    @ObservationIgnored private let fullFlushInterval: TimeInterval = 60
    @ObservationIgnored private var outbox: AsyncStream<Outgoing>.Continuation?

    private struct Outgoing: Sendable {
        let data: Data
        let hubID: UUID
        let completion: (@Sendable (Bool) -> Void)?
    }

    /// `providers` replaces the built-in Calendar, Reminders, and Now Playing apps. Messages is
    /// always present. Which of them are projected follows the switches in Settings.
    public init(
        channel: any PeerChannel,
        settings: HomePadSettings,
        providers: [any ProjectedAppProvider]? = nil,
        notifier: (any HomePadNotifying)? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.channel = channel
        self.settings = settings
        self.now = now
        self.state = ProjectionHostState(session: UUID())
        let owner = channel.localDevice.profileID ?? channel.localDevice.id
        self.messages = MessagesAppProvider(ownerID: owner, settings: settings, notifier: notifier ?? LocalNotifier(), now: now)
        self.providers = [messages] + (providers ?? [CalendarAppProvider(now: now), RemindersAppProvider(now: now), NowPlayingAppProvider()])
    }

    // MARK: Lifecycle

    /// Starts serving hubs. Safe to call more than once.
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        let (stream, continuation) = AsyncStream.makeStream(of: Outgoing.self)
        outbox = continuation
        let channel = channel
        // One task sends everything, so frames reach a hub in the order their sequence numbers
        // were assigned. It is not cancelled on stop: it ends when the stream is finished, after
        // every queued send has reported a result to whoever is waiting on it.
        Task {
            for await item in stream {
                do {
                    try await channel.send(item.data, on: PeerChannelName.projection, to: item.hubID)
                    item.completion?(true)
                } catch {
                    item.completion?(false)
                }
            }
        }
        let incoming = channel.messages(on: PeerChannelName.projection)
        tasks.append(Task { [weak self] in
            for await envelope in incoming {
                await self?.receive(envelope)
            }
        })
        tasks.append(Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        })
    }

    public func stop() {
        isRunning = false
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        flushTask?.cancel()
        flushTask = nil
        outbox?.finish()
        outbox = nil
        for provider in providers {
            provider.deactivate()
        }
        state = ProjectionHostState(session: UUID())
        projectedApps = []
        connectedHubs = []
        peers = [:]
    }

    /// Re-reads the Settings switches and the connected peers. Runs on a timer; call it as well
    /// when the scene becomes active or the transport reports a change.
    public func refresh() async {
        await syncProviders()
        await refreshPeers()
        if now().timeIntervalSince(lastFullFlush) >= fullFlushInterval {
            lastFullFlush = now()
            for app in state.apps {
                await flush(appID: app.id)
            }
        } else if state.apps.contains(where: { $0.id == messages.app.id }) {
            // Cheap, and it picks up a changed preview or retention setting.
            await flush(appID: messages.app.id)
        }
    }

    // MARK: Intents

    /// Takes a message from the Shortcuts automation, adds it to the Messages app, and sends the
    /// update to a hub, waiting a short time for one to connect.
    public func relayMessage(senderName: String, handle: String?, text: String) async -> MessageRelayOutcome {
        guard settings[MessagingSettings.projectMessages] else { return .disabled }
        start()
        await syncProviders()
        switch messages.receive(senderName: senderName, handle: handle, text: text) {
        case .failure(let error):
            return .rejected(error)
        case .success(.duplicate):
            return .duplicate
        case .success(.expired):
            return .keptForLater
        case .success(.inserted):
            break
        }
        let reached = await flush(appID: messages.app.id)
        if !reached.isEmpty {
            return .delivered(hubCount: reached.count)
        }
        let delivered = await waitForHub()
        return delivered > 0 ? .delivered(hubCount: delivered) : .keptForLater
    }

    /// Asks every connected hub to bring one of this iPhone's apps to the front.
    public func present(appID: String) async -> HubCommandOutcome {
        start()
        await syncProviders()
        guard state.apps.contains(where: { $0.id == appID }) else { return .rejected }
        var reached = await send(.present(appID: appID))
        if reached.isEmpty, await waitForHub() > 0 {
            reached = await send(.present(appID: appID))
        }
        return reached.isEmpty ? .noHubReachable : .delivered(hubCount: reached.count)
    }

    /// The provider for one of the built-in or supplied apps.
    public func provider(appID: String) -> (any ProjectedAppProvider)? {
        providers.first { $0.app.id == appID }
    }

    // MARK: Providers

    private func syncProviders() async {
        let enabled = MessagingSettings.enabledAppIDs(
            messages: settings[MessagingSettings.projectMessages],
            calendar: settings[MessagingSettings.projectCalendar],
            reminders: settings[MessagingSettings.projectReminders],
            nowPlaying: settings[MessagingSettings.projectNowPlaying]
        )
        let builtIn: Set<String> = [
            BuiltInProjectedApp.messagesID, BuiltInProjectedApp.calendarID,
            BuiltInProjectedApp.remindersID, BuiltInProjectedApp.nowPlayingID,
        ]
        for provider in providers {
            let appID = provider.app.id
            let wanted = !builtIn.contains(appID) || enabled.contains(appID)
            let registered = state.apps.contains { $0.id == appID }
            if wanted, !registered {
                await provider.activate { [weak self] in self?.invalidate(appID: appID) }
                let root = await provider.template(id: provider.rootTemplateID)
                    ?? placeholderTemplate(id: provider.rootTemplateID, title: provider.app.name, message: String(localized: "Nothing to show."))
                if let messages = try? state.register(provider.app, root: root) {
                    for message in messages {
                        _ = enqueue(message)
                    }
                } else {
                    provider.deactivate()
                }
            } else if !wanted, registered {
                provider.deactivate()
                if let messages = try? state.unregister(appID: appID) {
                    for message in messages {
                        _ = enqueue(message)
                    }
                }
            }
        }
        if projectedApps != state.apps {
            projectedApps = state.apps
        }
    }

    private func invalidate(appID: String) {
        dirtyApps.insert(appID)
        guard flushTask == nil else { return }
        // Several changes in the same turn of the run loop become one pass.
        flushTask = Task { [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled else { return }
            self.flushTask = nil
            let apps = self.dirtyApps
            self.dirtyApps.removeAll()
            for appID in apps {
                _ = await self.flush(appID: appID)
            }
        }
    }

    /// Asks the provider for the current version of every screen in the app's stack and sends what
    /// changed. Returns the hubs that received all of it.
    @discardableResult
    private func flush(appID: String) async -> Set<UUID> {
        guard let provider = provider(appID: appID) else { return [] }
        var pending: [[PendingSend]] = []
        for (index, shown) in state.stack(appID: appID).enumerated() {
            if let fresh = await provider.template(id: shown.id) {
                if let message = try? state.update(appID: appID, template: fresh) {
                    pending.append(enqueue(message))
                }
            } else if index > 0 {
                // The screen is gone, and so is everything above it.
                while state.stack(appID: appID).count > index, let message = try? state.pop(appID: appID) {
                    pending.append(enqueue(message))
                }
                break
            }
        }
        return await delivered(pending)
    }

    // MARK: Hubs

    private func refreshPeers() async {
        let connected = await channel.connectedPeers()
        peers = Dictionary(connected.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let added = state.reconcile(connected: connected)
        let hubs = connected.filter { $0.role == .hub }
        if connectedHubs != hubs {
            connectedHubs = hubs
        }
        for hubID in added {
            _ = enqueueSnapshot(to: hubID)
        }
    }

    /// Polls for a hub for a bounded time and sends it the full state. Returns how many hubs received it.
    private func waitForHub() async -> Int {
        let startedAt = now()
        while IntentTiming.shouldKeepWaiting(startedAt: startedAt, now: now()) {
            let connected = await channel.connectedPeers()
            peers = Dictionary(connected.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let added = state.reconcile(connected: connected)
            connectedHubs = connected.filter { $0.role == .hub }
            if !added.isEmpty {
                let reached = await delivered(added.map { enqueueSnapshot(to: $0) })
                if !reached.isEmpty {
                    return reached.count
                }
            }
            try? await Task.sleep(for: .seconds(IntentTiming.pollInterval))
            if Task.isCancelled { break }
        }
        return 0
    }

    private func receive(_ envelope: PeerEnvelope) async {
        if peers[envelope.sender] == nil {
            await refreshPeers()
        }
        guard let hub = peers[envelope.sender],
              let frame = try? codec.decodeHubFrame(envelope.payload),
              let events = try? state.receive(frame, from: hub, now: now())
        else { return }
        for event in events {
            await handle(event)
        }
    }

    private func handle(_ event: ProjectionHostEvent) async {
        switch event {
        case .sendSnapshot(let hubID):
            await syncProviders()
            _ = enqueueSnapshot(to: hubID)
        case .launch(let appID, _):
            await provider(appID: appID)?.launched()
            await flush(appID: appID)
        case .action(let appID, let actionID, let payload, _):
            guard let provider = provider(appID: appID) else { return }
            let navigation = await provider.handle(actionID: actionID, payload: payload)
            await apply(navigation, appID: appID, provider: provider)
        case .back(let appID, _):
            if let message = try? state.pop(appID: appID) {
                _ = enqueue(message)
            }
        case .reply(let conversationID, let text, _):
            await messages.queueReply(conversationID: conversationID, text: text)
        case .mediaCommand(let command, _):
            provider(appID: BuiltInProjectedApp.nowPlayingID)?.handle(mediaCommand: command)
        }
    }

    private func apply(_ navigation: ProjectionNavigation, appID: String, provider: any ProjectedAppProvider) async {
        switch navigation {
        case .none:
            break
        case .pop:
            if let message = try? state.pop(appID: appID) {
                _ = enqueue(message)
            }
        case .showDetail(let templateID):
            guard let template = await provider.template(id: templateID) else { return }
            while let message = try? state.pop(appID: appID) {
                _ = enqueue(message)
            }
            if let message = try? state.push(appID: appID, template: template) {
                _ = enqueue(message)
            }
        case .push(let templateID):
            guard let template = await provider.template(id: templateID),
                  let message = try? state.push(appID: appID, template: template)
            else { return }
            _ = enqueue(message)
        }
    }

    // MARK: Sending

    private final class PendingSend: Sendable {
        let hubID: UUID
        private let result = ResultBox()

        init(hubID: UUID) {
            self.hubID = hubID
        }

        func complete(_ success: Bool) {
            result.set(success)
        }

        func wait() async -> Bool {
            await result.value()
        }
    }

    /// Frames the message and queues it for every hub. Synchronous, so the order of calls is the
    /// order on the wire.
    private func enqueue(_ message: HostToHubMessage, to hubIDs: Set<UUID>? = nil) -> [PendingSend] {
        let targets = hubIDs ?? state.hubIDs
        guard let outbox, !targets.isEmpty,
              let data = try? codec.encode(state.frame(for: message))
        else { return [] }
        return targets.map { hubID in
            let pending = PendingSend(hubID: hubID)
            outbox.yield(Outgoing(data: data, hubID: hubID) { pending.complete($0) })
            return pending
        }
    }

    private func enqueueSnapshot(to hubID: UUID) -> [PendingSend] {
        state.snapshot().flatMap { enqueue($0, to: [hubID]) }
    }

    private func send(_ message: HostToHubMessage) async -> Set<UUID> {
        await delivered([enqueue(message)])
    }

    /// The hubs for which every one of the given sends succeeded.
    private func delivered(_ groups: [[PendingSend]]) async -> Set<UUID> {
        var failed: Set<UUID> = []
        var seen: Set<UUID> = []
        for pending in groups.flatMap({ $0 }) {
            seen.insert(pending.hubID)
            if await !pending.wait() {
                failed.insert(pending.hubID)
            }
        }
        return seen.subtracting(failed)
    }
}

/// A one-shot boolean that can be set from any thread and awaited.
private final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Bool?
    private var waiters: [CheckedContinuation<Bool, Never>] = []

    func set(_ value: Bool) {
        let pending = lock.withLock { () -> [CheckedContinuation<Bool, Never>] in
            guard result == nil else { return [] }
            result = value
            defer { waiters.removeAll() }
            return waiters
        }
        for waiter in pending {
            waiter.resume(returning: value)
        }
    }

    func value() async -> Bool {
        await withCheckedContinuation { continuation in
            let known = lock.withLock { () -> Bool? in
                if result == nil {
                    waiters.append(continuation)
                }
                return result
            }
            if let known {
                continuation.resume(returning: known)
            }
        }
    }
}
