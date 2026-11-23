import AppKit

/// A brief on-screen badge, like the system volume popup, confirming a switch
/// between Live and Loop. Needed because the menu-bar icon can be hidden when
/// the menu bar is full (behind the notch on laptops).
final class ModeHUD {
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(loop: Bool, inUse: Bool) {
        let panel = self.panel ?? makePanel()
        self.panel = panel

        let color = loop ? MenuIcon.loopColor : MenuIcon.liveColor
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 170))
        content.wantsLayer = true
        content.layer?.cornerRadius = 22
        content.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor

        let badge = NSImageView(image: MenuIcon.badge(loop ? .loopActive : .liveActive, color: color, side: 72))
        badge.frame = NSRect(x: 64, y: 70, width: 72, height: 72)
        content.addSubview(badge)

        let title = NSTextField(labelWithString: loop ? "Loop" : "Live")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        title.textColor = .white
        title.alignment = .center
        title.frame = NSRect(x: 0, y: 34, width: 200, height: 28)
        content.addSubview(title)

        let sub = NSTextField(labelWithString: inUse ? (loop ? "Your call sees the loop" : "Your call sees you live")
                                                     : "No call is using Afterimage")
        sub.font = .systemFont(ofSize: 12)
        sub.textColor = NSColor.white.withAlphaComponent(0.75)
        sub.alignment = .center
        sub.frame = NSRect(x: 0, y: 14, width: 200, height: 18)
        content.addSubview(sub)

        panel.contentView = content
        // Lower middle of the screen with the mouse, where the system's own popups go.
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let f = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: f.midX - 100, y: f.minY + f.height * 0.18))
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hideWork?.cancel()
        let work = DispatchWorkItem { [weak panel] in
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; panel?.animator().alphaValue = 0 },
                                                 completionHandler: { panel?.orderOut(nil) })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 170),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .statusBar
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return p
    }
}
