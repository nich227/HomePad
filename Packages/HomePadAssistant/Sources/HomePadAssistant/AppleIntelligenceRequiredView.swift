import HomePadAssistantCore
import SwiftUI
import UIKit

/// The screen shown in place of the app while Apple Intelligence is not available. It says in
/// a sentence or two what is needed, in type large enough to read from across a room.
///
/// The button opens HomePad's page in the Settings app, which is the only place in Settings an
/// app may open. The text names the pane to go to from there.
public struct AppleIntelligenceRequiredView: View {
    private let gate: AppleIntelligenceGate

    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var textScale = 1.0

    public init(gate: AppleIntelligenceGate) {
        self.gate = gate
    }

    public var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let content = Content(gate.decision)
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: side * 0.035) {
                    Image(systemName: content.symbol)
                        .font(.system(size: side * 0.11, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                        .accessibilityHidden(true)
                    Text(content.title)
                        .font(.system(size: max(28, side * 0.06) * textScale, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                    Text(content.message)
                        .font(.system(size: max(19, side * 0.034) * textScale, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                    if content.isWaiting {
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white)
                            .accessibilityLabel(Text("Getting ready"))
                    }
                    if content.offersSettings {
                        Button(action: openSettings) {
                            Text("Open Settings")
                                .font(.system(size: max(19, side * 0.034) * textScale, weight: .semibold))
                                .padding(.horizontal, side * 0.05)
                                .frame(minHeight: max(52, side * 0.08))
                        }
                        .buttonStyle(.glassProminent)
                        .accessibilityIdentifier("apple-intelligence-open-settings")
                    }
                }
                .foregroundStyle(.white)
                .padding(side * 0.06)
                .frame(maxWidth: min(proxy.size.width * 0.86, 820))
                .modifier(PanelBackground(reduceTransparency: reduceTransparency))
                .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .preferredColorScheme(.dark)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: gate.decision)
        .accessibilityIdentifier("apple-intelligence-required")
        .onAppear { gate.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                gate.refresh()
            }
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }

    private struct Content {
        let symbol: String
        let title: LocalizedStringKey
        let message: LocalizedStringKey
        var offersSettings = true
        var isWaiting = false

        init(_ decision: AssistantGateDecision) {
            switch decision {
            case .blocked(.needsAppleIntelligence):
                symbol = "sparkles"
                title = "Turn On Apple Intelligence"
                message = "HomePad needs Apple Intelligence. Open Settings, choose Apple Intelligence & Siri, and turn on Apple Intelligence."
            case .blocked(.deviceNotEligible):
                symbol = "exclamationmark.triangle"
                title = "This Device Is Not Supported"
                message = "HomePad needs Apple Intelligence, and this device cannot run it."
                offersSettings = false
            case .gettingReady, .run:
                symbol = "sparkles"
                title = "Getting Ready"
                message = "Apple Intelligence is preparing. HomePad opens by itself when it is done."
                offersSettings = false
                isWaiting = true
            case .blocked(.stillPreparing):
                symbol = "arrow.down.circle"
                title = "Still Getting Ready"
                message = "Apple Intelligence has not finished downloading. Keep this device on power and Wi-Fi. If nothing changes, check Apple Intelligence & Siri in Settings."
                isWaiting = true
            case .blocked(.unknown):
                symbol = "sparkles"
                title = "Apple Intelligence Is Not Available"
                message = "HomePad needs Apple Intelligence. Check Apple Intelligence & Siri in Settings."
            }
        }
    }
}

private struct PanelBackground: ViewModifier {
    let reduceTransparency: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 44, style: .continuous)
        if reduceTransparency {
            content
                .background(shape.fill(Color(white: 0.14)))
                .overlay(shape.stroke(Color.white.opacity(0.2), lineWidth: 1))
        } else {
            content.glassEffect(.regular, in: shape)
        }
    }
}
