import Foundation
import HomePadCore
import Testing
@testable import HomePadUICore

@Suite struct TallDigitsTests {
    @Test func strokes_whenAnyDigit_thenStayInsideTheBox() {
        for digit in 0...9 {
            let strokes = TallDigits.strokes(for: digit, aspect: 7)
            #expect(!strokes.isEmpty, "\(digit)")
            for point in strokes.flatMap(\.points) {
                #expect(point.x >= -1e-9 && point.x <= 1 + 1e-9, "\(digit) x \(point.x)")
                #expect(point.y >= -1e-9 && point.y <= 7 + 1e-9, "\(digit) y \(point.y)")
            }
        }
    }

    @Test func strokes_whenDigitHasACounter_thenThatLoopIsClosed() {
        func closedCount(_ digit: Int) -> Int { TallDigits.strokes(for: digit).filter { $0.isClosed }.count }
        #expect(closedCount(0) == 1)
        #expect(closedCount(8) == 2)
        #expect(closedCount(9) == 1)
        #expect([1, 2, 3, 4, 5, 6, 7].allSatisfy { closedCount($0) == 0 })
        #expect(TallDigits.strokes(for: 4).count == 2)
        #expect(TallDigits.strokes(for: 9).count == 2)
        #expect(TallDigits.strokes(for: 1).first?.points.count == 3)
    }

    @Test func strokes_whenZero_thenReachesAllFourEdges() {
        let points = TallDigits.strokes(for: 0, aspect: 6)[0].points
        #expect(abs((points.map(\.x).min() ?? 1) - 0) < 1e-9)
        #expect(abs((points.map(\.x).max() ?? 0) - 1) < 1e-9)
        #expect(abs((points.map(\.y).min() ?? 1) - 0) < 1e-9)
        #expect(abs((points.map(\.y).max() ?? 0) - 6) < 1e-9)
    }

    @Test func strokes_whenNotADigitOrAspectTooSquat_thenEmptyOrClamped() {
        #expect(TallDigits.strokes(for: 10).isEmpty)
        #expect(TallDigits.strokes(for: -1).isEmpty)
        let squat = TallDigits.strokes(for: 7, aspect: 1)
        #expect(squat.first?.points.last?.y == 3)
    }
}

@Suite struct SlotTextScaleTests {
    @Test func step_whenCanvasGrows_thenTextStepsUp() {
        #expect(SlotTextScale.step(forCanvasSide: 300) == 0)
        #expect(SlotTextScale.step(forCanvasSide: 500) == 0)
        #expect(SlotTextScale.step(forCanvasSide: 744) == 3)
        #expect(SlotTextScale.step(forCanvasSide: 1032) == 5)
        #expect(SlotTextScale.step(forCanvasSide: 5000) == SlotTextScale.bodySizes.count - 1)
    }
}

@Suite struct HubTestHooksTests {
    @Test func hooks_whenEnvironmentIsEmpty_thenEverythingIsOff() {
        let hooks = HubTestHooks(environment: ["PATH": "/usr/bin"])
        #expect(hooks == HubTestHooks.none)
        #expect(!hooks.isEphemeral && !hooks.usesSampleData && !hooks.forcesNight && !hooks.skipsWelcome && !hooks.offersDeviceUnlock)
        #expect(hooks.audience == nil && hooks.proximity == nil && hooks.canvas == nil)
    }

    @Test func hooks_whenVariablesSet_thenParsed() {
        let hooks = HubTestHooks(environment: [
            "HOMEPAD_UITEST_SAMPLE": "1",
            "HOMEPAD_UITEST_AUDIENCE": "recognized",
            "HOMEPAD_UITEST_PROXIMITY": "near",
            "HOMEPAD_UITEST_CANVAS": "fill",
            "HOMEPAD_UITEST_NIGHT": "1",
            "HOMEPAD_UITEST_SKIP_WELCOME": "1",
            "HOMEPAD_UITEST_DEVICE_UNLOCK": "1",
        ])
        #expect(hooks.offersDeviceUnlock)
        #expect(hooks.usesSampleData && hooks.isEphemeral)
        #expect(hooks.audience == .recognized)
        #expect(hooks.proximity == .near)
        #expect(hooks.canvas == .fill)
        #expect(hooks.forcesNight && hooks.skipsWelcome)
    }

    @Test func hooks_whenValuesAreUnknown_thenIgnored() {
        let hooks = HubTestHooks(environment: [
            "HOMEPAD_UITEST_EPHEMERAL": "1",
            "HOMEPAD_UITEST_SAMPLE": "yes",
            "HOMEPAD_UITEST_AUDIENCE": "admin",
            "HOMEPAD_UITEST_PROXIMITY": "orbit",
            "HOMEPAD_UITEST_CANVAS": "round",
        ])
        #expect(hooks.isEphemeral && !hooks.usesSampleData)
        #expect(hooks.audience == nil && hooks.proximity == nil && hooks.canvas == nil)
    }
}
