import Foundation
import HomePadBeamCore
import HomePadCore
import SwiftUI
import UIKit
import WebKit

/// Owns one web page. A page is only ever loaded from a `ValidatedURL`, the app never injects or
/// evaluates script in it, and it has no way to hand anything to another app: no downloads, no
/// file pickers, no camera, microphone, motion, or location, no dialogs, no menus, and no
/// navigation outside the URL policy.
///
/// The cookie and storage jar is fixed when the page is made and never changes, so nothing
/// reloads the page under the person reading it.
@MainActor
@Observable
public final class BeamBrowserModel {
    public private(set) var title = ""
    public private(set) var url: URL?
    public private(set) var isLoading = false
    public private(set) var estimatedProgress = 0.0
    public private(set) var canGoBack = false
    public private(set) var canGoForward = false
    public private(set) var hasOnlySecureContent = false

    public let dataStore: BrowserDataStore
    /// Checked on every navigation, so a change of the local-address preference applies to the
    /// next navigation of a page that is already open.
    @ObservationIgnored public var policy: BeamURLPolicy
    /// Called when a link asks for a new window. When `nil`, the address loads in this page.
    @ObservationIgnored public var onNewPage: ((ValidatedURL) -> Void)?

    @ObservationIgnored let webView: LockedWebView
    @ObservationIgnored private let delegate = PageDelegate()
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    /// The address of the load the app last started, until the navigation delegate has seen it.
    @ObservationIgnored private var ownRequestURL: URL?
    /// Loads started in place of a navigation since the delegate last recognized one of them.
    @ObservationIgnored private var unrecognizedReloads = 0

    private static let reloadLimit = 8

    public init(dataStore: BrowserDataStore = .ephemeral, policy: BeamURLPolicy = BeamURLPolicy()) {
        self.dataStore = dataStore
        self.policy = policy
        self.webView = LockedWebView(frame: .zero, configuration: Self.makeConfiguration(dataStore: dataStore))
        webView.allowsLinkPreview = false
        webView.allowsBackForwardNavigationGestures = true
        delegate.model = self
        webView.navigationDelegate = delegate
        webView.uiDelegate = delegate
        observe()
    }

    public func load(_ url: ValidatedURL) {
        load(URLRequest(url: url.url))
    }

    public func goBack() {
        webView.goBack()
    }

    public func goForward() {
        webView.goForward()
    }

    public func reload() {
        webView.reload()
    }

    /// Stops the page for good: nothing loads, nothing plays, nothing is presented over the app,
    /// the document is replaced by an empty one, and the view leaves the screen. Call it before
    /// dropping the last reference, which frees the web view and its process.
    public func shutDown() {
        onNewPage = nil
        observations = []
        delegate.model = nil
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.stopLoading()
        webView.closeAllMediaPresentations(completionHandler: nil)
        webView.pauseAllMediaPlayback(completionHandler: nil)
        webView.loadHTMLString("", baseURL: nil)
        webView.removeFromSuperview()
    }

    // MARK: Decisions asked by the web view

    /// Applies the navigation policy to one navigation and carries out the parts that are not a
    /// plain yes or no.
    fileprivate func decide(_ action: WKNavigationAction) -> WKNavigationActionPolicy {
        let request = action.request
        let targetsMainFrame = action.targetFrame?.isMainFrame
        let isOwnRequest = targetsMainFrame == true && request.url != nil && request.url == ownRequestURL
        if isOwnRequest {
            ownRequestURL = nil
            unrecognizedReloads = 0
        }
        let decision = BeamNavigationPolicy.decide(
            url: request.url,
            targetsMainFrame: targetsMainFrame,
            isDownload: action.shouldPerformDownload,
            trigger: BeamNavigationPolicy.Trigger(action.navigationType),
            isGet: (request.httpMethod ?? "GET").uppercased() == "GET" && request.httpBody == nil,
            currentURL: webView.url,
            isOwnRequest: isOwnRequest,
            policy: policy
        )
        switch decision {
        case .allow:
            return .allow
        case .cancel:
            return .cancel
        case .loadInPlace:
            // Each such load comes back here and is recognized. Were one never recognized, the
            // page would be loaded again without end, so the navigation is dropped instead.
            guard unrecognizedReloads < Self.reloadLimit else {
                unrecognizedReloads = 0
                return .cancel
            }
            unrecognizedReloads += 1
            load(request)
            return .cancel
        case .openInNewPage:
            openInNewPage(request)
            return .cancel
        }
    }

    /// Opens what asked for a new window as another page, or here when nobody takes new pages.
    private func openInNewPage(_ request: URLRequest) {
        guard let url = request.url, case .success(let validated) = policy.validate(url) else { return }
        if let onNewPage {
            onNewPage(validated)
        } else {
            load(request)
        }
    }

    /// Loads a request the app itself makes. The navigation delegate lets exactly this address
    /// through without asking whether it should be loaded again.
    private func load(_ request: URLRequest) {
        ownRequestURL = request.url
        webView.load(request)
    }

    // MARK: Setup

    private func observe() {
        observations = [
            webView.observe(\.title, options: [.initial, .new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.title = view.title ?? "" }
            },
            webView.observe(\.url, options: [.initial, .new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.url = view.url }
            },
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.isLoading = view.isLoading }
            },
            webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.estimatedProgress = view.estimatedProgress }
            },
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.canGoBack = view.canGoBack }
            },
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.canGoForward = view.canGoForward }
            },
            webView.observe(\.hasOnlySecureContent, options: [.initial, .new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.hasOnlySecureContent = view.hasOnlySecureContent }
            },
        ]
    }

    private static func makeConfiguration(dataStore: BrowserDataStore) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        switch dataStore {
        case .ephemeral: configuration.websiteDataStore = .nonPersistent()
        case .profile(let id): configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: id)
        }
        // Inline, so a video never brings up the system's own full screen player.
        configuration.allowsInlineMediaPlayback = true
        // A picture in picture window and an AirPlay route both outlive the page on screen.
        configuration.allowsPictureInPictureMediaPlayback = false
        configuration.allowsAirPlayForMediaPlayback = false
        // Detected phone numbers, addresses, and dates become links that open other apps.
        configuration.dataDetectorTypes = []
        configuration.allowsInlinePredictions = false
        configuration.supportsAdaptiveImageGlyph = false
        configuration.writingToolsBehavior = .none
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        return configuration
    }
}

extension BeamNavigationPolicy.Trigger {
    fileprivate init(_ type: WKNavigationType) {
        switch type {
        case .linkActivated: self = .link
        case .formSubmitted, .formResubmitted: self = .form
        case .backForward: self = .backForward
        case .reload: self = .reload
        case .other: self = .other
        @unknown default: self = .other
        }
    }
}

/// A web view with no menus and nothing to drag out of it. Text can still be typed and selected,
/// so forms work, but every action a menu or a keyboard shortcut could offer (copy, paste, look
/// up, translate, share, search the web) is refused, and what is left of the edit menu is removed.
final class LockedWebView: WKWebView {
    private static let removedMenus: [UIMenu.Identifier] = [
        .standardEdit, .replace, .share, .lookup, .learn, .speech, .autoFill, .textStyle, .find,
    ]

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        false
    }

    override func buildMenu(with builder: any UIMenuBuilder) {
        super.buildMenu(with: builder)
        for identifier in Self.removedMenus {
            builder.remove(menu: identifier)
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        disableDragging(in: self)
    }

    /// A link, image, or selection dragged out of the page lands in whatever app is beside this
    /// one. The web view sets its drag interaction up on views of its own, so they are found by
    /// walking the hierarchy each time the view comes on screen.
    private func disableDragging(in view: UIView) {
        for case let drag as UIDragInteraction in view.interactions {
            drag.isEnabled = false
        }
        for subview in view.subviews {
            disableDragging(in: subview)
        }
    }
}

/// Answers the web view's questions for one page. Every answer that could put system interface
/// in front of whoever is at the hub, or let the page out of the app, is "no".
@MainActor
private final class PageDelegate: NSObject, WKNavigationDelegate, WKUIDelegate {
    weak var model: BeamBrowserModel?

    // MARK: Navigation

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        model?.decide(navigationAction) ?? .cancel
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        let disposition = (navigationResponse.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition")
        let allowed = BeamNavigationPolicy.allowsResponse(
            canShowMimeType: navigationResponse.canShowMIMEType,
            contentDisposition: disposition
        )
        return allowed ? .allow : .cancel
    }

    // The policy above never answers "download". Should one start anyway, it is stopped.
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.cancel(nil)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.cancel(nil)
    }

    // MARK: Windows

    /// A new window never exists. What asked for one becomes another page of the session.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        _ = model?.decide(navigationAction)
        return nil
    }

    // MARK: Dialogs and pickers

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async {}

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async -> Bool {
        false
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo
    ) async -> String? {
        nil
    }

    /// No file leaves this iPad: a file input gets no file and no picker is shown.
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo) async -> [URL]? {
        nil
    }

    // MARK: Menus

    /// No menu on a long press. With link previews off as well, a link or image offers nothing
    /// to open elsewhere, share, or save.
    func webView(_ webView: WKWebView, contextMenuConfigurationFor elementInfo: WKContextMenuElementInfo) async -> UIContextMenuConfiguration? {
        nil
    }

    // MARK: Sensors

    // The front camera belongs to face recognition, and a page on a shared screen gets neither
    // it nor the microphone, the motion sensors, or the hub's location. Denying means no prompt.
    func webView(
        _ webView: WKWebView,
        decideMediaCapturePermissionsFor origin: WKSecurityOrigin,
        initiatedBy frame: WKFrameInfo,
        type: WKMediaCaptureType
    ) async -> WKPermissionDecision {
        .deny
    }

    func webView(
        _ webView: WKWebView,
        requestDeviceOrientationAndMotionPermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void
    ) {
        decisionHandler(.deny)
    }

    func webView(
        _ webView: WKWebView,
        requestGeolocationPermissionFor origin: WKSecurityOrigin,
        initiatedBy frame: WKFrameInfo
    ) async -> WKPermissionDecision {
        .deny
    }
}

/// Shows a model's web view. The view belongs to the model, so taking this off screen does not
/// stop the page: the model's `shutDown()` does.
struct BeamWebView: UIViewRepresentable {
    let model: BeamBrowserModel

    func makeUIView(context: Context) -> UIView {
        let host = UIView()
        host.clipsToBounds = true
        return host
    }

    func updateUIView(_ host: UIView, context: Context) {
        let webView = model.webView
        guard webView.superview !== host else { return }
        host.subviews.forEach { $0.removeFromSuperview() }
        webView.frame = host.bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.addSubview(webView)
    }
}

/// The web pages behind the open pages of the person in front of the hub. A web page lives
/// exactly as long as its page is listed here, so closing a page or signing out stops its sound
/// and video and frees it.
@MainActor
@Observable
final class BeamPageStore {
    private var models: [UUID: BeamBrowserModel] = [:]

    func model(for pageID: UUID) -> BeamBrowserModel? {
        models[pageID]
    }

    /// Makes the web pages match `pages`: shuts down and lets go of every one that is no longer
    /// listed, and creates and loads the new ones, each with the data store its page opened with.
    func sync(
        pages: [BrowserPage],
        policy: BeamURLPolicy,
        onNewPage: @escaping (_ parentID: UUID, _ url: ValidatedURL) -> Void
    ) {
        let open = Set(pages.map(\.id))
        for (id, model) in models where !open.contains(id) {
            model.shutDown()
            models[id] = nil
        }
        for page in pages {
            if let model = models[page.id] {
                model.policy = policy
            } else {
                let model = BeamBrowserModel(dataStore: page.dataStore, policy: policy)
                let parentID = page.id
                model.onNewPage = { url in onNewPage(parentID, url) }
                model.load(page.beam.url)
                models[page.id] = model
            }
        }
    }
}
