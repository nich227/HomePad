import HomePadAssistantCore
import SwiftUI

/// The Assistant, over whatever the hub is showing. Everything is see-through except the light
/// around the screen's edge and a card at the bottom that holds the conversation.
///
/// The overlay opens the engine when it appears and closes it when it goes away, when the
/// scene stops being active, and when the person taps outside the card, swipes it down, or
/// taps Close. `onDismiss` is called once the engine has closed, whatever closed it.
public struct AssistantOverlayView: View {
    private let engine: AssistantEngine
    private let isNight: Bool
    private let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.scenePhase) private var scenePhase
    @State private var draft = ""
    @State private var dragOffset: CGFloat = 0
    @FocusState private var isTyping: Bool

    public init(engine: AssistantEngine, isNight: Bool, onDismiss: @escaping () -> Void) {
        self.engine = engine
        self.isNight = isNight
        self.onDismiss = onDismiss
    }

    private var palette: AssistantPalette {
        AssistantPalette.resolve(isNight: isNight)
    }

    private var conversation: AssistantConversation {
        engine.conversation
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Color(palette.scrim)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { engine.dismiss() }
                    .accessibilityLabel(Text("Close Assistant"))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("assistant-scrim")
                EdgeGlowView(palette: palette, activity: conversation.glowActivity, reduceMotion: reduceMotion)
                card
                    .frame(width: AssistantLayout.cardWidth(containerWidth: proxy.size.width))
                    .padding(.bottom, AssistantLayout.cardMargin)
                    .offset(y: dragOffset)
                    .gesture(dragToDismiss)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .accessibilityAction(.escape) { engine.dismiss() }
        .accessibilityIdentifier("assistant-overlay")
        .onAppear {
            engine.open()
            if !conversation.isOpen {
                onDismiss()
            }
        }
        .onChange(of: conversation.isOpen) { _, isOpen in
            if !isOpen {
                onDismiss()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // The microphone never stays on behind another app.
            if phase != .active {
                engine.dismiss()
            }
        }
        .onChange(of: draft) {
            engine.noteInteraction()
        }
        .onDisappear { engine.dismiss() }
    }

    private var dragToDismiss: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                dragOffset = max(0, value.translation.height)
                engine.noteInteraction()
            }
            .onEnded { value in
                if AssistantLayout.dismissesOnDrag(
                    translation: value.translation.height,
                    predictedEndTranslation: value.predictedEndTranslation.height
                ) {
                    engine.dismiss()
                } else {
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.3)) {
                        dragOffset = 0
                    }
                }
            }
    }

    // MARK: Card

    private var card: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            transcript
            if let exchange = conversation.exchange, conversation.phase == .followUps {
                if !exchange.snippets.isEmpty {
                    snippets(exchange.snippets)
                }
                if !exchange.followUps.isEmpty {
                    chips(exchange.followUps)
                }
            }
            inputRow
        }
        .padding(22)
        .foregroundStyle(Color(palette.text))
        .modifier(CardBackground(palette: palette, reduceTransparency: reduceTransparency))
        .contentShape(RoundedRectangle(cornerRadius: CardBackground.cornerRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("assistant-card")
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color(palette.accent))
                .accessibilityHidden(true)
            Text("Assistant")
                .font(.title3.weight(.semibold))
            Spacer()
            Button {
                engine.dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(palette.secondaryText))
            .accessibilityLabel(Text("Close"))
            .accessibilityIdentifier("assistant-close")
        }
    }

    @ViewBuilder private var transcript: some View {
        switch conversation.phase {
        case .idle:
            Text("Ask about the weather, timers, or your home.")
                .font(.title2)
                .foregroundStyle(Color(palette.secondaryText))
        case .listening:
            HStack(spacing: 14) {
                ListeningLevels(color: Color(palette.accent), isAnimating: !reduceMotion)
                if conversation.heard.isEmpty {
                    Text("Listening")
                        .font(.title2)
                        .foregroundStyle(Color(palette.secondaryText))
                } else {
                    Text(conversation.heard)
                        .font(.title2.weight(.medium))
                }
            }
            .accessibilityElement(children: .combine)
        case .thinking, .answering, .followUps:
            exchangeText
        case .failed(let failure):
            VStack(alignment: .leading, spacing: 8) {
                if let request = conversation.exchange?.request {
                    requestText(request)
                }
                Text(failure.message)
                    .font(.title2)
                    .accessibilityIdentifier("assistant-failure")
            }
        }
    }

    @ViewBuilder private var exchangeText: some View {
        if let exchange = conversation.exchange {
            VStack(alignment: .leading, spacing: 8) {
                requestText(exchange.request)
                if exchange.answer.isEmpty {
                    ProgressView()
                        .tint(Color(palette.accent))
                        .accessibilityLabel(Text("Thinking"))
                } else {
                    Text(exchange.answer)
                        .font(.title.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("assistant-answer")
                }
            }
        }
    }

    private func requestText(_ request: String) -> some View {
        Text(request)
            .font(.title3)
            .foregroundStyle(Color(palette.secondaryText))
            .lineLimit(2)
    }

    private func snippets(_ items: [AssistantContextItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items) { item in
                HStack(spacing: 12) {
                    Image(systemName: item.kind.symbolName)
                        .font(.headline)
                        .foregroundStyle(Color(palette.accent))
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.headline)
                        if !item.detail.isEmpty {
                            Text(item.detail)
                                .font(.subheadline)
                                .foregroundStyle(Color(palette.secondaryText))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(chipShape.fill(Color(palette.chipFill)))
                .overlay(chipShape.stroke(Color(palette.cardStroke), lineWidth: isNight ? 1 : 0))
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var chipShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
    }

    private func chips(_ followUps: [AssistantFollowUp]) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(followUps, id: \.self) { followUp in
                    Button {
                        engine.submit(followUp.title)
                    } label: {
                        Text(followUp.title)
                            .font(.headline)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 44)
                            .background(Capsule().fill(Color(palette.chipFill)))
                            .overlay(Capsule().stroke(Color(palette.cardStroke), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("assistant-follow-ups")
    }

    private var isBusy: Bool {
        conversation.phase == .thinking || conversation.phase == .answering
    }

    private var inputRow: some View {
        HStack(spacing: 10) {
            TextField("Type a request", text: $draft)
                .font(.title3)
                .focused($isTyping)
                .submitLabel(.send)
                .onSubmit(send)
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                .background(Capsule().fill(Color(palette.chipFill)))
                .overlay(Capsule().stroke(Color(palette.cardStroke), lineWidth: 1))
                .tint(Color(palette.accent))
                .accessibilityIdentifier("assistant-field")
            if isBusy {
                roundButton(symbol: "stop.fill", label: "Stop", identifier: "assistant-stop") {
                    engine.cancel()
                }
            } else if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                roundButton(symbol: "arrow.up", label: "Send", identifier: "assistant-send", action: send)
            } else if conversation.phase == .listening {
                roundButton(symbol: "waveform", label: "Stop listening", identifier: "assistant-microphone") {
                    engine.toggleListening()
                }
            } else {
                roundButton(symbol: "mic.fill", label: "Start listening", identifier: "assistant-microphone") {
                    isTyping = false
                    engine.toggleListening()
                }
            }
        }
    }

    private func roundButton(symbol: String, label: LocalizedStringKey, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .frame(width: 48, height: 48)
                .foregroundStyle(isNight ? Color(palette.text) : Color.white)
                .background(Circle().fill(isNight ? Color.black : Color(palette.accent)))
                .overlay(Circle().stroke(Color(palette.cardStroke), lineWidth: isNight ? 1 : 0))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .accessibilityIdentifier(identifier)
    }

    private func send() {
        let text = draft
        draft = ""
        engine.submit(text)
    }
}

/// Liquid Glass by day. Solid black with a red outline in Night Mode, and a solid fill when
/// Reduce Transparency is on.
private struct CardBackground: ViewModifier {
    static let cornerRadius: CGFloat = 34

    let palette: AssistantPalette
    let reduceTransparency: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        if let fill = palette.cardFill {
            content
                .background(shape.fill(Color(fill)))
                .overlay(shape.stroke(Color(palette.cardStroke), lineWidth: 1.5))
        } else if reduceTransparency {
            content
                .background(shape.fill(Color(white: 0.14)))
                .overlay(shape.stroke(Color(palette.cardStroke), lineWidth: 1))
        } else {
            content.glassEffect(.regular, in: shape)
        }
    }
}

/// Five bars that rise and fall while the microphone is open.
private struct ListeningLevels: View {
    let color: Color
    let isAnimating: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isAnimating)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { index in
                    let level = isAnimating ? 0.35 + 0.65 * abs(sin(time * 4 + Double(index) * 0.9)) : 0.6
                    Capsule()
                        .fill(color)
                        .frame(width: 5, height: 30 * level)
                }
            }
            .frame(height: 30)
        }
        .accessibilityHidden(true)
    }
}
