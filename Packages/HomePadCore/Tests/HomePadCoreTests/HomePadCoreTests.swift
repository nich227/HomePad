import Foundation
import Testing
@testable import HomePadCore

@MainActor
@Suite struct HouseholdSessionTests {
    private func makeSession(limit: Int? = nil, requiresCompanion: Bool = false, store: any ProfileStore = InMemoryProfileStore()) -> HouseholdSession {
        HouseholdSession(store: store, profileLimit: limit, requiresCompanionForPersonalContent: requiresCompanion)
    }

    @Test func addProfile_whenNameValid_thenPersistsAndCyclesTints() throws {
        let store = InMemoryProfileStore()
        let session = makeSession(store: store)
        for index in 0..<7 {
            try session.addProfile(name: " Member \(index) ")
        }
        #expect(session.profiles.map(\.name).first == "Member 0")
        #expect(session.profiles.map(\.tint) == [.green, .yellow, .orange, .red, .purple, .blue, .green])
        #expect(try store.load() == session.profiles)
    }

    @Test func addProfile_whenNameBlank_thenThrowsEmptyName() {
        let session = makeSession()
        #expect(throws: HouseholdError.emptyName) { try session.addProfile(name: "  \n") }
    }

    @Test func addProfile_whenLimitReached_thenThrows() throws {
        let session = makeSession(limit: 1)
        try session.addProfile(name: "A", tint: .red, symbolName: "star")
        #expect(session.profiles[0].tint == .red)
        #expect(throws: HouseholdError.profileLimitReached(1)) { try session.addProfile(name: "B") }
    }

    @Test func init_whenStoreHasProfiles_thenLoadsThem() {
        let existing = HouseholdProfile(name: "A", tint: .blue)
        let session = makeSession(store: InMemoryProfileStore(profiles: [existing]))
        #expect(session.profiles == [existing])
    }

    @Test func init_whenStoreFails_thenStartsEmpty() {
        let session = makeSession(store: FailingStore())
        #expect(session.profiles.isEmpty)
    }

    @Test func updateProfile_whenKnown_thenReplaces() throws {
        let session = makeSession()
        var profile = try session.addProfile(name: "A")
        profile.name = "B"
        try session.updateProfile(profile)
        #expect(session.profiles.first?.name == "B")
    }

    @Test func updateProfile_whenUnknown_thenThrows() {
        let session = makeSession()
        let stranger = HouseholdProfile(name: "X", tint: .red)
        #expect(throws: HouseholdError.unknownProfile(stranger.id)) { try session.updateProfile(stranger) }
    }

    @Test func removeProfile_whenActive_thenLocksAndForgetsCompanion() throws {
        let session = makeSession()
        let profile = try session.addProfile(name: "A")
        let other = try session.addProfile(name: "B")
        session.setCompanionPresent(true, for: profile.id)
        session.faceRecognized(profileID: profile.id, proximity: .near)
        try session.removeProfile(id: profile.id)
        #expect(session.activation == .none)
        #expect(session.profilesWithCompanionPresent.isEmpty)
        #expect(session.isGuest)

        try session.switchManually(to: other.id)
        let third = try session.addProfile(name: "C")
        try session.removeProfile(id: third.id)
        #expect(session.activation == .manual(other.id))
    }

    @Test func removeProfile_whenUnknown_thenThrows() {
        let session = makeSession()
        let id = UUID()
        #expect(throws: HouseholdError.unknownProfile(id)) { try session.removeProfile(id: id) }
    }

    @Test func faceRecognized_whenEnrolled_thenUnlocksPersonalContent() throws {
        let session = makeSession()
        let profile = try session.addProfile(name: "A")
        let now = Date(timeIntervalSince1970: 100)
        session.faceRecognized(profileID: profile.id, proximity: .near, at: now)
        #expect(session.activation == .face(profile.id, at: now))
        #expect(session.activeProfile == profile)
        #expect(session.isPersonalContentUnlocked)
        #expect(session.isSomeonePresent)
        #expect(session.proximity == .near)
        #expect(!session.isGuest)
    }

    @Test func faceRecognized_whenNotEnrolled_thenIgnored() {
        let session = makeSession()
        session.faceRecognized(profileID: UUID(), proximity: .near)
        #expect(session.activation == .none)
        #expect(!session.isSomeonePresent)
        #expect(!session.isPersonalContentUnlocked)
    }

    @Test func personalContent_whenCompanionRequired_thenNeedsCompanionPresent() throws {
        let session = makeSession(requiresCompanion: true)
        let profile = try session.addProfile(name: "A")
        session.faceRecognized(profileID: profile.id, proximity: .near)
        #expect(!session.isPersonalContentUnlocked)
        session.setCompanionPresent(true, for: profile.id)
        #expect(session.isPersonalContentUnlocked)
        session.setCompanionPresent(false, for: profile.id)
        #expect(!session.isPersonalContentUnlocked)
        session.setCompanionPresent(true, for: UUID())
        #expect(session.profilesWithCompanionPresent.isEmpty)
    }

    @Test func switchManually_whenKnown_thenPersonalizesWithoutPersonalContent() throws {
        let session = makeSession()
        let profile = try session.addProfile(name: "A")
        try session.switchManually(to: profile.id)
        #expect(session.activeProfile == profile)
        #expect(!session.isPersonalContentUnlocked)
        session.lock()
        #expect(session.isGuest)
    }

    @Test func switchManually_whenUnknown_thenThrows() {
        let session = makeSession()
        let id = UUID()
        #expect(throws: HouseholdError.unknownProfile(id)) { try session.switchManually(to: id) }
    }

    @Test func unknownFacePresent_whenFaceActive_thenLocks_whenManual_thenKeeps() throws {
        let session = makeSession()
        let profile = try session.addProfile(name: "A")
        session.faceRecognized(profileID: profile.id, proximity: .near)
        session.unknownFacePresent(proximity: .far)
        #expect(session.activation == .none)
        #expect(session.isSomeonePresent)
        #expect(session.proximity == .far)

        try session.switchManually(to: profile.id)
        session.unknownFacePresent(proximity: .near)
        #expect(session.activation == .manual(profile.id))
    }

    @Test func presenceLost_whenFaceActive_thenLocks_whenManual_thenKeeps() throws {
        let session = makeSession()
        let profile = try session.addProfile(name: "A")
        session.faceRecognized(profileID: profile.id, proximity: .near)
        session.presenceLost()
        #expect(session.activation == .none)
        #expect(!session.isSomeonePresent)
        #expect(session.proximity == .far)

        try session.switchManually(to: profile.id)
        session.presenceLost()
        #expect(session.activation == .manual(profile.id))
    }

    @Test func faceMatchedWithoutLiveness_whenEnrolled_thenPersonalizesButStaysLocked() throws {
        let session = makeSession()
        let profile = try session.addProfile(name: "A")
        session.faceMatchedWithoutLiveness(profileID: profile.id, proximity: .near)
        #expect(session.activation == .manual(profile.id))
        #expect(session.cameraMatchedProfileID == profile.id)
        #expect(session.canConfirmWithDeviceBiometrics)
        #expect(!session.isPersonalContentUnlocked)
        #expect(session.isSomeonePresent)
        #expect(session.proximity == .near)

        session.faceMatchedWithoutLiveness(profileID: UUID(), proximity: .far)
        #expect(session.cameraMatchedProfileID == profile.id)
        #expect(session.proximity == .near)
    }

    @Test func confirmWithDeviceBiometrics_whenCameraMatchWaiting_thenUnlocksUntilPersonLeaves() throws {
        let session = makeSession()
        let profile = try session.addProfile(name: "A")
        let now = Date(timeIntervalSince1970: 50)
        session.faceMatchedWithoutLiveness(profileID: profile.id, proximity: .near)
        #expect(session.confirmWithDeviceBiometrics(at: now))
        #expect(session.activation == .face(profile.id, at: now))
        #expect(session.isConfirmedByDeviceBiometrics)
        #expect(session.isPersonalContentUnlocked)
        #expect(!session.canConfirmWithDeviceBiometrics)

        // Later frames of the same unproven match must not lock it again.
        session.faceMatchedWithoutLiveness(profileID: profile.id, proximity: .far)
        #expect(session.activation == .face(profile.id, at: now))
        #expect(session.proximity == .far)

        session.presenceLost()
        #expect(session.activation == .none)
        #expect(session.cameraMatchedProfileID == nil)
        #expect(!session.isConfirmedByDeviceBiometrics)
        #expect(!session.isPersonalContentUnlocked)
    }

    @Test func confirmWithDeviceBiometrics_whenNoCameraMatch_thenRefused() throws {
        let session = makeSession()
        let profile = try session.addProfile(name: "A")
        #expect(!session.confirmWithDeviceBiometrics())

        try session.switchManually(to: profile.id)
        #expect(!session.confirmWithDeviceBiometrics())
        #expect(session.activation == .manual(profile.id))
        #expect(!session.isPersonalContentUnlocked)

        session.faceRecognized(profileID: profile.id, proximity: .near)
        #expect(!session.confirmWithDeviceBiometrics())
        #expect(!session.isConfirmedByDeviceBiometrics)
    }

    @Test func cameraMatch_whenAnotherMemberMatches_thenFirstMembersContentLocks() throws {
        let session = makeSession()
        let alice = try session.addProfile(name: "A")
        let bob = try session.addProfile(name: "B")
        session.faceMatchedWithoutLiveness(profileID: alice.id, proximity: .near)
        session.confirmWithDeviceBiometrics()
        session.faceMatchedWithoutLiveness(profileID: bob.id, proximity: .near)
        #expect(session.activation == .manual(bob.id))
        #expect(session.cameraMatchedProfileID == bob.id)
        #expect(!session.isConfirmedByDeviceBiometrics)
        #expect(!session.isPersonalContentUnlocked)
    }

    @Test func cameraMatch_whenUnknownFaceOrManualSwitchOrLock_thenCleared() throws {
        let session = makeSession()
        let alice = try session.addProfile(name: "A")
        let bob = try session.addProfile(name: "B")

        session.faceMatchedWithoutLiveness(profileID: alice.id, proximity: .near)
        session.unknownFacePresent(proximity: .near)
        #expect(session.activation == .none)
        #expect(session.cameraMatchedProfileID == nil)

        session.faceMatchedWithoutLiveness(profileID: alice.id, proximity: .near)
        try session.switchManually(to: bob.id)
        #expect(session.cameraMatchedProfileID == nil)
        #expect(!session.confirmWithDeviceBiometrics())
        session.presenceLost()
        #expect(session.activation == .manual(bob.id))

        session.faceMatchedWithoutLiveness(profileID: alice.id, proximity: .near)
        session.confirmWithDeviceBiometrics()
        session.lock()
        #expect(session.activation == .none)
        #expect(!session.isConfirmedByDeviceBiometrics)

        session.faceMatchedWithoutLiveness(profileID: alice.id, proximity: .near)
        session.confirmWithDeviceBiometrics()
        session.faceRecognized(profileID: alice.id, proximity: .near)
        #expect(session.cameraMatchedProfileID == nil)
        #expect(!session.isConfirmedByDeviceBiometrics)
        #expect(session.isPersonalContentUnlocked)

        session.faceMatchedWithoutLiveness(profileID: alice.id, proximity: .near)
        try session.removeProfile(id: alice.id)
        #expect(session.cameraMatchedProfileID == nil)
        #expect(session.activation == .none)
    }

    @Test func activationProfileID_coversEveryCase() {
        let id = UUID()
        #expect(ProfileActivation.none.profileID == nil)
        #expect(ProfileActivation.manual(id).profileID == id)
        #expect(ProfileActivation.face(id, at: Date()).profileID == id)
    }
}

private struct FailingStore: ProfileStore {
    struct Failure: Error {}
    func load() throws -> [HouseholdProfile] { throw Failure() }
    func save(_ profiles: [HouseholdProfile]) throws { throw Failure() }
}

@Suite struct ProfileStoreTests {
    @Test func fileStore_whenNoFile_thenEmpty_whenSaved_thenRoundTrips() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = FileProfileStore(url: url)
        #expect(try store.load().isEmpty)
        let profiles = [HouseholdProfile(name: "A", tint: .purple, createdAt: Date(timeIntervalSince1970: 1_000))]
        try store.save(profiles)
        #expect(try store.load() == profiles)
    }

    @Test func applicationSupport_createsDirectory() throws {
        let store = try FileProfileStore.applicationSupport()
        _ = try store.load()
    }

    @Test func rainbowTint_hasSixDistinctColorsInRange() {
        let colors = RainbowTint.allCases.map(\.rgb)
        #expect(colors.count == 6)
        #expect(Set(colors.map { "\($0.red),\($0.green),\($0.blue)" }).count == 6)
        #expect(colors.allSatisfy { (0...1).contains($0.red) && (0...1).contains($0.green) && (0...1).contains($0.blue) })
    }
}

@Suite struct PeerChannelTests {
    private struct Ping: Codable, Equatable, Sendable { let value: Int }

    private func makePair() -> (LoopbackPeerChannel, LoopbackPeerChannel) {
        LoopbackPeerChannel.pair(
            PeerDevice(id: UUID(), name: "Hub", role: .hub),
            PeerDevice(id: UUID(), name: "Phone", role: .companion, profileID: UUID())
        )
    }

    @Test func send_whenPaired_thenDeliversOnlyOnThatChannel() async throws {
        let (hub, phone) = makePair()
        var beam = hub.messages(on: PeerChannelName.beam).makeAsyncIterator()
        var typed = hub.decoded(Ping.self, on: PeerChannelName.projection).makeAsyncIterator()

        try await phone.send(Data([1]), on: PeerChannelName.beam, to: hub.localDevice.id)
        try await phone.send(Data("not json".utf8), on: PeerChannelName.projection, to: nil)
        try await phone.send(Ping(value: 7), on: PeerChannelName.projection)

        let envelope = await beam.next()
        #expect(envelope == PeerEnvelope(channel: PeerChannelName.beam, sender: phone.localDevice.id, payload: Data([1])))
        let ping = await typed.next()
        #expect(ping?.message == Ping(value: 7))
        #expect(ping?.sender == phone.localDevice.id)
        #expect(await hub.connectedPeers() == [phone.localDevice])
    }

    @Test func send_whenPeerUnknown_thenThrows() async {
        let (hub, _) = makePair()
        let stranger = UUID()
        await #expect(throws: PeerChannelError.unknownPeer(stranger)) {
            try await hub.send(Data(), on: PeerChannelName.presence, to: stranger)
        }
    }

    @Test func send_whenDisconnected_thenThrowsAndPeersEmpty() async {
        let (hub, phone) = makePair()
        hub.disconnect()
        await #expect(throws: PeerChannelError.notConnected) {
            try await phone.send(Data(), on: PeerChannelName.intercom, to: nil)
        }
        #expect(await hub.connectedPeers().isEmpty)
        hub.disconnect()
    }

    @Test func messages_whenStreamCancelled_thenUnsubscribes() async throws {
        let (hub, phone) = makePair()
        let consumer = Task {
            for await _ in hub.decoded(Ping.self, on: PeerChannelName.beam) {}
        }
        consumer.cancel()
        await consumer.value
        try await phone.send(Ping(value: 1), on: PeerChannelName.beam)
        try await phone.send(Ping(value: 1), on: "nobody-listening")
    }
}
