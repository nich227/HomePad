import Foundation
import Testing
@testable import HomePadAnimationsCore

@Suite struct HomePadAnimationTests {
    @Test(arguments: HomePadAnimation.allCases)
    func resourceURL_whenBundled_thenPointsAtNamedJSONFile(animation: HomePadAnimation) throws {
        let url = try #require(animation.resourceURL)
        #expect(url.lastPathComponent == animation.rawValue + ".json")
    }

    @Test(arguments: HomePadAnimation.allCases)
    func data_whenBundled_thenIsNotEmpty(animation: HomePadAnimation) throws {
        #expect(try animation.data().count > 1000)
    }

    @Test func resourceURL_whenNameUnknown_thenIsNil() {
        #expect(HomePadAnimation.resourceURL(named: "no-such-animation") == nil)
    }

    @Test func data_whenURLMissing_thenThrowsMissingResource() {
        #expect(throws: HomePadAnimationError.missingResource("ghost")) {
            try HomePadAnimation.data(at: nil, named: "ghost")
        }
    }

    @Test func data_whenFileUnreadable_thenThrowsUnreadableResource() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        #expect(throws: HomePadAnimationError.unreadableResource("ghost")) {
            try HomePadAnimation.data(at: url, named: "ghost")
        }
    }

    @Test func allCases_whenListed_thenHaveUniqueFileNames() {
        let names = HomePadAnimation.allCases.map(\.rawValue)
        #expect(Set(names).count == names.count)
        #expect(names.count == 11)
    }

    @Test func loops_whenPlayOnceAnimation_thenIsFalse() {
        let once = HomePadAnimation.allCases.filter { !$0.loops }
        #expect(once == [.success, .beamIncoming, .hello, .locked])
    }

    @Test func supportsTint_whenHello_thenIsFalse() {
        let fixed = HomePadAnimation.allCases.filter { !$0.supportsTint }
        #expect(fixed == [.hello])
    }

    @Test(arguments: HomePadAnimation.allCases)
    func duration_whenRead_thenIsFrameCountOverFrameRate(animation: HomePadAnimation) {
        #expect(animation.duration == Double(animation.frameCount) / 60)
        #expect(animation.duration >= 1.5)
        #expect(animation.duration <= 3.5)
    }

    @Test func keypaths_whenRead_thenTargetNamedStyleColors() {
        #expect(HomePadAnimationKeypath.tintColor == "**.\(HomePadAnimationKeypath.tintName).Color")
        #expect(HomePadAnimationKeypath.inkColor == "**.\(HomePadAnimationKeypath.inkName).Color")
        #expect(HomePadAnimationKeypath.tintName != HomePadAnimationKeypath.inkName)
    }
}
