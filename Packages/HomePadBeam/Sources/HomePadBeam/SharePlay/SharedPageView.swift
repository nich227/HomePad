import HomePadBeamCore
import SwiftUI
import WebKit

/// A companion's view of a browse-together session: the shared page, kept in step with everyone
/// else. It browses without a persistent cookie jar.
public struct SharedPageView: View {
    private let coordinator: SharePlayCoordinator

    @State private var model = BeamBrowserModel()

    public init(coordinator: SharePlayCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        VStack(spacing: 0) {
            if model.page.isLoading {
                ProgressView(value: model.page.estimatedProgress)
                    .accessibilityLabel(Text("Loading page"))
            }
            WebView(model.page)
        }
        .navigationTitle(Text(model.page.title.isEmpty ? (model.page.url?.host() ?? "") : model.page.title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button("Back", systemImage: "chevron.backward") { model.goBack() }
                    .disabled(!model.canGoBack)
                Button("Forward", systemImage: "chevron.forward") { model.goForward() }
                    .disabled(!model.canGoForward)
                Spacer()
                Text("\(coordinator.participantCount) browsing")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Leave", systemImage: "shareplay.slash") { coordinator.leave() }
            }
        }
        .task(id: coordinator.currentPage) {
            guard let page = coordinator.currentPage, page.url != model.page.url else { return }
            model.load(page)
        }
        .onChange(of: model.page.url) { _, url in
            guard let url else { return }
            coordinator.localDidNavigate(to: url, title: model.page.title.isEmpty ? nil : model.page.title)
        }
    }
}
