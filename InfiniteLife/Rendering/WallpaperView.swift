import AppKit
import MetalKit

final class WallpaperView: MTKView {
    private var renderer: MetalRenderer?
    private var listenerID: UUID?
    private let engine: SimulationEngine
    private var lastDrawablePixelSize: (Int, Int) = (0, 0)

    init(engine: SimulationEngine, frame: CGRect) {
        self.engine = engine
        super.init(frame: frame, device: MTLCreateSystemDefaultDevice())
        commonInit()
    }

    required init(coder: NSCoder) {
        self.engine = SimulationEngine.shared
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        guard let device else {
            NSLog("InfiniteLife: Metalデバイスが見つかりません")
            return
        }
        self.device = device
        self.colorPixelFormat = .bgra8Unorm
        self.framebufferOnly = true
        self.isPaused = true
        self.enableSetNeedsDisplay = true
        self.autoResizeDrawable = true
        self.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        self.preferredFramesPerSecond = 60

        renderer = MetalRenderer(device: device)

        listenerID = engine.addFrameListener { [weak self] ptr, w, h, _ in
            self?.onFrame(ptr: ptr, width: w, height: h)
        }
    }

    deinit {
        if let listenerID {
            engine.removeFrameListener(listenerID)
        }
    }

    private func onFrame(ptr: UnsafePointer<UInt8>, width: Int, height: Int) {
        let count = width * height
        let data = Data(bytes: ptr, count: count)
        DispatchQueue.main.async { [weak self] in
            guard let self, let renderer = self.renderer else { return }
            data.withUnsafeBytes { raw in
                guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
                renderer.upload(cells: base, width: width, height: height)
            }
            self.draw()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        renderer?.draw(in: self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reportSize()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        reportSize()
    }

    private func reportSize() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        let pointsW = max(1, bounds.width)
        let pointsH = max(1, bounds.height)
        let pixelW = max(32, Int((pointsW * scale).rounded(.up)))
        let pixelH = max(32, Int((pointsH * scale).rounded(.up)))
        if (pixelW, pixelH) != lastDrawablePixelSize, let listenerID {
            lastDrawablePixelSize = (pixelW, pixelH)
            engine.resizeFrame(for: listenerID, pixelWidth: pixelW, pixelHeight: pixelH)
        }
    }
}
