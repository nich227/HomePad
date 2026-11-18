import HomePadAssistantCore
import SwiftUI

/// The light that traces the screen's border while the Assistant is open. It is drawn on the
/// shape of the display itself, so it follows the rounded corners, and it ignores the safe
/// area, so it sits on the true edge. With Reduce Motion it holds one still frame.
struct EdgeGlowView: View {
    let palette: AssistantPalette
    let activity: EdgeGlow.Activity
    let reduceMotion: Bool
    @State private var start = Date()

    var body: some View {
        Group {
            if reduceMotion {
                layers(EdgeGlow.frame(elapsed: 0, activity: activity, reduceMotion: true))
            } else {
                TimelineView(.animation) { timeline in
                    layers(EdgeGlow.frame(
                        elapsed: timeline.date.timeIntervalSince(start),
                        activity: activity,
                        reduceMotion: false
                    ))
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func layers(_ frame: EdgeGlowFrame) -> some View {
        let gradient = AngularGradient(
            colors: palette.glow.map { Color($0) },
            center: .center,
            angle: .degrees(frame.rotationDegrees)
        )
        // Concentric with the display. The minimum keeps a visible curve in a window whose
        // container has square corners.
        let border = ConcentricRectangle(corners: .concentric(minimum: 20))
        return ZStack {
            border
                .stroke(gradient, lineWidth: frame.lineWidth * 3)
                .blur(radius: frame.blurRadius)
            border
                .stroke(gradient, lineWidth: frame.lineWidth)
                .blur(radius: 1.5)
        }
        .opacity(frame.opacity)
    }
}
