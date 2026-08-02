import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBar: StatusBarController?
    private var wallpaperManager: WallpaperManager?
    private let settings = SettingsStore.shared
    private let engine = SimulationEngine.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings.load()
        engine.configure(with: settings.snapshot)
        engine.start()

        wallpaperManager = WallpaperManager(engine: engine)
        wallpaperManager?.start()

        statusBar = StatusBarController(
            settings: settings,
            engine: engine,
            wallpaperManager: wallpaperManager
        )
        statusBar?.install()

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceDidChange),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.pause()
        settings.saveWorldSnapshot(engine.exportWorldState())
        settings.save()
        wallpaperManager?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc private func activeSpaceDidChange() {
        wallpaperManager?.refreshSpaceVisibility()
    }
}
