import AppKit

/// ディスプレイごとに壁紙ウインドウとMetalビューを管理する。
final class WallpaperManager {
    private let engine: SimulationEngine
    private var windows: [CGDirectDisplayID: WallpaperWindow] = [:]
    private var views: [CGDirectDisplayID: WallpaperView] = [:]
    private var powerTimer: Timer?
    private var spaceTimer: Timer?

    init(engine: SimulationEngine) {
        self.engine = engine
    }

    func start() {
        rebuildWindows()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        // 電源状態とFPS設定を定期確認する。
        powerTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.engine.updatePowerState()
        }
        // Mission Controlやフルスクリーン切り替え後も背面を維持する。
        spaceTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refreshSpaceVisibility()
        }
        engine.updatePowerState()
    }

    func stop() {
        powerTimer?.invalidate()
        powerTimer = nil
        spaceTimer?.invalidate()
        spaceTimer = nil
        for (_, window) in windows {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        windows.removeAll()
        views.removeAll()
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func screensChanged() {
        rebuildWindows()
    }

    func refreshSpaceVisibility() {
        for (_, window) in windows {
            window.orderFrontRegardless()
            if let screen = window.screen {
                window.setFrame(screen.frame, display: false)
            }
        }
    }

    private func rebuildWindows() {
        let screens = NSScreen.screens
        var live = Set<CGDirectDisplayID>()

        for screen in screens {
            let id = screen.displayID
            live.insert(id)
            if let existing = windows[id] {
                existing.attach(to: screen)
                continue
            }
            let window = WallpaperWindow(screen: screen)
            let view = WallpaperView(engine: engine, frame: window.contentView?.bounds ?? screen.frame)
            view.autoresizingMask = [.width, .height]
            window.contentView = view
            window.orderFrontRegardless()
            windows[id] = window
            views[id] = view
        }

        // 接続解除されたディスプレイを削除する。
        for key in windows.keys where !live.contains(key) {
            windows[key]?.orderOut(nil)
            windows[key]?.close()
            windows.removeValue(forKey: key)
            views.removeValue(forKey: key)
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[key] as? NSNumber)?.uint32Value ?? 0
    }
}
