import Foundation

struct RNG64 {
    private var s0: UInt64
    private var s1: UInt64
    private var s2: UInt64
    private var s3: UInt64

    init(seed: UInt64) {
        var sm = seed
        let a = Self.splitmix(&sm)
        let b = Self.splitmix(&sm)
        let c = Self.splitmix(&sm)
        let d = Self.splitmix(&sm)
        s0 = a
        s1 = b
        s2 = c
        s3 = d
        if s0 | s1 | s2 | s3 == 0 {
            s0 = 1
        }
    }

    mutating func nextUInt64() -> UInt64 {
        let result = Self.rotl(s1 &* 5, 7) &* 9
        let t = s1 << 17
        s2 ^= s0
        s3 ^= s1
        s1 ^= s2
        s0 ^= s3
        s2 ^= t
        s3 = Self.rotl(s3, 45)
        return result
    }

    mutating func nextDouble() -> Double {
        Double(nextUInt64() >> 11) * (1.0 / Double(1 << 53))
    }

    mutating func nextBool(probability: Double) -> Bool {
        nextDouble() < probability
    }

    mutating func nextInt(_ bound: Int) -> Int {
        guard bound > 0 else { return 0 }
        return Int(nextUInt64() % UInt64(bound))
    }

    private static func rotl(_ x: UInt64, _ k: Int) -> UInt64 {
        (x << k) | (x >> (64 - k))
    }

    private static func splitmix(_ z: inout UInt64) -> UInt64 {
        z &+= 0x9E3779B97F4A7C15
        var r = z
        r = (r ^ (r >> 30)) &* 0xBF58476D1CE4E5B9
        r = (r ^ (r >> 27)) &* 0x94D049BB133111EB
        return r ^ (r >> 31)
    }
}
