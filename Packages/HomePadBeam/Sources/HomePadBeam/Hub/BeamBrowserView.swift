import HomePadBeamCore
import HomePadCore
import SwiftUI

/// The hub's whole browser for the person in front of it: their open pages with a switcher, a
/// toolbar, and, when nothing is open, their recent pages.
///
/// It shows only what `BeamReceiver` publishes for the active person, so it is empty for anyone
/// else. There is no address field: pages arrive by beam, and a person moves on by following
/// links. Nothing here opens another app, a share sheet, a file picker, or a print dialog.
public struct BeamBrowserView: View {
    private let receiver: BeamReceiver
    private let session: HouseholdSession
    private let sharePlay: SharePlayCoordinator?
    private let onNavigate: ((URL, String?) -> Void)?
    private let accessory: AnyView?
    private let leadingInset: CGFloat

    @State private var sendBackFailed = false

    /// - Parameters:
    ///   - sharePlay: When given, the toolbar offers browsing together and the page in front is
    ///     kept in step with the session.
    ///   - leadingInset: Width kept clear at the leading end of the toolbar, for a control the
    ///     host draws over that corner.
    public init(
        receiver: BeamReceiver,
        session: HouseholdSession,
        sharePlay: SharePlayCoordinator? = nil,
        leadingInset: CGFloat = 88
    ) {
        self.receiver = receiver
        self.session = session
        self.sharePlay = sharePlay
        self.onNavigate = nil
        self.accessory = nil
        self.leadingInset = leadingInset
    }

    /// The form older callers use. `beam` is not needed: the view draws every page of the
    /// active person and puts the one in front on screen.
    /// - Parameters:
    ///   - onNavigate: Called when the page in front moves to a new address, for SharePlay.
    ///   - accessory: Extra toolbar content, such as `SharePlayButton`.
    public init<Accessory: View>(
        receiver: BeamReceiver,
        session: HouseholdSession,
        beam: ApprovedBeam,
        onNavigate: ((URL, String?) -> Void)? = nil,
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) {
        self.receiver = receiver
        self.session = session
        self.sharePlay = nil
        self.onNavigate = onNavigate
        self.accessory = AnyView(accessory())
        self.leadingInset = 88
    }

    public var body: some View {
        Group {
            if let front = receiver.frontPage, let model = receiver.model(for: front.id) {
                VStack(spacing: 0) {
                    chrome(front: front, model: model)
                    if model.isLoading {
                        ProgressView(value: model.estimatedProgress)
                            .accessibilityLabel(Text("Loading page"))
                    }
                    BeamWebView(model: model)
                        .id(front.id)
                }
                .onChange(of: PageAddress(pageID: front.id, url: model.url)) { _, address in
                    guard let url = address.url else { return }
                    let title = model.title.isEmpty ? nil : model.title
                    onNavigate?(url, title)
                    sharePlay?.localDidNavigate(to: url, title: title)
                }
            } else {
                BeamBrowserEmptyView(receiver: receiver, ownerName: session.activeProfile?.name)
            }
        }
        .alert(Text("Could not send the page to the iPhone"), isPresented: $sendBackFailed) {
            Button("OK", role: .cancel) {}
        }
    }

    private var isFar: Bool { session.proximity == .far }

    private func chrome(front: BrowserPage, model: BeamBrowserModel) -> some View {
        let side: CGFloat = isFar ? 64 : 52
        return VStack(spacing: 10) {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    Color.clear.frame(width: leadingInset, height: 1)
                        .accessibilityHidden(true)
                    BrowserBarButton("Back", systemImage: "chevron.backward", side: side) { model.goBack() }
                        .disabled(!model.canGoBack)
                    BrowserBarButton("Forward", systemImage: "chevron.forward", side: side) { model.goForward() }
                        .disabled(!model.canGoForward)
                    BrowserBarButton("Reload", systemImage: "arrow.clockwise", side: side) { model.reload() }
                    addressLabel(front: front, model: model, side: side)
                    actions(model: model, side: side)
                }
            }
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            ForEach(receiver.pages) { page in
                                BrowserPageChip(
                                    title: title(of: page),
                                    isFront: page.id == front.id,
                                    isFar: isFar,
                                    select: { receiver.selectPage(page.id) },
                                    close: { receiver.closePage(page.id) }
                                )
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .scrollIndicators(.hidden)
                    ownerBadge
                }
            }
        }
        .font(isFar ? .title2 : .title3)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.black)
        .environment(\.colorScheme, .dark)
    }

    /// Shows where the person is. It is a label, not a field: there is nowhere to type an address.
    private func addressLabel(front: BrowserPage, model: BeamBrowserModel, side: CGFloat) -> some View {
        let isSecure = model.hasOnlySecureContent
        return VStack(alignment: .leading, spacing: 2) {
            Text(title(of: front))
                .font(isFar ? .title2.weight(.semibold) : .headline)
                .lineLimit(1)
            Label {
                Text(model.url?.host() ?? front.beam.url.url.host() ?? "")
            } icon: {
                Image(systemName: isSecure ? "lock.fill" : "lock.open")
            }
            .font(isFar ? .title3 : .subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, minHeight: side, alignment: .leading)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(isSecure ? "Secure connection" : "Connection is not secure"))
    }

    @ViewBuilder
    private func actions(model: BeamBrowserModel, side: CGFloat) -> some View {
        if let url = model.url {
            Group {
                if let sharePlay {
                    SharePlayButton(coordinator: sharePlay, url: url, title: model.title.isEmpty ? nil : model.title)
                }
                accessory
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.extraLarge)
            if let target = receiver.sendBackTarget {
                BrowserBarButton("Send to \(target.name)", systemImage: "iphone.and.arrow.forward", side: side) {
                    Task {
                        let title = model.title.isEmpty ? nil : model.title
                        sendBackFailed = await !receiver.sendBack(url, title: title)
                    }
                }
            }
        }
        BrowserBarButton("Close All Pages", systemImage: "xmark.square", side: side) { receiver.closeAllPages() }
    }

    private var ownerBadge: some View {
        let name = session.activeProfile?.name
        return Label {
            Text(name ?? String(localized: "Guest"))
        } icon: {
            Image(systemName: session.activeProfile?.symbolName ?? "person.crop.circle.badge.questionmark")
        }
        .lineLimit(1)
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            name.map { Text("These pages belong to \($0) and close when \($0) leaves") }
                ?? Text("These pages belong to a guest and close when the guest leaves")
        )
    }

    private func title(of page: BrowserPage) -> String {
        let live = receiver.model(for: page.id)
        if let title = live?.title, !title.isEmpty { return title }
        return page.beam.payload.title ?? live?.url?.host() ?? page.beam.url.url.host() ?? ""
    }
}

/// The page in front and where it is, so one observer sees a switch of pages and a navigation.
private struct PageAddress: Equatable {
    let pageID: UUID
    let url: URL?
}

/// A round glass toolbar button with a touch target of at least 52 points.
private struct BrowserBarButton: View {
    private let title: LocalizedStringKey
    private let systemImage: String
    private let side: CGFloat
    private let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    init(_ title: LocalizedStringKey, systemImage: String, side: CGFloat, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.side = side
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .fontWeight(.semibold)
                .frame(width: side, height: side)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.35)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(Text(title))
    }
}

/// One open page in the switcher: tap the title to bring it to the front, the cross to close it.
private struct BrowserPageChip: View {
    let title: String
    let isFront: Bool
    let isFar: Bool
    let select: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: select) {
                Text(title)
                    .font(isFar ? .title3.weight(.medium) : .body.weight(.medium))
                    .lineLimit(1)
                    .frame(minWidth: 60, maxWidth: isFar ? 320 : 220, minHeight: 44, alignment: .leading)
                    .padding(.leading, 18)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(title))
            .accessibilityAddTraits(isFront ? .isSelected : [])
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Close \(title)"))
        }
        .glassEffect(isFront ? .regular.tint(.accentColor.opacity(0.55)).interactive() : .regular.interactive(), in: .capsule)
    }
}

/// What the browser shows when the person in front of the hub has no page open: whose browser
/// it is, and their own recent pages.
private struct BeamBrowserEmptyView: View {
    let receiver: BeamReceiver
    let ownerName: String?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(systemName: "safari")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(ownerName.map { "\($0)'s Browser" } ?? String(localized: "Guest Browser"))
                    .font(.largeTitle.weight(.semibold))
                Text(ownerName == nil
                    ? "Pages opened here are shown to you only and close when you leave the hub."
                    : "Pages you send from your iPhone open here, for you only, and close when you leave the hub.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            .padding(.top, 96)
            .padding(.bottom, 16)
            .accessibilityElement(children: .combine)
            BeamRecentsView(receiver: receiver)
        }
    }
}

// MARK: Previews

@MainActor
private enum BrowserPreview {
    /// A receiver with nothing on the network and one household member picked by hand.
    static func make(pages: [String], member: Bool = true) -> (BeamReceiver, HouseholdSession) {
        let profile = HouseholdProfile(name: "Ada", tint: .allCases[0])
        let session = HouseholdSession(store: InMemoryProfileStore(profiles: [profile]))
        if member { try? session.switchManually(to: profile.id) }
        let store = InMemoryPairingStore()
        let link = PeerLink(localDevice: PeerDevice(id: UUID(), name: "Kitchen", role: .hub), store: store)
        let receiver = BeamReceiver(link: link, session: session, settings: HomePadSettings(), store: store)
        for page in pages {
            let activity = NSUserActivity(activityType: HomePadIdentifiers.beamActivityType)
            activity.userInfo = [HandoffPayload.urlKey: page]
            receiver.handle(userActivity: activity)
        }
        return (receiver, session)
    }
}

#Preview("Three pages") {
    let (receiver, session) = BrowserPreview.make(pages: [
        "https://example.com/soup", "https://example.org/bread", "https://example.net/salad",
    ])
    BeamBrowserView(receiver: receiver, session: session)
}

#Preview("Nothing open, with recents") {
    let (receiver, session) = BrowserPreview.make(pages: ["https://example.com/soup", "https://example.org/bread"])
    BeamBrowserView(receiver: receiver, session: session)
        .onAppear { receiver.closeAllPages() }
}

#Preview("Guest") {
    let (receiver, session) = BrowserPreview.make(pages: [], member: false)
    BeamBrowserView(receiver: receiver, session: session)
}
