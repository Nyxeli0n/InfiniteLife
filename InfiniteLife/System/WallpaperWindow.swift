import AppKit

final class WallpaperWindow: NSWindow {
    init(screen: NSScreen) {
        let frame = screen.frame
        super.init(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        configureAsDesktopWallpaper(on: screen)
    }

    private func configureAsDesktopWallpaper(on screen: NSScreen) {
        let wallpaperLevel = Int(CGWindowLevelForKey(.desktopIconWindow)) - 1
        level = NSWindow.Level(rawValue: wallpaperLevel)

        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary
        ]

        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        sharingType = .readOnly

        setFrame(screen.frame, display: true)
        orderFrontRegardless()
    }

    func attach(to screen: NSScreen) {
        setFrame(screen.frame, display: true)
        orderFrontRegardless()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
