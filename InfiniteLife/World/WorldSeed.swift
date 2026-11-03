import Foundation
import Security

struct WorldSeed: Equatable, Hashable, Codable {
    var high: UInt64
    var low: UInt64

    static func random() -> WorldSeed {
        var high: UInt64 = 0
        var low: UInt64 = 0
        let statusHigh = SecRandomCopyBytes(kSecRandomDefault, MemoryLayout<UInt64>.size, &high)
        let statusLow = SecRandomCopyBytes(kSecRandomDefault, MemoryLayout<UInt64>.size, &low)
        if statusHigh != errSecSuccess || statusLow != errSecSuccess {
            let t = UInt64(Date().timeIntervalSince1970 * 1_000_000)
            high = t ^ (t << 13) ^ UInt64(ProcessInfo.processInfo.processIdentifier)
            low = t &* 0x9E3779B97F4A7C15 &+ 0xD1B54A32D192ED03
        }
        if high == 0 && low == 0 {
            high = 0xA5A5_5A5A_C3C3_3C3C
            low = 0x1234_5678_9ABC_DEF0
        }
        return WorldSeed(high: high, low: low)
    }

    func stream(chunkX: Int32, chunkY: Int32, salt: UInt64 = 0) -> UInt64 {
        var h = high ^ salt
        var l = low &+ UInt64(bitPattern: Int64(chunkX)) &* 0xC2B2AE3D27D4EB4F
        l ^= UInt64(bitPattern: Int64(chunkY)) &* 0x165667B19E3779F9
        h ^= l &+ 0x9E3779B97F4A7C15
        return splitmix64(h &+ l)
    }

    private func splitmix64(_ z0: UInt64) -> UInt64 {
        var z = z0 &+ 0x9E3779B97F4A7C15
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
