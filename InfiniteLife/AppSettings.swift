import Foundation

enum EvolutionPreset: String, CaseIterable, Codable {
    case calm
    case balanced
    case chaotic

    var displayName: String {
        switch self {
        case .calm: return "穏やか"
        case .balanced: return "標準"
        case .chaotic: return "活発"
        }
    }
}

enum FrameRateLimit: Int, CaseIterable, Codable {
    case fps30 = 30
    case fps60 = 60
    case auto = 0

    var displayName: String {
        switch self {
        case .fps30: return "30 fps"
        case .fps60: return "60 fps"
        case .auto: return "自動（電源状態に連動）"
        }
    }
}

struct AppSettings: Codable, Equatable {
    var isRunning: Bool = true
    var evolutionSpeed: Double = 14.0
    var cellDensity: Double = 0.075
    var preset: EvolutionPreset = .balanced
    var frameRateLimit: FrameRateLimit = .auto
    var launchAtLogin: Bool = false
    var continuePreviousWorld: Bool = false
    var worldSeedHigh: UInt64 = 0
    var worldSeedLow: UInt64 = 0
    var generation: UInt64 = 0

    static let `default` = AppSettings()

    mutating func applyPreset(_ preset: EvolutionPreset) {
        self.preset = preset
        switch preset {
        case .calm:
            evolutionSpeed = 8.0
            cellDensity = 0.045
        case .balanced:
            evolutionSpeed = 14.0
            cellDensity = 0.075
        case .chaotic:
            evolutionSpeed = 20.0
            cellDensity = 0.11
        }
    }

    var worldSeed: WorldSeed {
        get { WorldSeed(high: worldSeedHigh, low: worldSeedLow) }
        set {
            worldSeedHigh = newValue.high
            worldSeedLow = newValue.low
        }
    }
}
