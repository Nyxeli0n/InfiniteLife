import AppKit

final class StatusBarController {
    private let statusItem: NSStatusItem
    private let settings: SettingsStore
    private let engine: SimulationEngine
    private weak var wallpaperManager: WallpaperManager?
    private var preferencesWindow: NSWindow?

    init(settings: SettingsStore, engine: SimulationEngine, wallpaperManager: WallpaperManager?) {
        self.settings = settings
        self.engine = engine
        self.wallpaperManager = wallpaperManager
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    }

    func install() {
        if let button = statusItem.button {
            if let image = NSImage(systemSymbolName: "circle.grid.3x3", accessibilityDescription: "Infinite Life") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "IL"
            }
            button.toolTip = "Infinite Life"
        }
        rebuildMenu()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(rebuildMenu),
            name: .infiniteLifeSettingsDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(rebuildMenu),
            name: .infiniteLifeEngineStateDidChange,
            object: nil
        )
    }

    @objc private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let s = settings.snapshot
        let running = engine.running

        let playItem = NSMenuItem(
            title: running ? "一時停止" : "開始",
            action: #selector(toggleRun),
            keyEquivalent: ""
        )
        playItem.target = self
        menu.addItem(playItem)
        menu.addItem(.separator())

        let evo = NSMenuItem(title: "進化速度", action: nil, keyEquivalent: "")
        let evoSub = NSMenu()
        for (title, value) in [("遅い", 8.0), ("標準", 14.0), ("速い", 20.0), ("とても速い", 24.0)] {
            let item = NSMenuItem(title: title, action: #selector(setEvolutionSpeed(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value
            item.state = abs(s.evolutionSpeed - value) < 0.1 ? .on : .off
            evoSub.addItem(item)
        }
        evo.submenu = evoSub
        menu.addItem(evo)

        let dens = NSMenuItem(title: "セル密度", action: nil, keyEquivalent: "")
        let densSub = NSMenu()
        for (title, value) in [("少ない", 0.045), ("標準", 0.075), ("多い", 0.11)] {
            let item = NSMenuItem(title: title, action: #selector(setDensity(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value
            item.state = abs(s.cellDensity - value) < 0.005 ? .on : .off
            densSub.addItem(item)
        }
        dens.submenu = densSub
        menu.addItem(dens)

        let preset = NSMenuItem(title: "プリセット", action: nil, keyEquivalent: "")
        let presetSub = NSMenu()
        for p in EvolutionPreset.allCases {
            let item = NSMenuItem(title: p.displayName, action: #selector(setPreset(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = p.rawValue
            item.state = s.preset == p ? .on : .off
            presetSub.addItem(item)
        }
        preset.submenu = presetSub
        menu.addItem(preset)

        menu.addItem(.separator())

        let newWorld = NSMenuItem(title: "新しい世界", action: #selector(newWorldAction), keyEquivalent: "")
        newWorld.target = self
        menu.addItem(newWorld)

        let cont = NSMenuItem(title: "前回の世界を続ける", action: #selector(continueWorldAction), keyEquivalent: "")
        cont.target = self
        cont.state = s.continuePreviousWorld ? .on : .off
        menu.addItem(cont)

        menu.addItem(.separator())

        let fps = NSMenuItem(title: "フレームレート上限", action: nil, keyEquivalent: "")
        let fpsSub = NSMenu()
        for limit in FrameRateLimit.allCases {
            let item = NSMenuItem(title: limit.displayName, action: #selector(setFPS(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = limit.rawValue
            item.state = s.frameRateLimit == limit ? .on : .off
            fpsSub.addItem(item)
        }
        fps.submenu = fpsSub
        menu.addItem(fps)

        let login = NSMenuItem(
            title: "ログイン時に起動",
            action: #selector(toggleLogin),
            keyEquivalent: ""
        )
        login.target = self
        login.state = (s.launchAtLogin || LaunchAtLoginManager.isEnabled) ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())

        let prefs = NSMenuItem(title: "設定…", action: #selector(openPreferences), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "終了", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }


    @objc private func toggleRun() {
        engine.toggleRunning()
        settings.update { $0.isRunning = engine.running }
        rebuildMenu()
    }

    @objc private func setEvolutionSpeed(_ sender: NSMenuItem) {
        guard let v = sender.representedObject as? Double else { return }
        settings.update { $0.evolutionSpeed = v }
        engine.applySettings(settings.snapshot)
        rebuildMenu()
    }

    @objc private func setDensity(_ sender: NSMenuItem) {
        guard let v = sender.representedObject as? Double else { return }
        settings.update { $0.cellDensity = v }
        engine.applySettings(settings.snapshot)
        rebuildMenu()
    }

    @objc private func setPreset(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let p = EvolutionPreset(rawValue: raw) else { return }
        settings.update { $0.applyPreset(p) }
        engine.applySettings(settings.snapshot)
        rebuildMenu()
    }

    @objc private func newWorldAction() {
        engine.newWorld()
        rebuildMenu()
    }

    @objc private func continueWorldAction() {
        settings.update { $0.continuePreviousWorld = true }
        if let data = engine.exportWorldState() {
            settings.saveWorldSnapshot(data)
        }
        engine.continuePreviousWorld()
        rebuildMenu()
    }

    @objc private func setFPS(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? Int,
              let limit = FrameRateLimit(rawValue: raw) else { return }
        settings.update { $0.frameRateLimit = limit }
        engine.applySettings(settings.snapshot)
        rebuildMenu()
    }

    @objc private func toggleLogin() {
        let next = !settings.snapshot.launchAtLogin
        settings.update { $0.launchAtLogin = next }
        LaunchAtLoginManager.setEnabled(next)
        rebuildMenu()
    }

    @objc private func openPreferences() {
        if preferencesWindow == nil {
            let vc = PreferencesViewController(settings: settings, engine: engine)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 420),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.contentViewController = vc
            window.title = "Infinite Life"
            window.backgroundColor = NSColor.black
            window.isReleasedWhenClosed = false
            window.center()
            preferencesWindow = window
        }
        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        if let data = engine.exportWorldState() {
            settings.saveWorldSnapshot(data)
        }
        settings.save()
        NSApp.terminate(nil)
    }
}
