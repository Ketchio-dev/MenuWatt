import AppKit
import SwiftUI

/// The scrolling container hosting every settings pane.
///
/// Extracted from SettingsPanel.swift. Scrolling stays manual-only
/// (wheel-driven): programmatic autoscroll is ignored until the user has
/// scrolled explicitly, and scroller style changes still re-measure the
/// viewport instead of leaving a stale blank region.
struct ManualOnlyScrollView<Content: View>: NSViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeNSView(context: Context) -> ManualOnlyScrollContainer<Content> {
        ManualOnlyScrollContainer(rootView: content)
    }

    func updateNSView(_ nsView: ManualOnlyScrollContainer<Content>, context: Context) {
        nsView.update(rootView: content)
    }
}

final class ManualOnlyScrollContainer<Content: View>: NSView {
    private let scrollView = ManualOnlyNSScrollView()
    private let viewport = SettingsScrollViewport()
    private let hostingView: NSHostingView<SettingsScrollContent<Content>>

    init(rootView: Content) {
        self.hostingView = NSHostingView(rootView: SettingsScrollContent(content: rootView, viewport: viewport))
        super.init(frame: .zero)

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.sizingOptions = [.intrinsicContentSize]
        scrollView.documentView = hostingView
        scrollView.viewportDidChange = { [weak self] in self?.updateViewportWidth() }
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            hostingView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])
        // Intrinsic height follows the actual viewport width and nested state
        // (e.g. search), not an unconstrained ideal width or a stale fixed height.
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        updateViewportWidth()
    }

    private func updateViewportWidth() {
        let width = scrollView.contentView.bounds.width
        guard width > 0, abs(viewport.width - width) > 0.5 else { return }
        viewport.width = width
        hostingView.invalidateIntrinsicContentSize()
        hostingView.needsLayout = true
    }

    func update(rootView: Content) {
        hostingView.rootView = SettingsScrollContent(content: rootView, viewport: viewport)
    }
}

final class SettingsScrollViewport: ObservableObject {
    @Published var width: CGFloat = 1
}

struct SettingsScrollContent<Content: View>: View {
    let content: Content
    @ObservedObject var viewport: SettingsScrollViewport

    var body: some View {
        content
            .frame(width: viewport.width, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .modifier(SettingsControlsStyle())
    }
}

final class ManualOnlyNSScrollView: NSScrollView {
    var viewportDidChange: (() -> Void)?
    private var hasReceivedExplicitScroll = false

    override func tile() {
        super.tile()
        // Scroller style/visibility can resize the clip view without a parent layout.
        viewportDidChange?()
    }

    override func scrollWheel(with event: NSEvent) {
        hasReceivedExplicitScroll = true
        super.scrollWheel(with: event)
    }

    override func autoscroll(with event: NSEvent) -> Bool {
        guard hasReceivedExplicitScroll else {
            return false
        }

        return super.autoscroll(with: event)
    }
}
