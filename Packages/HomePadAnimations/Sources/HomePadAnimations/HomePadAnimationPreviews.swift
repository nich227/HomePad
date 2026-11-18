import HomePadAnimationsCore
import SwiftUI

/// Every bundled animation in a grid on black, the way they sit on the hub screen.
private struct AnimationGallery: View {
    var tint: Color?
    var isPlaying = true

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 24)], spacing: 24) {
                ForEach(HomePadAnimation.allCases, id: \.self) { animation in
                    VStack(spacing: 8) {
                        HomePadAnimationView(authored: animation, isPlaying: isPlaying, tint: tint)
                        Text(verbatim: animation.rawValue)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            .padding(24)
        }
        .background(.black)
    }
}

#Preview("All animations") {
    AnimationGallery()
}

#Preview("Tinted") {
    AnimationGallery(tint: .orange)
}

#Preview("Paused on first frame") {
    AnimationGallery(isPlaying: false)
}

#Preview("Play once with callback") {
    @Previewable @State var finished = false
    VStack(spacing: 16) {
        HomePadAnimationView(.success, loop: false, tint: .green)
            .onFinished { finished = true }
            .frame(width: 240, height: 240)
        Text(verbatim: finished ? "finished" : "playing")
            .foregroundStyle(.white)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.black)
}
