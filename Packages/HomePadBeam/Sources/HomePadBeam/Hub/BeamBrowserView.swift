import HomePadBeamCore
import HomePadCore
import SwiftUI
import WebKit

/// Owns the web page the hub is showing. A page is only ever loaded from a `ValidatedURL`, and
/// the app never injects or evaluates script in it.
@MainActor
@Observable
public final class BeamBrowserModel {
    public private(set) var page: WebPage
    public private(set) var dataStore: BrowserDataStore
    public private(set) var policy: BeamURLPolicy

    public init(dataStore: BrowserDataStore = .ephemeral, policy: BeamURLPolicy = BeamURLPolicy()) {
        self.dataStore = dataStore
        self.policy = policy
        self.page = Self.makePage(dataStore: dataStore, policy: policy)
    }

    public func load(_ url: ValidatedURL) {
        page.load(URLRequest(url: url.url))
    }

    /// Switches cookie jars when the person in front of the hub changes, then reloads the page so
    /// nothing fetched with the previous jar stays on screen.
    public func use(dataStore newStore: BrowserDataStore, policy newPolicy: BeamURLPolicy) {
        guard newStore != dataStore || newPolicy != policy else { return }
        let reload = page.url.flatMap { try? newPolicy.validate($0).get() }
        dataStore = newStore
        policy = newPolicy
        page = Self.makePage(dataStore: newStore, policy: newPolicy)
        if let reload { load(reload) }
    }

    public var canGoBack: Bool { !page.backForwardList.backList.isEmpty }
    public var canGoForward: Bool { !page.backForwardList.forwardList.isEmpty }

    public func goBack() {
        guard let item = page.backForwardList.backList.last else { return }
        page.load(item)
    }

    public func goForward() {
        guard let item = page.backForwardList.forwardList.first else { return }
        page.load(item)
    }

    public func reload() {
        page.reload()
    }

    private static func makePage(dataStore: BrowserDataStore, policy: BeamURLPolicy) -> WebPage {
        var configuration = WebPage.Configuration()
        switch dataStore {
        case .ephemeral: configuration.websiteDataStore = .nonPersistent()
        case .profile(let id): configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: id)
        }
        let box = PageBox()
        let page = WebPage(configuration: configuration, navigationDecider: NavigationDecider(policy: policy, box: box))
        box.page = page
        return page
    }
}

/// Lets the navigation decider reach the page it belongs to without owning it.
@MainActor
private final class PageBox {
    weak var page: WebPage?
}

private struct NavigationDecider: WebPage.NavigationDeciding {
    let policy: BeamURLPolicy
    let box: PageBox

    @MainActor
    mutating func decidePolicy(
        for action: WebPage.NavigationAction,
        preferences: inout WebPage.NavigationPreferences
    ) async -> WKNavigationActionPolicy {
        let decision = BeamNavigationPolicy.decide(
            url: action.request.url,
            targetsMainFrame: action.target?.isMainFrame,
            isDownload: action.shouldPerformDownload,
            policy: policy
        )
        switch decision {
        case .allow:
            return .allow
        case .cancel:
            return .cancel
        case .loadInPlace:
            box.page?.load(action.request)
            return .cancel
        }
    }

    @MainActor
    mutating func decidePolicy(for response: WebPage.NavigationResponse) async -> WKNavigationResponsePolicy {
        response.canShowMimeType ? .allow : .cancel
    }
}

/// The hub's browser: the page, and a toolbar with back, forward, reload, share, send back to the
/// iPhone, and close.
public struct BeamBrowserView<Accessory: View>: View {
    private let receiver: BeamReceiver
    private let session: HouseholdSession
    private let beam: ApprovedBeam
    private let onNavigate: ((URL, String?) -> Void)?
    private let accessory: Accessory

    @State private var model = BeamBrowserModel()
    @State private var sendBackFailed = false

    /// - Parameters:
    ///   - onNavigate: Called when the page moves to a new address, for SharePlay.
    ///   - accessory: Extra toolbar content, such as `SharePlayButton`.
    public init(
        receiver: BeamReceiver,
        session: HouseholdSession,
        beam: ApprovedBeam,
        onNavigate: ((URL, String?) -> Void)? = nil,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) {
        self.receiver = receiver
        self.session = session
        self.beam = beam
        self.onNavigate = onNavigate
        self.accessory = accessory()
    }

    private var storeChoice: BrowserDataStore {
        BrowserDataStore.choice(
            isPersonalContentUnlocked: session.isPersonalContentUnlocked,
            activeProfileID: session.activeProfile?.id
        )
    }

    public var body: some View {
        VStack(spacing: 0) {
            toolbar
            if model.page.isLoading {
                ProgressView(value: model.page.estimatedProgress)
                    .accessibilityLabel(Text("Loading page"))
            }
            WebView(model.page)
                .webViewBackForwardNavigationGestures(.enabled)
        }
        .task(id: beam.id) {
            model.use(dataStore: storeChoice, policy: receiver.preferences.urlPolicy)
            model.load(beam.url)
        }
        .onChange(of: storeChoice) { _, choice in
            model.use(dataStore: choice, policy: receiver.preferences.urlPolicy)
        }
        .onChange(of: model.page.url) { _, url in
            guard let url else { return }
            onNavigate?(url, model.page.title.isEmpty ? nil : model.page.title)
        }
        .alert(Text("Could not send the page to the iPhone"), isPresented: $sendBackFailed) {
            Button("OK", role: .cancel) {}
        }
    }

    private var toolbar: some View {
        HStack(spacing: 20) {
            Button("Back", systemImage: "chevron.backward") { model.goBack() }
                .disabled(!model.canGoBack)
            Button("Forward", systemImage: "chevron.forward") { model.goForward() }
                .disabled(!model.canGoForward)
            Button("Reload", systemImage: "arrow.clockwise") { model.reload() }

            VStack(alignment: .leading, spacing: 2) {
                Text(model.page.title.isEmpty ? (beam.payload.title ?? "") : model.page.title)
                    .font(.headline)
                    .lineLimit(1)
                Label {
                    Text(model.page.url?.host() ?? beam.url.url.host() ?? "")
                } icon: {
                    Image(systemName: model.page.hasOnlySecureContent ? "lock.fill" : "lock.open")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityLabel(Text(model.page.hasOnlySecureContent ? "Secure connection" : "Connection is not secure"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            accessory
            if let url = model.page.url {
                ShareLink(item: url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                if let target = receiver.sendBackTarget {
                    Button("Send to \(target.name)", systemImage: "iphone.and.arrow.forward") {
                        Task {
                            let title = model.page.title.isEmpty ? nil : model.page.title
                            sendBackFailed = await !receiver.sendBack(url, title: title)
                        }
                    }
                }
            }
            Button("Close", systemImage: "xmark") { receiver.closeBrowser() }
        }
        .labelStyle(.iconOnly)
        .font(.title2)
        .buttonStyle(.bordered)
        .controlSize(.large)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }
}
