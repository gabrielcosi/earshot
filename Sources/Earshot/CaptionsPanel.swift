import AppKit
import EarshotKit
import SwiftUI

/// The captions overlay's window. The panel is made once and kept, so AppKit keeps remembering
/// its frame; hidden, it holds no SwiftUI content, so a partial costs it nothing.
final class Captions {
    private var panel: CaptionsPanel?

    /// AppKit saves the frame under "NSWindow Frame CaptionsOverlay".
    private static let frameName = "CaptionsOverlay"
    /// The approved design's size: its width, and its height at Medium, two translated turns and
    /// the live line under the status.
    private static let size = CGSize(width: 620, height: 200)

    func show(_ content: some View) {
        let panel = panel ?? makePanel()
        guard let material = panel.contentView else { return }
        if material.subviews.isEmpty {
            let hosting = NSHostingView(rootView: content)
            // The content sets the least width and height; the user sizes it from there.
            hosting.sizingOptions = [.minSize]
            // The title bar is hidden; its safe area would leave an empty band at the top.
            hosting.safeAreaRegions = []
            hosting.translatesAutoresizingMaskIntoConstraints = false
            material.addSubview(hosting)
            NSLayoutConstraint.activate([
                hosting.leadingAnchor.constraint(equalTo: material.leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: material.trailingAnchor),
                hosting.topAnchor.constraint(equalTo: material.topAnchor),
                hosting.bottomAnchor.constraint(equalTo: material.bottomAnchor),
            ])
            place(panel)
        }
        // Never `NSApp.activate()`: it would switch away from a full-screen call's Space.
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.contentView?.subviews.forEach { $0.removeFromSuperview() }
    }

    /// Where it was left, at the size it was left. The content's least size still holds: a
    /// larger text size can make it taller.
    private func place(_ panel: NSPanel) {
        let saved = panel.setFrameUsingName(Self.frameName) ? panel.frame : nil
        panel.setFrame(
            CaptionsPlacement.frame(
                saved: saved,
                screens: ([NSScreen.main] + NSScreen.screens).compactMap { $0?.visibleFrame },
                size: Self.size),
            display: false)
    }

    private func makePanel() -> CaptionsPanel {
        let panel = CaptionsPanel()
        panel.setFrameAutosaveName(Self.frameName)
        self.panel = panel
        return panel
    }
}

/// Floats over every app, on every Space, and over full-screen apps. It takes clicks without
/// activating Earshot or taking the keyboard, so typing stays in the call. SwiftUI's windows can do
/// none of this (ADR-0011).
final class CaptionsPanel: NSPanel {
    init() {
        // Titled for the system's shadow, corners, and edge resizing; the title bar is hidden.
        super.init(
            contentRect: .zero,
            styleMask: [
                .titled, .fullSizeContentView, .resizable, .nonactivatingPanel, .utilityWindow,
            ],
            backing: .buffered, defer: true)
        title = "Captions"
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
        // Also sets the floating level.
        isFloatingPanel = true
        hidesOnDeactivate = false
        // Hide Others in another app would take the captions away mid-call.
        canHide = false
        // Without the non-activating style mask above, a panel of a regular app, which Earshot is
        // while its window is open, is not shown over another app's full-screen Space.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        // The panel is kept for the app's life, even if something closes it.
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        // Captions are read over any video, bright or dark.
        appearance = NSAppearance(named: .darkAqua)
        let material = NSVisualEffectView()
        material.material = .hudWindow
        material.blendingMode = .behindWindow
        material.state = .active
        contentView = material
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
