import HomePadBeam
import HomePadCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The share extension's only screen. It finds the web address in what was shared and hands it to
/// `BeamShareView`, which does the rest.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        Task { await loadSharedPage() }
    }

    private func loadSharedPage() async {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        guard let page = await Self.sharedPage(in: items) else {
            finish()
            return
        }
        // The app mirrors the settings this extension reads into the app group defaults.
        let defaults = UserDefaults(suiteName: HomePadIdentifiers.appGroup) ?? .standard
        let root = BeamShareView(url: page.url, title: page.title, defaults: defaults) { [weak self] in
            self?.finish()
        }
        let host = UIHostingController(rootView: root)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    /// Safari shares the page as a URL attachment. When the extension has a JavaScript
    /// preprocessing file, the address arrives in a property list instead; both are read.
    private static func sharedPage(in items: [NSExtensionItem]) async -> (url: URL, title: String?)? {
        for item in items {
            let title = item.attributedContentText?.string ?? item.attributedTitle?.string
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                    return (url, title)
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.propertyList.identifier),
                   let list = try? await provider.loadItem(forTypeIdentifier: UTType.propertyList.identifier) as? [String: Any],
                   let results = list[NSExtensionJavaScriptPreprocessingResultsKey] as? [String: Any],
                   let text = results["URL"] as? String, let url = URL(string: text) {
                    return (url, results["title"] as? String ?? title)
                }
            }
        }
        return nil
    }
}
