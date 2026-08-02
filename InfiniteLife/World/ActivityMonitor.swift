import Foundation

final class ActivityMonitor {
    private var seed: WorldSeed = WorldSeed(high: 1, low: 1)
    private var density: Double = 0.06
    private var preset: EvolutionPreset = .balanced
    private var generation: UInt64 = 0

    private var globalCooldown: Int = 0

    func configure(seed: WorldSeed, density: Double, preset: EvolutionPreset) {
        self.seed = seed
        self.density = density
        self.preset = preset
    }

    func setGeneration(_ g: UInt64) {
        generation = g
    }

    func tickCooldown() {
        if globalCooldown > 0 { globalCooldown -= 1 }
    }

    @discardableResult
    func evaluate(world: ChunkWorld, activeKeys: [ChunkKey]) -> Int {
        guard globalCooldown == 0 else { return 0 }

        let targetLive = Int(Double(Chunk.cellCount) * max(0.004, min(0.020, density * 0.20)))
        let maxInterventions = preset == .chaotic ? 3 : 2

        let candidates = activeKeys.compactMap { key -> (ChunkKey, Chunk, Double)? in
            guard let chunk = world.chunk(at: key) else { return nil }
            let tooQuiet = chunk.liveCount < targetLive && chunk.stagnantSteps > 16
            let stagnant = chunk.liveCount > 0 &&
                chunk.recentActivity < max(2.0, Double(chunk.liveCount) * 0.055) &&
                chunk.stagnantSteps > 30
            guard chunk.liveCount == 0 || tooQuiet || stagnant else { return nil }

            let score = Double(chunk.liveCount)
                + chunk.recentActivity * 0.45
                - Double(min(chunk.stagnantSteps, 80)) * 0.22
            return (key, chunk, score)
        }
        .sorted { lhs, rhs in
            if lhs.2 == rhs.2 {
                if lhs.0.y == rhs.0.y { return lhs.0.x < rhs.0.x }
                return lhs.0.y < rhs.0.y
            }
            return lhs.2 < rhs.2
        }

        var interventions = 0
        for (key, chunk, _) in candidates.prefix(maxInterventions) {
            var localRng = RNG64(seed: seed.stream(
                chunkX: key.x,
                chunkY: key.y,
                salt: generation ^ UInt64(interventions) ^ 0x42414C414E4345
            ))
            injectBalancedEvent(into: chunk, key: key, rng: &localRng)
            chunk.recountLive()
            interventions += 1
        }

        if interventions > 0 {
            globalCooldown = preset == .chaotic ? 14 : (preset == .calm ? 38 : 24)
        }
        return interventions
    }

    private func injectBalancedEvent(into chunk: Chunk, key: ChunkKey, rng: inout RNG64) {
        let slot = Int((Int64(key.x) &* 3 &+ Int64(key.y) &* 5 &+ Int64(generation / 23)) & 3)
        let bounds = slotBounds(slot)
        let roll = rng.nextDouble()
        if roll < 0.28 {
            injectSoup(into: chunk, bounds: bounds, rng: &rng)
        } else if roll < 0.62 {
            injectMethuselah(into: chunk, bounds: bounds, rng: &rng)
        } else {
            injectIntruder(into: chunk, bounds: bounds, rng: &rng)
        }
    }

    private func slotBounds(_ slot: Int) -> (minX: Int, minY: Int, width: Int, height: Int) {
        let half = Chunk.size / 2
        let minX = (slot & 1) == 0 ? 4 : half + 2
        let minY = (slot & 2) == 0 ? 4 : half + 2
        return (minX, minY, half - 8, half - 8)
    }

    private func injectSoup(into chunk: Chunk, bounds: (minX: Int, minY: Int, width: Int, height: Int), rng: inout RNG64) {
        let w = 7 + rng.nextInt(6)
        let h = 7 + rng.nextInt(6)
        let ox = bounds.minX + rng.nextInt(max(1, bounds.width - w))
        let oy = bounds.minY + rng.nextInt(max(1, bounds.height - h))
        let fill = 0.16 + rng.nextDouble() * 0.09

        for y in 0..<h {
            for x in 0..<w where rng.nextDouble() < fill {
                chunk.set(ox + x, oy + y, 1)
            }
        }
    }

    private func injectMethuselah(into chunk: Chunk, bounds: (minX: Int, minY: Int, width: Int, height: Int), rng: inout RNG64) {
        let pattern = PatternLibrary.rotated(
            PatternLibrary.randomMethuselah(rng: &rng),
            turns: rng.nextInt(4)
        )
        let ox = bounds.minX + rng.nextInt(max(1, bounds.width - pattern.width))
        let oy = bounds.minY + rng.nextInt(max(1, bounds.height - pattern.height))
        chunk.stamp(pattern: pattern, originX: ox, originY: oy, age: 1)
    }

    private func injectIntruder(into chunk: Chunk, bounds: (minX: Int, minY: Int, width: Int, height: Int), rng: inout RNG64) {
        let pattern = PatternLibrary.rotated(
            PatternLibrary.randomIntruder(rng: &rng),
            turns: rng.nextInt(4)
        )
        let ox = bounds.minX + rng.nextInt(max(1, bounds.width - pattern.width))
        let oy = bounds.minY + rng.nextInt(max(1, bounds.height - pattern.height))
        chunk.stamp(pattern: pattern, originX: ox, originY: oy, age: 1)
    }

}
