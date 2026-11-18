import Foundation
import HomePadCore
import HomePadMessagingCore
import Observation

/// The hub side of projection. It mirrors what connected companions project, decides what the
/// person in front of the hub may see, and sends their taps back to the companion.
///
/// Projected content is held in memory only and is dropped when its companion disconnects.
@MainActor
@Observable
public final class ProjectionClient {
    /// Companions connected right now, whether or not they project anything.
    public private(set) var connectedCompanions: [PeerDevice] = []

    private var state: ProjectionClientState
    @ObservationIgnored private let channel: any PeerChannel
    @ObservationIgnored private let session: HouseholdSession
    @ObservationIgnored private let settings: HomePadSettings
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let codec = ProjectionCodec()
    @ObservationIgnored private var peers: [UUID: PeerDevice] = [:]
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var outbox: AsyncStream<Outgoing>.Continuation?
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var lastResyncRequest: [UUID: Date] = [:]

    private struct Outgoing: Sendable {
        let data: Data
        let deviceID: UUID
    }

    public init(
        channel: any PeerChannel,
        session: HouseholdSession,
        settings: HomePadSettings,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.channel = channel
        self.session = session
        self.settings = settings
        self.now = now
        self.state = ProjectionClientState(session: UUID())
    }

    // MARK: Lifecycle

    /// Starts listening for companions. Safe to call more than once.
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        let (stream, continuation) = AsyncStream.makeStream(of: Outgoing.self)
        outbox = continuation
        let channel = channel
        // One task sends everything, so commands reach a companion in sequence order.
        Task {
            for await item in stream {
                try? await channel.send(item.data, on: PeerChannelName.projection, to: item.deviceID)
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
                await self?.refreshPeers()
                try? await Task.sleep(for: .seconds(2))
            }
        })
    }

    public func stop() {
        isRunning = false
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        outbox?.finish()
        outbox = nil
        state = ProjectionClientState(session: UUID())
        peers = [:]
        lastResyncRequest = [:]
        connectedCompanions = []
    }

    /// Re-reads the connected peers and drops content from companions that left. Runs on a
    /// timer; call it as well when the transport reports a change.
    public func refreshPeers() async {
        let connected = await channel.connectedPeers()
        peers = Dictionary(connected.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let companions = connected.filter { $0.role == .companion }
        if connectedCompanions != companions {
            connectedCompanions = companions
        }
        for deviceID in state.reconcile(connected: connected, now: now()) {
            send(.hello, to: deviceID)
        }
    }

    // MARK: What the viewer may see

    /// Who is in front of the hub, in the form the visibility policy takes.
    public var viewer: ViewerContext {
        ViewerContext(activeProfileID: session.activeProfile?.id, isPersonalContentUnlocked: session.isPersonalContentUnlocked)
    }

    /// Apps to list for the current viewer. Hidden apps are not in the list.
    public var entries: [ProjectedAppEntry] {
        state.entries(viewer: viewer)
    }

    public func entry(_ id: ProjectedAppEntryID) -> ProjectedAppEntry? {
        state.entry(id, viewer: viewer)
    }

    /// The screen at `depth` (1 is the root, `nil` is the top), or a redacted or loading state.
    public func content(for id: ProjectedAppEntryID, depth: Int? = nil) -> ProjectedContent {
        state.content(for: id, depth: depth, viewer: viewer)
    }

    public func navigationDepth(for id: ProjectedAppEntryID) -> Int {
        state.navigationDepth(for: id)
    }

    /// Set when a companion asked for one of its apps to be brought to the front.
    public var presentationRequest: ProjectionPresentationRequest? {
        state.presentationRequest
    }

    public func clearPresentationRequest() {
        state.clearPresentationRequest()
    }

    public var proximity: Proximity { session.proximity }

    // MARK: Context summaries

    /// Short text summaries of the active member's projected content: recent messages, coming
    /// events, open reminders, and what is playing. Empty unless personal content is unlocked and
    /// that member's iPhone is connected and projecting, the same rule `content(for:depth:)` follows.
    ///
    /// The result holds personal text. Keep it in memory and never log it.
    public func contextSummaries(limit: Int = 8, maxTextLength: Int = 140) -> [ProjectedContextSummary] {
        state.contextSummaries(viewer: viewer, limit: limit, maxTextLength: maxTextLength, now: now())
    }

    // MARK: Replies

    /// How a reply typed on the hub would be delivered for this conversation, as data the UI explains.
    public func replyRoute(for id: ProjectedAppEntryID, canReply: Bool, hubCanSendText: Bool) -> ReplyRoute {
        ReplyRouting.route(
            ReplyContext(
                conversationOwner: entry(id)?.ownerProfileID,
                companionDeviceID: state.connectedDeviceIDs.contains(id.deviceID) ? id.deviceID : nil,
                viewer: viewer,
                canReply: canReply,
                hubCanSendText: hubCanSendText,
                hubMessagesAccountOwner: ReplyRouting.hubAccountOwner(
                    named: settings[MessagingSettings.hubMessagesAccountOwner],
                    in: session.profiles
                )
            )
        )
    }

    // MARK: Commands to the companion

    public func launch(_ id: ProjectedAppEntryID) {
        send(.launch(appID: id.appID), to: id.deviceID)
    }

    public func perform(actionID: String, payload: [String: String] = [:], in id: ProjectedAppEntryID) {
        guard entry(id)?.decision.visibility == .visible else { return }
        send(.action(appID: id.appID, actionID: actionID, payload: payload), to: id.deviceID)
    }

    public func back(in id: ProjectedAppEntryID) {
        perform(actionID: ProjectionReservedAction.back, in: id)
    }

    /// Hands a reply to the companion. The companion's owner still has to confirm it there.
    public func sendReply(conversationID: String, text: String, in id: ProjectedAppEntryID) {
        guard entry(id)?.decision.visibility == .visible else { return }
        send(.reply(conversationID: conversationID, text: text), to: id.deviceID)
    }

    public func send(_ command: MediaCommand, in id: ProjectedAppEntryID) {
        guard entry(id)?.decision.visibility == .visible else { return }
        send(.mediaCommand(command), to: id.deviceID)
    }

    // MARK: Plumbing

    private func receive(_ envelope: PeerEnvelope) async {
        if peers[envelope.sender] == nil {
            await refreshPeers()
        }
        guard let device = peers[envelope.sender],
              let frame = try? codec.decodeHostFrame(envelope.payload)
        else { return }
        // A frame that fails any check is dropped whole; nothing from it is kept or logged.
        do {
            try state.apply(frame, from: device, now: now())
        } catch .staleSequence, .senderRoleNotAllowed {
            return
        } catch {
            // The mirror no longer matches the companion. Ask it to send everything again, but not
            // more often than the retry interval, so a companion that keeps failing cannot cause a loop.
            let last = lastResyncRequest[device.id] ?? .distantPast
            if now().timeIntervalSince(last) >= state.helloRetryInterval {
                lastResyncRequest[device.id] = now()
                send(.hello, to: device.id)
            }
        }
    }

    private func send(_ message: HubToHostMessage, to deviceID: UUID) {
        guard let outbox, let data = try? codec.encode(state.frame(for: message)) else { return }
        outbox.yield(Outgoing(data: data, deviceID: deviceID))
    }
}
