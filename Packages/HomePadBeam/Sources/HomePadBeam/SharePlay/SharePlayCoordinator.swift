import Combine
import Foundation
import GroupActivities
import HomePadBeamCore
import HomePadCore
import Observation
import os

public enum SharePlayStartResult: Equatable, Sendable {
    /// The activity started in the current call or nearby session.
    case activated
    /// Nobody to share with yet. Present `GroupActivitySharingController` to pick people.
    case needsInvitation
    case cancelled
    /// SharePlay is turned off in Settings.
    case disabled
    case failed
}

/// Joins browse-together sessions and keeps this device's page in step with everyone else's.
@MainActor
@Observable
public final class SharePlayCoordinator {
    public private(set) var isActive = false
    /// The page everyone in the session is on.
    public private(set) var currentPage: ValidatedURL?
    public private(set) var participantCount = 0
    /// Whether the device is in a call or nearby session that can start SharePlay right away.
    public private(set) var isEligibleForGroupSession = false

    /// Whether this device may show the system sheet that invites people to a session. False on
    /// a hub, where a session can only start inside a call that is already under way.
    public private(set) var allowsInvitations = true

    /// What the local browser should do when someone else navigates, scrolls, or closes the page.
    @ObservationIgnored public var onAction: ((SharedBrowsingAction) -> Void)?

    @ObservationIgnored private let settings: HomePadSettings
    @ObservationIgnored private let log = Logger(subsystem: HomePadIdentifiers.bundlePrefix, category: "beam.shareplay")
    @ObservationIgnored private let stateObserver = GroupStateObserver()
    @ObservationIgnored private var state = SharedBrowsingState()
    @ObservationIgnored private var session: GroupSession<BeamTogetherActivity>?
    @ObservationIgnored private var messenger: GroupSessionMessenger?
    @ObservationIgnored private var knownParticipants: Set<Participant> = []
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private var sessionTasks: [Task<Void, Never>] = []
    @ObservationIgnored private var eligibility: AnyCancellable?
    @ObservationIgnored private var subscriptions: Set<AnyCancellable> = []

    public init(settings: HomePadSettings) {
        self.settings = settings
    }

    private var preferences: BeamPreferences { BeamPreferences.read(from: settings) }
    public var isEnabled: Bool { preferences.sharePlayEnabled }

    /// On the hub, shows the session's page in the browser of the person in front of it and
    /// closes that page when the session's page is closed. The hub leaves the session when that
    /// person signs out, so the next person is not shown what the session browses. The hub also
    /// stops offering to invite people, because that hands a link to another app.
    public func attach(to receiver: BeamReceiver) {
        allowsInvitations = false
        onAction = { [weak receiver] action in
            switch action {
            case .load(let url, let title): receiver?.open(sharePlay: url, title: title)
            case .close: receiver?.closeSharedPage()
            case .scroll: break
            }
        }
        receiver.onSignOut = { [weak self] _ in
            guard let self, self.isActive else { return }
            self.leave()
        }
    }

    /// Starts watching for sessions. Call once at launch on both hub and companion.
    public func start() {
        guard observation == nil else { return }
        observeEligibility()
        observation = Task { [weak self] in
            for await session in BeamTogetherActivity.sessions() {
                self?.configure(session)
            }
        }
    }

    /// Offers the page to the people in the current call or nearby session.
    public func startSharing(_ url: ValidatedURL, title: String?) async -> SharePlayStartResult {
        guard isEnabled else { return .disabled }
        let activity = BeamTogetherActivity(url: url, title: title)
        switch await activity.prepareForActivation() {
        case .activationPreferred:
            do {
                return try await activity.activate() ? .activated : .failed
            } catch {
                log.error("SharePlay activation failed")
                return .failed
            }
        case .activationDisabled:
            return .needsInvitation
        case .cancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    /// Tells the session the local browser moved to a new page.
    public func localDidNavigate(to url: URL, title: String?) {
        guard let session, let messenger else { return }
        let local = session.localParticipant.id.uuidString
        guard let message = state.localNavigation(to: url.absoluteString, title: title, localParticipant: local) else { return }
        currentPage = state.current
        send(message, with: messenger, to: .all)
    }

    public func localDidScroll(toFraction fraction: Double) {
        guard let messenger, let message = state.scrollMessage(fraction: fraction) else { return }
        send(message, with: messenger, to: .all)
    }

    /// Leaves the session. Others keep browsing.
    public func leave() {
        session?.leave()
        tearDown()
    }

    /// Ends the session for everyone.
    public func end() {
        if let messenger {
            send(.close, with: messenger, to: .all)
        }
        session?.end()
        tearDown()
    }

    private func configure(_ session: GroupSession<BeamTogetherActivity>) {
        guard isEnabled else {
            session.leave()
            return
        }
        tearDown()
        let messenger = GroupSessionMessenger(session: session, deliveryMode: .reliable)
        self.session = session
        self.messenger = messenger
        state = SharedBrowsingState(policy: preferences.urlPolicy)
        knownParticipants = []
        isActive = true

        let first = SharePlayMessage.navigate(urlText: session.activity.url.absoluteString, title: session.activity.title, sequence: 0)
        apply(first, from: "activity")

        sessionTasks.append(Task { [weak self] in
            for await (message, context) in messenger.messages(of: SharePlayMessage.self) {
                self?.apply(message, from: context.source.id.uuidString)
            }
        })
        session.$activeParticipants
            .receive(on: RunLoop.main)
            .sink { [weak self] participants in
                MainActor.assumeIsolated { self?.participantsChanged(participants) }
            }
            .store(in: &subscriptions)
        session.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] sessionState in
                guard case .invalidated = sessionState else { return }
                MainActor.assumeIsolated { self?.tearDown() }
            }
            .store(in: &subscriptions)
        session.join()
    }

    /// Someone who joined late has no page yet, so they are sent the current one.
    private func participantsChanged(_ participants: Set<Participant>) {
        let joined = participants.subtracting(knownParticipants)
        knownParticipants = participants
        participantCount = participants.count
        guard let messenger, let session, let catchUp = state.catchUpMessage else { return }
        let others = joined.filter { $0 != session.localParticipant }
        guard !others.isEmpty else { return }
        send(catchUp, with: messenger, to: .only(others))
    }

    private func apply(_ message: SharePlayMessage, from participant: String) {
        guard let action = state.receive(message, from: participant) else { return }
        currentPage = state.current
        onAction?(action)
        if action == .close {
            session?.leave()
            tearDown()
        }
    }

    private func send(_ message: SharePlayMessage, with messenger: GroupSessionMessenger, to participants: Participants) {
        Task { [log] in
            do {
                try await messenger.send(message, to: participants)
            } catch {
                log.notice("A SharePlay message was not delivered")
            }
        }
    }

    private func tearDown() {
        sessionTasks.forEach { $0.cancel() }
        sessionTasks = []
        subscriptions = []
        session = nil
        messenger = nil
        knownParticipants = []
        participantCount = 0
        currentPage = nil
        isActive = false
    }

    private func observeEligibility() {
        eligibility = stateObserver.$isEligibleForGroupSession
            .receive(on: RunLoop.main)
            .sink { [weak self] eligible in
                MainActor.assumeIsolated { self?.isEligibleForGroupSession = eligible }
            }
    }
}
