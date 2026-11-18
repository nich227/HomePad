import Foundation
import Lottie
import Testing
@testable import HomePadAnimationsCore

/// Checks the generated JSON files: what Lottie decodes, and the structure the app relies on.
@Suite struct AnimationFileTests {
    @Test(arguments: HomePadAnimation.allCases)
    func decode_whenBundled_thenHasSpecifiedTimingAndCanvas(animation: HomePadAnimation) throws {
        let decoded = try LottieAnimation.from(data: animation.data())
        #expect(decoded.framerate == Double(HomePadAnimation.frameRate))
        #expect(Int(decoded.startFrame) == 0)
        #expect(Int(decoded.endFrame) == animation.frameCount)
        #expect(abs(decoded.duration - animation.duration) < 0.0001)
        #expect(decoded.bounds == CGRect(x: 0, y: 0, width: 400, height: 400))
        #expect(HomePadAnimation.canvasSize == 400)
    }

    @Test(arguments: HomePadAnimation.allCases)
    func layers_whenRead_thenAreShapeLayersSpanningTheWholeAnimation(animation: HomePadAnimation) throws {
        let document = try AnimationDocument(animation)
        #expect(!document.layers.isEmpty)
        #expect(document.root["nm"] as? String == animation.rawValue)
        for layer in document.layers {
            #expect(layer["ty"] as? Int == 4)
            #expect(layer["ip"] as? Double == 0)
            #expect(layer["op"] as? Double == Double(animation.frameCount))
            #expect(!((layer["shapes"] as? [Any]) ?? []).isEmpty)
        }
    }

    /// The Core Animation engine draws groups, basic shapes, strokes, fills, and stroke trims.
    /// Effects, masks, mattes, time remapping, and parenting are kept out of the files.
    @Test(arguments: HomePadAnimation.allCases)
    func features_whenRead_thenStayInsideTheCoreAnimationSubset(animation: HomePadAnimation) throws {
        let document = try AnimationDocument(animation)
        #expect(document.shapeTypes.isSubset(of: ["gr", "el", "rc", "sh", "st", "fl", "tm", "tr"]))
        #expect(document.keys.isDisjoint(with: ["ef", "masksProperties", "hasMask", "tt", "td", "tm", "parent"]))
        #expect(!document.hasExpressions)
        #expect(document.trimmedFills.isEmpty)
        #expect(document.pathCounts.values.allSatisfy { $0 == 1 })
        #expect((document.root["assets"] as? [Any])?.isEmpty == true)
    }

    @Test(arguments: HomePadAnimation.allCases)
    func keyframes_whenRead_thenAreOrderedInsideTheAnimation(animation: HomePadAnimation) throws {
        let document = try AnimationDocument(animation)
        #expect(!document.animatedProperties.isEmpty)
        for property in document.animatedProperties {
            #expect(property.times.count >= 2, "\(property.path)")
            #expect(property.times == property.times.sorted(), "\(property.path)")
            #expect(Set(property.times).count == property.times.count, "\(property.path)")
            #expect((property.times.first ?? -1) >= 0, "\(property.path)")
            #expect((property.times.last ?? .infinity) <= Double(animation.frameCount), "\(property.path)")
        }
    }

    @Test(arguments: HomePadAnimation.allCases.filter(\.loops))
    func keyframes_whenAnimationLoops_thenEveryPropertyEndsWhereItStarts(animation: HomePadAnimation) throws {
        let document = try AnimationDocument(animation)
        for property in document.animatedProperties {
            #expect(property.first == property.last, "\(property.path)")
        }
    }

    @Test(arguments: HomePadAnimation.allCases.filter { !$0.loops })
    func keyframes_whenAnimationPlaysOnce_thenSomePropertyEndsSomewhereNew(animation: HomePadAnimation) throws {
        let document = try AnimationDocument(animation)
        #expect(document.animatedProperties.contains { $0.first != $0.last })
    }

    @Test(arguments: HomePadAnimation.allCases)
    func styles_whenRead_thenUseTheRoleNames(animation: HomePadAnimation) throws {
        let document = try AnimationDocument(animation)
        let names = Set(document.styles.map(\.name))
        #expect(names.isSubset(of: [HomePadAnimationKeypath.tintName, HomePadAnimationKeypath.inkName, "Stripe"]))
        for style in document.styles where style.name != "Stripe" {
            #expect(style.color == [1, 1, 1, 1], "\(style.keypath)")
        }
    }

    @Test(arguments: HomePadAnimation.allCases)
    func styles_whenAnimationSupportsTint_thenHasTintParts(animation: HomePadAnimation) throws {
        let document = try AnimationDocument(animation)
        let tinted = document.styles.filter { $0.name == HomePadAnimationKeypath.tintName }
        #expect(tinted.isEmpty == !animation.supportsTint)
    }

    @Test func styles_whenHello_thenStripesAreTheSixRainbowColorsTopToBottom() throws {
        let document = try AnimationDocument(.hello)
        let stripes = document.styles.filter { $0.name == "Stripe" }
        let hex = stripes.map { style in
            style.color.prefix(3).map { String(format: "%02X", Int(($0 * 255).rounded())) }.joined()
        }
        #expect(hex == ["61BB46", "FDB827", "F5821F", "E03A3E", "963D97", "009DDC"])
        #expect(stripes.map(\.keypath) == (1...6).map { "Stripes.Stripe \($0).Stripe" })
    }
}
