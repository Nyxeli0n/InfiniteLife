import AppKit

final class PreferencesViewController: NSViewController {
    private let settings: SettingsStore
    private let engine: SimulationEngine

    private var speedPopup: NSPopUpButton!
    private var densityPopup: NSPopUpButton!
    private var presetPopup: NSPopUpButton!
    private var fpsPopup: NSPopUpButton!
    private var loginCheckbox: NSButton!
    private var statusLabel: NSTextField!

    init(settings: SettingsStore, engine: SimulationEngine) {
        self.settings = settings
        self.engine = engine
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) は使用できません")
    }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 420))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.black.cgColor
        view = root

        let title = makeLabel("Infinite Life", size: 15, bold: true)
        let subtitle = makeLabel("モノクロの人工生命ライブ壁紙", size: 11, bold: false)
        subtitle.textColor = NSColor(white: 0.65, alpha: 1)

        speedPopup = makePopup(items: ["遅い", "標準", "速い", "とても速い"])
        densityPopup = makePopup(items: ["少ない", "標準", "多い"])
        presetPopup = makePopup(items: EvolutionPreset.allCases.map(\.displayName))
        fpsPopup = makePopup(items: FrameRateLimit.allCases.map(\.displayName))

        loginCheckbox = NSButton(checkboxWithTitle: "ログイン時に起動", target: self, action: #selector(loginToggled))
        styleCheckbox(loginCheckbox)

        let startButton = makeButton(title: "開始 / 一時停止", action: #selector(toggleRun))
        let newWorldButton = makeButton(title: "新しい世界", action: #selector(newWorld))
        let continueButton = makeButton(title: "前回の世界を続ける", action: #selector(continueWorld))

        statusLabel = makeLabel("", size: 11, bold: false)
        statusLabel.textColor = NSColor(white: 0.55, alpha: 1)

        let stack = NSStackView(views: [
            title,
            subtitle,
            spacer(8),
            labeled("進化速度", speedPopup),
            labeled("セル密度", densityPopup),
            labeled("プリセット", presetPopup),
            labeled("フレームレート", fpsPopup),
            loginCheckbox,
            spacer(6),
            startButton,
            newWorldButton,
            continueButton,
            spacer(8),
            statusLabel
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20)
        ])

        speedPopup.target = self
        speedPopup.action = #selector(controlsChanged)
        densityPopup.target = self
        densityPopup.action = #selector(controlsChanged)
        presetPopup.target = self
        presetPopup.action = #selector(controlsChanged)
        fpsPopup.target = self
        fpsPopup.action = #selector(controlsChanged)

        refreshFromSettings()
    }

    private func refreshFromSettings() {
        let s = settings.snapshot
        switch s.evolutionSpeed {
        case ..<11: speedPopup.selectItem(at: 0)
        case ..<17: speedPopup.selectItem(at: 1)
        case ..<22: speedPopup.selectItem(at: 2)
        default: speedPopup.selectItem(at: 3)
        }
        switch s.cellDensity {
        case ..<0.06: densityPopup.selectItem(at: 0)
        case ..<0.095: densityPopup.selectItem(at: 1)
        default: densityPopup.selectItem(at: 2)
        }
        if let idx = EvolutionPreset.allCases.firstIndex(of: s.preset) {
            presetPopup.selectItem(at: idx)
        }
        if let idx = FrameRateLimit.allCases.firstIndex(of: s.frameRateLimit) {
            fpsPopup.selectItem(at: idx)
        }
        loginCheckbox.state = s.launchAtLogin ? .on : .off
        let seed = s.worldSeed
        statusLabel.stringValue = engine.running
            ? String(format: "実行中 · シード %016llx%016llx", seed.high, seed.low)
            : String(format: "一時停止中 · シード %016llx%016llx", seed.high, seed.low)
    }

    @objc private func controlsChanged() {
        settings.update { s in
            let speeds = [8.0, 14.0, 20.0, 24.0]
            s.evolutionSpeed = speeds[max(0, min(3, speedPopup.indexOfSelectedItem))]
            let dens = [0.045, 0.075, 0.11]
            s.cellDensity = dens[max(0, min(2, densityPopup.indexOfSelectedItem))]
            let presets = EvolutionPreset.allCases
            let pi = max(0, min(presets.count - 1, presetPopup.indexOfSelectedItem))
            s.preset = presets[pi]
            let limits = FrameRateLimit.allCases
            let fi = max(0, min(limits.count - 1, fpsPopup.indexOfSelectedItem))
            s.frameRateLimit = limits[fi]
        }
        engine.applySettings(settings.snapshot)
        refreshFromSettings()
    }

    @objc private func loginToggled() {
        let enabled = loginCheckbox.state == .on
        settings.update { $0.launchAtLogin = enabled }
        LaunchAtLoginManager.setEnabled(enabled)
    }

    @objc private func toggleRun() {
        engine.toggleRunning()
        settings.update { $0.isRunning = engine.running }
        refreshFromSettings()
    }

    @objc private func newWorld() {
        engine.newWorld()
        refreshFromSettings()
    }

    @objc private func continueWorld() {
        if let data = engine.exportWorldState() {
            settings.saveWorldSnapshot(data)
        }
        settings.update { $0.continuePreviousWorld = true }
        engine.continuePreviousWorld()
        refreshFromSettings()
    }


    private func makeLabel(_ text: String, size: CGFloat, bold: Bool) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.textColor = .white
        f.font = bold
            ? NSFont.systemFont(ofSize: size, weight: .medium)
            : NSFont.systemFont(ofSize: size)
        f.backgroundColor = .clear
        f.isBordered = false
        return f
    }

    private func makePopup(items: [String]) -> NSPopUpButton {
        let p = NSPopUpButton(frame: .zero, pullsDown: false)
        p.addItems(withTitles: items)
        p.controlSize = .regular
        return p
    }

    private func makeButton(title: String, action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.bezelStyle = .rounded
        b.setButtonType(.momentaryPushIn)
        return b
    }

    private func styleCheckbox(_ b: NSButton) {
        b.contentTintColor = .white
    }

    private func labeled(_ title: String, _ control: NSView) -> NSView {
        let label = makeLabel(title, size: 11, bold: false)
        label.textColor = NSColor(white: 0.7, alpha: 1)
        let row = NSStackView(views: [label, control])
        row.orientation = .vertical
        row.alignment = .leading
        row.spacing = 2
        control.translatesAutoresizingMaskIntoConstraints = false
        control.widthAnchor.constraint(equalToConstant: 300).isActive = true
        return row
    }

    private func spacer(_ h: CGFloat) -> NSView {
        let v = NSView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalToConstant: h).isActive = true
        return v
    }
}
