import Foundation
import CoreGraphics
import AppKit
import CoreVideo
import QuartzCore

final class SimulationEngine {
    static let shared = SimulationEngine()

    private let world: ChunkWorld
    private let camera = CameraController()
    private let activity = ActivityMonitor()
    private let stateLock = NSLock()

    private var settings: AppSettings = .default
    private var isRunning = true
    private var displayLink: CVDisplayLink?
    private var lastTimestamp: Double = 0
    private var evolutionAccumulator: Double = 0
    private var targetFPS: Double = 60
    private var onBattery = false

    private var cellPixelSize: CGFloat = 2.0

    private struct FrameListener {
        var pixelWidth: Int
        var pixelHeight: Int
        let block: (UnsafePointer<UInt8>, Int, Int, CGFloat) -> Void
    }

    private var frameListeners: [UUID: FrameListener] = [:]
    private let listenerLock = NSLock()

    private init() {
        world = ChunkWorld(seed: WorldSeed.random())
        camera.reset(seed: world.seed)
    }

    var running: Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return isRunning
    }

    var currentSettings: AppSettings {
        stateLock.lock(); defer { stateLock.unlock() }
        return settings
    }

    func configure(with settings: AppSettings) {
        stateLock.lock()
        self.settings = settings
        isRunning = settings.isRunning
        activity.configure(seed: settings.worldSeed, density: settings.cellDensity, preset: settings.preset)
        updateCellPixelSizeLocked()
        stateLock.unlock()
        updatePowerState()
    }

    func start() {
        let store = SettingsStore.shared
        let snap = store.snapshot

        if snap.continuePreviousWorld, let data = store.loadWorldSnapshot(),
           world.importSnapshot(data, camera: camera) {
            stateLock.lock()
            settings = snap
            settings.worldSeed = WorldSeed(high: world.seed.high, low: world.seed.low)
            settings.generation = world.generation
            isRunning = snap.isRunning
            activity.configure(seed: settings.worldSeed, density: settings.cellDensity, preset: settings.preset)
            stateLock.unlock()
        } else {
            newWorld(seed: snap.worldSeed.high == 0 && snap.worldSeed.low == 0 ? WorldSeed.random() : snap.worldSeed)
        }

        startDisplayLink()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsChanged(_:)),
            name: .infiniteLifeSettingsDidChange,
            object: nil
        )
    }

    func pause() {
        stateLock.lock()
        isRunning = false
        settings.isRunning = false
        stateLock.unlock()
        NotificationCenter.default.post(name: .infiniteLifeEngineStateDidChange, object: nil)
    }

    func resume() {
        stateLock.lock()
        isRunning = true
        settings.isRunning = true
        lastTimestamp = 0
        stateLock.unlock()
        NotificationCenter.default.post(name: .infiniteLifeEngineStateDidChange, object: nil)
    }

    func toggleRunning() {
        if running { pause() } else { resume() }
    }

    func newWorld(seed: WorldSeed = WorldSeed.random()) {
        stateLock.lock()
        settings.worldSeed = seed
        settings.generation = 0
        settings.continuePreviousWorld = false
        let density = settings.cellDensity
        let preset = settings.preset
        stateLock.unlock()

        world.reset(seed: seed, generation: 0)
        camera.reset(seed: seed)
        activity.configure(seed: seed, density: density, preset: preset)
        SettingsStore.shared.clearWorldSnapshot()
        SettingsStore.shared.update { s in
            s.worldSeed = seed
            s.generation = 0
            s.continuePreviousWorld = false
        }
        NotificationCenter.default.post(name: .infiniteLifeEngineStateDidChange, object: nil)
    }

    func continuePreviousWorld() {
        SettingsStore.shared.update { $0.continuePreviousWorld = true }
        if let data = SettingsStore.shared.loadWorldSnapshot(),
           world.importSnapshot(data, camera: camera) {
            stateLock.lock()
            settings.worldSeed = WorldSeed(high: world.seed.high, low: world.seed.low)
            settings.generation = world.generation
            settings.continuePreviousWorld = true
            activity.configure(seed: settings.worldSeed, density: settings.cellDensity, preset: settings.preset)
            stateLock.unlock()
        }
        NotificationCenter.default.post(name: .infiniteLifeEngineStateDidChange, object: nil)
    }

    func exportWorldState() -> Data? {
        world.exportSnapshot(camera: camera)
    }

    func applySettings(_ newSettings: AppSettings) {
        stateLock.lock()
        settings = newSettings
        activity.configure(seed: world.seed, density: newSettings.cellDensity, preset: newSettings.preset)
        isRunning = newSettings.isRunning
        updateCellPixelSizeLocked()
        stateLock.unlock()
        recomputeTargetFPS()
    }

    // MARK: - フレーム受信先（ディスプレイごとのMetalビュー）

    @discardableResult
    func addFrameListener(_ block: @escaping (UnsafePointer<UInt8>, Int, Int, CGFloat) -> Void) -> UUID {
        let id = UUID()
        listenerLock.lock()
        frameListeners[id] = FrameListener(pixelWidth: 1280, pixelHeight: 800, block: block)
        listenerLock.unlock()
        return id
    }

    func removeFrameListener(_ id: UUID) {
        listenerLock.lock()
        frameListeners.removeValue(forKey: id)
        listenerLock.unlock()
    }

    func resizeFrame(for listenerID: UUID, pixelWidth: Int, pixelHeight: Int) {
        listenerLock.lock()
        if var listener = frameListeners[listenerID] {
            listener.pixelWidth = max(32, pixelWidth)
            listener.pixelHeight = max(32, pixelHeight)
            frameListeners[listenerID] = listener
        }
        listenerLock.unlock()
    }

    // MARK: - ディスプレイリンク

    private func startDisplayLink() {
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let link else { return }
        displayLink = link

        let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, userInfo -> CVReturn in
            guard let userInfo else { return kCVReturnSuccess }
            let engine = Unmanaged<SimulationEngine>.fromOpaque(userInfo).takeUnretainedValue()
            engine.displayTick()
            return kCVReturnSuccess
        }

        let pointer = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(link, callback, pointer)
        CVDisplayLinkStart(link)
    }

    private func stopDisplayLink() {
        if let link = displayLink {
            CVDisplayLinkStop(link)
        }
        displayLink = nil
    }

    private var lastPublishTime: Double = 0

    private func displayTick() {
        let now = CACurrentMediaTime()
        stateLock.lock()
        let runningNow = isRunning
        let fps = targetFPS
        let evoSpeed = settings.evolutionSpeed
        let density = settings.cellDensity
        let cellPx = cellPixelSize
        stateLock.unlock()

        let targets = renderTargets(cellPixelSize: cellPx)
        guard !targets.isEmpty else { return }

        if lastTimestamp == 0 {
            lastTimestamp = now
            return
        }
        var dt = now - lastTimestamp
        lastTimestamp = now
        dt = min(dt, 0.1)

        // フレームレートを制限する。
        let minFrameDt = 1.0 / max(15.0, fps)
        if now - lastPublishTime < minFrameDt * 0.92 {
            return
        }

        let simRects = targets.map { target in
            target.worldRect.insetBy(dx: -Double(Chunk.size), dy: -Double(Chunk.size))
        }
        world.ensureCoverage(worldRects: simRects, density: density)

        if runningNow {
            evolutionAccumulator += dt * evoSpeed

            var steps = 0
            while evolutionAccumulator >= 1.0 && steps < 1 {
                evolutionAccumulator -= 1.0
                steps += 1
            }
            if evolutionAccumulator > 2.0 { evolutionAccumulator = 2.0 }

            for _ in 0..<steps {
                world.step(density: density)
                activity.setGeneration(world.generation)
                activity.tickCooldown()
                let keys = world.allChunkKeys()
                _ = activity.evaluate(world: world, activeKeys: keys)
            }

            stateLock.lock()
            settings.generation = world.generation
            stateLock.unlock()
        }

        for target in targets {
            var buffer = [UInt8](repeating: 0, count: target.width * target.height)
            world.renderToBuffer(
                buffer: &buffer,
                width: target.width,
                height: target.height,
                worldRect: target.worldRect
            )

            buffer.withUnsafeBufferPointer { ptr in
                guard let base = ptr.baseAddress else { return }
                target.block(base, target.width, target.height, cellPx)
            }
        }
        lastPublishTime = now
    }

    private struct RenderTarget {
        let width: Int
        let height: Int
        let worldRect: CGRect
        let block: (UnsafePointer<UInt8>, Int, Int, CGFloat) -> Void
    }

    private func renderTargets(cellPixelSize: CGFloat) -> [RenderTarget] {
        let cellPx = max(4.0, cellPixelSize)
        let maxFieldDimension = 1024

        listenerLock.lock()
        let listeners = Array(frameListeners.values)
        listenerLock.unlock()

        return listeners.compactMap { listener in
            let rawW = max(32, Int((CGFloat(listener.pixelWidth) / cellPx).rounded(.up)))
            let rawH = max(32, Int((CGFloat(listener.pixelHeight) / cellPx).rounded(.up)))
            let scaleDown = max(1.0, Double(max(rawW, rawH)) / Double(maxFieldDimension))
            let width = max(32, Int(Double(rawW) / scaleDown))
            let height = max(32, Int(Double(rawH) / scaleDown))
            let worldRect = camera.visibleWorldRect(cellWidth: width, cellHeight: height)
            return RenderTarget(width: width, height: height, worldRect: worldRect, block: listener.block)
        }
    }

    private func updateCellPixelSizeLocked() {
        switch settings.preset {
        case .calm: cellPixelSize = 16.0
        case .balanced: cellPixelSize = 12.0
        case .chaotic: cellPixelSize = 10.0
        }
    }

    func updatePowerState() {
        onBattery = PowerMonitor.isOnBattery()
        recomputeTargetFPS()
    }

    private func recomputeTargetFPS() {
        stateLock.lock()
        defer { stateLock.unlock() }
        switch settings.frameRateLimit {
        case .fps30:
            targetFPS = 30
        case .fps60:
            targetFPS = 60
        case .auto:
            targetFPS = onBattery ? 30 : 60
        }
    }

    @objc private func settingsChanged(_ note: Notification) {
        guard let s = note.object as? AppSettings else { return }
        applySettings(s)
    }

    deinit {
        stopDisplayLink()
    }
}
