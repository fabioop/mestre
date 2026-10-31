import AppKit
import Combine
import MestreCore
import SwiftUI

/// Borderless, non-activating floating panel. Non-activating means the panel can
/// take keyboard focus without making Mestre the active app, so when it closes
/// the previous app is still frontmost and nothing in the menu bar flickers.
final class SearchPanel: NSPanel {
    /// Return true to swallow a key-down event. Runs before the field editor, so
    /// bound keys (arrows, Return, ⌘Q…) never reach the text field.
    var onKeyDown: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, !isComposingText, onKeyDown?(event) == true { return }
        super.sendEvent(event)
    }

    /// While an input method (Japanese, Chinese…) is composing, Return and Escape
    /// belong to the composition, not to the panel.
    private var isComposingText: Bool {
        (firstResponder as? NSTextView)?.hasMarkedText() ?? false
    }
}

@MainActor
final class SearchPanelController: NSObject, NSWindowDelegate {
    let panel: SearchPanel
    private let viewModel: SearchViewModel
    private let hostingView: NSHostingView<SearchView>
    private let effectView = NSVisualEffectView()
    /// Liquid Glass container, used instead of `effectView` on macOS 26 when the material is
    /// glass. Typed as NSView because stored properties can't be `@available`.
    private var glassView: NSView?
    private var cancellables = Set<AnyCancellable>()

    init(viewModel: SearchViewModel) {
        self.viewModel = viewModel
        panel = SearchPanel(
            contentRect: NSRect(x: 0, y: 0, width: viewModel.layout.width, height: viewModel.layout.fieldHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        hostingView = NSHostingView(rootView: SearchView(viewModel: viewModel))
        super.init()
        configurePanel()

        viewModel.onDismiss = { [weak self] in self?.hide() }
        panel.onKeyDown = { [weak viewModel] event in
            guard let viewModel, let binding = viewModel.bindings.binding(for: event) else { return false }
            return viewModel.perform(binding)
        }
        // Results and the actions menu change the height; nothing else does. Hidden panels
        // don't resize: show() measures from scratch.
        viewModel.$results.map { _ in () }
            .merge(with: viewModel.$actionIndex.map { $0 != nil }.removeDuplicates().map { _ in () })
            .merge(with: viewModel.$chips.map(\.isEmpty).removeDuplicates().map { _ in () })
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                guard let self, self.panel.isVisible else { return }
                self.resizeToFit()
            }
            .store(in: &cancellables)
        viewModel.$layout
            .receive(on: RunLoop.main)
            .sink { [weak self] layout in self?.apply(layout) }
            .store(in: &cancellables)
    }

    private func configurePanel() {
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow
        panel.delegate = self

        effectView.blendingMode = .behindWindow
        effectView.wantsLayer = true
        effectView.layer?.cornerCurve = .continuous
        effectView.layer?.masksToBounds = true
        hostingView.translatesAutoresizingMaskIntoConstraints = false
    }

    /// Puts the SwiftUI content inside the container the material calls for.
    private func mount(in container: NSView, attach: (NSView) -> Void) {
        guard panel.contentView !== container else { return }
        hostingView.removeFromSuperview()
        // The glass keeps its contentView after that, and setting the same one again does nothing.
        if #available(macOS 26.0, *) { (glassView as? NSGlassEffectView)?.contentView = nil }
        attach(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: container.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        panel.contentView = container
    }

    private var appliedLayout: Config.Panel?
    private var appliedAppearance: Config.Panel.Appearance?
    private var maskRadius: Double?

    private func apply(_ layout: Config.Panel) {
        if #available(macOS 26.0, *), layout.material.isGlass {
            let glass = (glassView as? NSGlassEffectView) ?? NSGlassEffectView()
            glass.cornerRadius = layout.cornerRadius
            glass.style = layout.material == .clearGlass ? .clear : .regular
            // The glass draws a soft shadow around itself, and the window cuts that shadow off
            // square: without this clip a faint rectangle shows in all four corners.
            glass.wantsLayer = true
            glass.layer?.cornerCurve = .continuous
            glass.layer?.cornerRadius = layout.cornerRadius
            glass.layer?.masksToBounds = true
            glassView = glass
            mount(in: glass) { glass.contentView = $0 }
        } else {
            effectView.layer?.cornerRadius = layout.cornerRadius
            // The layer's corners don't reach the blur behind the window; only a mask image does.
            if maskRadius != layout.cornerRadius {
                effectView.maskImage = Self.cornerMask(radius: layout.cornerRadius)
                maskRadius = layout.cornerRadius
            }
            // "none" keeps the view (it hosts the content) but drops the blur.
            effectView.state = layout.material == .none ? .inactive : .active
            effectView.material = Self.material(for: layout.material)
            mount(in: effectView) { effectView.addSubview($0) }
        }
        if appliedAppearance != layout.appearance {
            switch layout.appearance {
            case .system: panel.appearance = nil
            case .light: panel.appearance = NSAppearance(named: .aqua)
            case .dark: panel.appearance = NSAppearance(named: .darkAqua)
            }
            appliedAppearance = layout.appearance
        }
        if panel.isVisible {
            resizeToFit()
            let moved = appliedLayout.map { $0.width != layout.width || $0.verticalPosition != layout.verticalPosition } ?? true
            if moved { positionOnActiveScreen() }
        }
        appliedLayout = layout
    }

    /// A rounded shape that stretches with the panel, so resizing doesn't redraw it.
    private static func cornerMask(radius: CGFloat) -> NSImage {
        let side = 2 * radius + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    private static func material(for material: Config.Panel.Material) -> NSVisualEffectView.Material {
        switch material {
        case .popover, .glass, .clearGlass: return .popover  // glass falls back to popover before macOS 26
        case .hud: return .hudWindow
        case .sidebar: return .sidebar
        case .menu: return .menu
        case .window, .none: return .windowBackground
        }
    }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    /// Captures the panel's own window to a PNG at screen resolution: a developer aid kept in
    /// release builds so `--screenshot` works on the bundle. A process may capture its own
    /// windows without the Screen Recording permission; this is the only API that includes
    /// the glass backdrop (deprecated, but present on macOS 26).
    func writeScreenshot(to url: URL) {
        Self.writeScreenshot(of: panel, to: url)
    }

    static func writeScreenshot(of window: NSWindow, to url: URL) {
        let id = CGWindowID(window.windowNumber)
        guard let image = CGWindowListCreateImage(.null, .optionIncludingWindow, id, [.boundsIgnoreFraming, .bestResolution]) else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
    }

    func show() {
        Perf.measure("panel show") {
            viewModel.isPanelVisible = true
            // Keys must be assigned before the home rows are built, or they carry the last assignment.
            viewModel.assignQuickKeys()
            viewModel.reset()
            resizeToFit()
            positionOnActiveScreen()
            panel.makeKeyAndOrderFront(nil)
            viewModel.requestFocus()
        }
        viewModel.panelWillShow()
    }

    func hide() {
        viewModel.isPanelVisible = false
        panel.orderOut(nil)
    }

    /// Grows and shrinks with the result list while keeping the top edge where it is.
    private func resizeToFit() {
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize  // SwiftUI owns both width and height
        var frame = panel.frame
        guard frame.size != size else { return }  // typing within the same row count moves nothing
        let top = frame.maxY
        frame.size = size
        frame.origin.y = top - size.height
        panel.setFrame(frame, display: true)
    }

    private func positionOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let x = visible.midX - panel.frame.width / 2
        let top = visible.maxY - visible.height * viewModel.layout.verticalPosition
        panel.setFrameTopLeftPoint(NSPoint(x: x, y: top))
    }

    // Losing key status (click elsewhere, another app activates) closes the panel.
    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}
