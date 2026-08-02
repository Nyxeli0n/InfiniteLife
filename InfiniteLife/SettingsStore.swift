import Foundation

final class SettingsStore {
    static let shared = SettingsStore()

    private let defaults = UserDefaults.standard
    private let settingsKey = "InfiniteLife.settings.v1"
    private let worldKey = "InfiniteLife.world.v1"
    private let algorithmKey = "InfiniteLife.algorithm.version"
    private let algorithmVersion = "conway-endless-v3"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private(set) var settings: AppSettings = .default
    private var worldBlob: Data?

    var snapshot: AppSettings { settings }

    private init() {}

    func load() {
        if let data = defaults.data(forKey: settingsKey),
           let decoded = try? decoder.decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = .default
            settings.applyPreset(.balanced)
            settings.worldSeed = WorldSeed.random()
        }

        worldBlob = defaults.data(forKey: worldKey)
        let needsAlgorithmReset = defaults.string(forKey: algorithmKey) != algorithmVersion

        if settings.worldSeedHigh == 0 && settings.worldSeedLow == 0 {
            settings.worldSeed = WorldSeed.random()
        }

        var shouldResetWorld = needsAlgorithmReset
        if settings.evolutionSpeed < 10.0 || settings.evolutionSpeed > 24.0 {
            settings.evolutionSpeed = 14.0
        }
        if settings.cellDensity < 0.035 || settings.cellDensity > 0.12 {
            settings.cellDensity = 0.075
            shouldResetWorld = true
        }
        if shouldResetWorld {
            settings.continuePreviousWorld = false
            worldBlob = nil
            defaults.removeObject(forKey: worldKey)
            defaults.set(algorithmVersion, forKey: algorithmKey)
        }
    }

    func save() {
        if let data = try? encoder.encode(settings) {
            defaults.set(data, forKey: settingsKey)
        }
    }

    func update(_ mutate: (inout AppSettings) -> Void) {
        mutate(&settings)
        save()
        NotificationCenter.default.post(name: .infiniteLifeSettingsDidChange, object: settings)
    }

    func saveWorldSnapshot(_ data: Data?) {
        worldBlob = data
        if let data {
            defaults.set(data, forKey: worldKey)
        } else {
            defaults.removeObject(forKey: worldKey)
        }
    }

    func loadWorldSnapshot() -> Data? {
        worldBlob ?? defaults.data(forKey: worldKey)
    }

    func clearWorldSnapshot() {
        worldBlob = nil
        defaults.removeObject(forKey: worldKey)
    }
}

extension Notification.Name {
    static let infiniteLifeSettingsDidChange = Notification.Name("InfiniteLife.settingsDidChange")
    static let infiniteLifeEngineStateDidChange = Notification.Name("InfiniteLife.engineStateDidChange")
}
