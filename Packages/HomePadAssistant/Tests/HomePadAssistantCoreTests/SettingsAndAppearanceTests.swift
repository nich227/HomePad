import Foundation
import HomePadCore
import Testing
@testable import HomePadAssistantCore

@Suite struct SettingsTests {
    @Test func descriptors_whenListed_thenEveryKeyIsPrefixedAndInTheAssistantPane() {
        let names = AssistantSettings.descriptors.map(\.name)
        #expect(names == [
            "assistant.enabled", "assistant.listenOnOpen", "assistant.speakAnswers",
            "assistant.usePersonalContext", "assistant.autoDismissSeconds", "assistant.formatRecipes",
        ])
        #expect(Set(names).count == names.count)
        #expect(AssistantSettings.descriptors.allSatisfy { $0.pane == "Assistant" })
    }

    @Test func descriptors_whenAutoDismissChoice_thenDefaultIsAmongNumericOptions() throws {
        let descriptor = try #require(AssistantSettings.descriptors.first { $0.name == AssistantSettings.autoDismissSeconds.name })
        guard case .choice(let options) = descriptor.control else {
            Issue.record("not a choice")
            return
        }
        #expect(options.allSatisfy { Int($0.value) != nil })
        #expect(options.contains { $0.value == String(AssistantSettings.autoDismissSeconds.defaultValue) })
    }

    @Test func descriptors_whenTitlesAndFooters_thenNoDashesAndNoUseOfSirisName() {
        for descriptor in AssistantSettings.descriptors {
            let text = descriptor.title + (descriptor.footer ?? "")
            #expect(!text.contains("\u{2014}") && !text.contains("\u{2013}"))
            #expect(!text.contains("Siri"))
        }
    }

    @Test func descriptors_whenTidyUpRecipes_thenOnByDefaultAndSaysItStaysOnThisDeviceWithTheOriginalATapAway() throws {
        let descriptor = try #require(AssistantSettings.descriptors.first { $0.name == "assistant.formatRecipes" })
        #expect(descriptor.title == "Tidy Up Recipes")
        #expect(descriptor.control == .toggle)
        #expect(descriptor.defaultValue == .bool(true))
        let footer = try #require(descriptor.footer)
        #expect(footer.contains("on this device"))
        #expect(footer.contains("original recipe stays one tap away"))
        #expect(AssistantSettings.formatRecipes.defaultValue)
    }

    @Test func preferences_whenDefaults_thenMatchTheSettingKeys() {
        let preferences = AssistantPreferences()
        #expect(preferences.isEnabled)
        #expect(preferences.speaksAnswers)
        #expect(preferences.listensOnOpen)
        #expect(preferences.usesPersonalContext)
        #expect(preferences.autoDismissAfter == 30)
        #expect(preferences.formatsRecipes)
    }

    @Test func preferences_whenAutoDismissIsZero_thenNeverCloses() {
        #expect(AssistantPreferences(autoDismissSeconds: 0).autoDismissAfter == nil)
    }

    @MainActor
    @Test func preferences_whenReadFromSettings_thenReflectsWhatSettingsHolds() throws {
        let suite = "assistant-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = HomePadSettings(defaults: defaults)
        settings.register(AssistantSettings.descriptors)
        #expect(AssistantPreferences(settings: settings) == AssistantPreferences())

        defaults.set(false, forKey: AssistantSettings.enabled.name)
        defaults.set(false, forKey: AssistantSettings.speakAnswers.name)
        defaults.set(false, forKey: AssistantSettings.listenOnOpen.name)
        defaults.set(false, forKey: AssistantSettings.usePersonalContext.name)
        defaults.set(120, forKey: AssistantSettings.autoDismissSeconds.name)
        defaults.set(false, forKey: AssistantSettings.formatRecipes.name)
        let changed = AssistantPreferences(settings: settings)
        #expect(changed == AssistantPreferences(isEnabled: false, speaksAnswers: false, listensOnOpen: false, usesPersonalContext: false, autoDismissSeconds: 120, formatsRecipes: false))
        #expect(!changed.formatsRecipes)
        #expect(changed.autoDismissAfter == 120)
    }
}

@Suite struct AppearanceTests {
    @Test func palette_whenNight_thenOnlyPureBlackAndTheNightRed() {
        let palette = AssistantPalette.resolve(isNight: true)
        for color in palette.allColors {
            let isBlack = color.red == 0 && color.green == 0 && color.blue == 0
            let isNightRed = color.opacity(1) == AssistantColor.nightRed
            #expect(isBlack || isNightRed)
        }
        #expect(palette.cardFill == .black)
        #expect(palette.text == .nightRed)
        #expect(AssistantColor.nightRed == AssistantColor(red: 1, green: 45 / 255.0, blue: 32 / 255.0))
    }

    @Test func palette_whenDay_thenGlassCardAndSeamlessManyColoredGlow() {
        let palette = AssistantPalette.resolve(isNight: false)
        #expect(palette.cardFill == nil)
        #expect(palette.glow.first == palette.glow.last)
        #expect(Set(palette.glow.map { "\($0.red) \($0.green) \($0.blue)" }).count >= 4)
        #expect(palette.text == .white)
        #expect(palette.allColors.count == palette.glow.count + 6)
    }

    @Test func palette_whenNight_thenGlowLoopsWithoutSeam() {
        let glow = AssistantPalette.resolve(isNight: true).glow
        #expect(glow.first == glow.last)
    }

    @Test func glowFrame_whenReduceMotion_thenTheSameStillFrameAtAnyTime() {
        let first = EdgeGlow.frame(elapsed: 0, activity: .thinking, reduceMotion: true)
        let later = EdgeGlow.frame(elapsed: 17.3, activity: .listening, reduceMotion: true)
        #expect(first == later)
        #expect(first.rotationDegrees == 0)
        #expect(first.opacity > 0.5)
    }

    @Test func glowFrame_whenTimePasses_thenRotatesAndBreathes() {
        let start = EdgeGlow.frame(elapsed: 0, activity: .thinking, reduceMotion: false)
        #expect(start.rotationDegrees == 0)
        #expect(start.lineWidth == EdgeGlow.baseLineWidth)
        let half = EdgeGlow.frame(elapsed: EdgeGlow.lapDuration / 2, activity: .thinking, reduceMotion: false)
        #expect(abs(half.rotationDegrees - 180) < 0.001)
        let peak = EdgeGlow.frame(elapsed: 1.2, activity: .thinking, reduceMotion: false)
        #expect(abs(peak.lineWidth - (EdgeGlow.baseLineWidth + 4)) < 0.001)
        #expect(abs(peak.opacity - 1) < 0.001)
        #expect(abs(peak.blurRadius - (EdgeGlow.baseBlurRadius + 10)) < 0.001)
    }

    @Test func glowFrame_whenAnyActivity_thenRotationStaysInOneTurnAndNegativeTimeIsZero() {
        for activity in EdgeGlow.Activity.allCases {
            let frame = EdgeGlow.frame(elapsed: 1_000.25, activity: activity, reduceMotion: false)
            #expect((0..<360).contains(frame.rotationDegrees))
            #expect(EdgeGlow.frame(elapsed: -5, activity: activity, reduceMotion: false).rotationDegrees == 0)
        }
        #expect(EdgeGlow.Activity.listening.breathDuration < EdgeGlow.Activity.idle.breathDuration)
    }

    @Test func cardWidth_whenNarrowOrWide_thenFillsToMarginsUpToTheMaximum() {
        #expect(AssistantLayout.cardWidth(containerWidth: 544) == 512)
        #expect(AssistantLayout.cardWidth(containerWidth: 1_366) == 720)
        #expect(AssistantLayout.cardWidth(containerWidth: 20) == 0)
    }

    @Test func dismissesOnDrag_whenFarOrFast_thenTrue() {
        #expect(AssistantLayout.dismissesOnDrag(translation: 100, predictedEndTranslation: 100))
        #expect(AssistantLayout.dismissesOnDrag(translation: 30, predictedEndTranslation: 300))
        #expect(!AssistantLayout.dismissesOnDrag(translation: 30, predictedEndTranslation: 60))
        #expect(!AssistantLayout.dismissesOnDrag(translation: -200, predictedEndTranslation: -400))
    }
}

@Suite struct TextTests {
    @Test func singleLine_whenLineBreaksAndControlCharacters_thenFoldedToSpaces() {
        #expect(AssistantText.singleLine("  one\n\ntwo\tthree\u{0}four \r\n", limit: 100) == "one two three four")
        #expect(AssistantText.singleLine("", limit: 10) == "")
    }

    @Test func clip_whenTooLong_thenCutsAtAWordAndMarksIt() {
        #expect(AssistantText.clip("short", limit: 10) == "short")
        #expect(AssistantText.clip("alpha beta gamma delta", limit: 14) == "alpha beta...")
        #expect(AssistantText.clip("abcdefghijklmnop", limit: 8) == "abcde...")
        #expect(AssistantText.clip("abcdef", limit: 2) == "...")
    }

    @Test func duration_whenVariousLengths_thenTwoLargestUnits() {
        #expect(AssistantText.duration(0) == "0 seconds")
        #expect(AssistantText.duration(-4) == "0 seconds")
        #expect(AssistantText.duration(1) == "1 second")
        #expect(AssistantText.duration(600) == "10 minutes")
        #expect(AssistantText.duration(3_661) == "1 hour 1 minute")
        #expect(AssistantText.duration(125) == "2 minutes 5 seconds")
    }

    @Test func degrees_whenWholeOrHalf_thenNoTrailingZero() {
        #expect(AssistantText.degrees(21) == "21")
        #expect(AssistantText.degrees(21.5) == "21.5")
        #expect(AssistantText.degrees(69.8) == "70")
    }
}
