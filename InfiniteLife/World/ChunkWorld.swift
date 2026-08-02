import Foundation
import CoreGraphics

final class ChunkWorld {
    private static let maximumSnapshotBytes = 12 * 1024 * 1024
    private static let maximumSnapshotChunks = 512
    private static let maximumCameraDistance = 1_000_000.0

    private var chunks: [ChunkKey: Chunk] = [:]
    private(set) var seed: WorldSeed
    private(set) var generation: UInt64 = 0

    var loadRadius: Int = 1
    var maxChunks: Int = 256

    private let lock = NSLock()

    init(seed: WorldSeed) {
        self.seed = seed
    }

    func reset(seed: WorldSeed, generation: UInt64 = 0) {
        lock.lock()
        defer { lock.unlock() }
        self.seed = seed
        self.generation = generation
        chunks.removeAll(keepingCapacity: true)
    }

    func chunk(at key: ChunkKey) -> Chunk? {
        lock.lock()
        defer { lock.unlock() }
        return chunks[key]
    }

    func allChunkKeys() -> [ChunkKey] {
        lock.lock()
        defer { lock.unlock() }
        return Array(chunks.keys)
    }

    // MARK: - 手続き型生成

    private func generateChunk(cx: Int32, cy: Int32, density: Double) -> Chunk {
        let chunk = Chunk(cx: cx, cy: cy)
        var rng = RNG64(seed: seed.stream(chunkX: cx, chunkY: cy, salt: 0x47454E))

        let baseEvents = rng.nextDouble() < 0.86 ? 1 : 0
        let extraEvents = rng.nextDouble() < min(0.34, density * 2.8) ? 1 : 0
        let eventCount = baseEvents + extraEvents
        var usedSlots = Set<Int>()

        for i in 0..<eventCount {
            let slot = nextEventSlot(index: i, used: &usedSlots, rng: &rng)
            stampConwayEvent(into: chunk, slot: slot, rng: &rng)
        }

        chunk.recountLive()
        return chunk
    }

    // MARK: - ストリーミング

    /// `worldRect` と周辺を覆うチャンクを用意し、遠いチャンクを破棄する。
    func ensureCoverage(worldRect: CGRect, density: Double) {
        ensureCoverage(worldRects: [worldRect], density: density)
    }

    /// すべての表示領域を覆うチャンクを用意し、遠いチャンクを破棄する。
    func ensureCoverage(worldRects: [CGRect], density: Double) {
        guard !worldRects.isEmpty else { return }

        lock.lock()
        defer { lock.unlock() }

        let s = Double(Chunk.size)
        var needed = Set<ChunkKey>()
        var bounds = worldRects[0]

        for rect in worldRects {
            bounds = bounds.union(rect)

            let minCX = Int32(floor(rect.minX / s)) - Int32(loadRadius)
            let maxCX = Int32(floor(rect.maxX / s)) + Int32(loadRadius)
            let minCY = Int32(floor(rect.minY / s)) - Int32(loadRadius)
            let maxCY = Int32(floor(rect.maxY / s)) + Int32(loadRadius)

            var cx = minCX
            while cx <= maxCX {
                var cy = minCY
                while cy <= maxCY {
                    let key = ChunkKey(x: cx, y: cy)
                    needed.insert(key)
                    if chunks[key] == nil {
                        chunks[key] = generateChunk(cx: cx, cy: cy, density: density)
                    }
                    cy += 1
                }
                cx += 1
            }
        }

        let effectiveMax = max(maxChunks, needed.count)

        // 遠いチャンクから破棄する。
        if chunks.count > effectiveMax {
            let centerX = bounds.midX / s
            let centerY = bounds.midY / s
            let sorted = chunks.keys.sorted { a, b in
                let da = hypot(Double(a.x) - centerX, Double(a.y) - centerY)
                let db = hypot(Double(b.x) - centerX, Double(b.y) - centerY)
                return da > db
            }
            for key in sorted {
                if chunks.count <= effectiveMax { break }
                if !needed.contains(key) {
                    chunks.removeValue(forKey: key)
                }
            }
        }

        // 上限を大きく超える場合は必要領域外をすべて破棄する。
        if chunks.count > effectiveMax * 2 {
            for key in Array(chunks.keys) where !needed.contains(key) {
                chunks.removeValue(forKey: key)
            }
        }
    }

    // MARK: - シミュレーション

    func step(density: Double) {
        lock.lock()
        let keys = Array(chunks.keys)
        let localChunks = chunks
        let cellSnapshots = chunks.mapValues { $0.cells }
        let gen = generation
        let worldSeed = seed
        lock.unlock()

        let s = Chunk.size
        let paddedSize = (s + 2) * (s + 2)
        var padded = [UInt8](repeating: 0, count: paddedSize)
        let stride = s + 2

        var commits: [(Chunk, Int)] = []
        commits.reserveCapacity(keys.count)

        for key in keys {
            guard let chunk = localChunks[key],
                  let currentCells = cellSnapshots[key] else { continue }

            // 世代計算用の連続領域へ、隣接チャンクの境界を複製する。
            for i in 0..<paddedSize { padded[i] = 0 }

            // 内部
            for y in 0..<s {
                let srcRow = y * s
                let dstRow = (y + 1) * stride + 1
                for x in 0..<s {
                    padded[dstRow + x] = currentCells[srcRow + x]
                }
            }

            // 隣接チャンクの境界
            // 上端と下端
            if let north = cellSnapshots[ChunkKey(x: key.x, y: key.y - 1)] {
                let srcRow = (s - 1) * s
                for x in 0..<s {
                    padded[1 + x] = north[srcRow + x]
                }
            }
            if let south = cellSnapshots[ChunkKey(x: key.x, y: key.y + 1)] {
                let dstRow = (s + 1) * stride + 1
                for x in 0..<s {
                    padded[dstRow + x] = south[x]
                }
            }
            // 左端と右端
            if let west = cellSnapshots[ChunkKey(x: key.x - 1, y: key.y)] {
                for y in 0..<s {
                    padded[(y + 1) * stride] = west[y * s + (s - 1)]
                }
            }
            if let east = cellSnapshots[ChunkKey(x: key.x + 1, y: key.y)] {
                for y in 0..<s {
                    padded[(y + 1) * stride + (s + 1)] = east[y * s]
                }
            }
            // 四隅
            if let nw = cellSnapshots[ChunkKey(x: key.x - 1, y: key.y - 1)] {
                padded[0] = nw[(s - 1) * s + (s - 1)]
            }
            if let ne = cellSnapshots[ChunkKey(x: key.x + 1, y: key.y - 1)] {
                padded[s + 1] = ne[(s - 1) * s]
            }
            if let sw = cellSnapshots[ChunkKey(x: key.x - 1, y: key.y + 1)] {
                padded[(s + 1) * stride] = sw[s - 1]
            }
            if let se = cellSnapshots[ChunkKey(x: key.x + 1, y: key.y + 1)] {
                padded[(s + 1) * stride + (s + 1)] = se[0]
            }

            let activity = CellularAutomata.computeNext(
                chunk: chunk,
                padded: padded,
                generation: gen,
                seed: worldSeed
            )
            commits.append((chunk, activity))
        }

        for (chunk, activity) in commits {
            chunk.commitNext(activity: activity, generation: gen)
            cleanAgedResidue(in: chunk, generation: gen, seed: worldSeed)
            energizeIfNeeded(chunk: chunk, density: density, generation: gen, seed: worldSeed)
        }

        lock.lock()
        generation &+= 1
        lock.unlock()
    }

    private func energizeIfNeeded(chunk: Chunk, density: Double, generation: UInt64, seed: WorldSeed) {
        let targetFill = max(0.006, min(0.018, density * 0.22))
        let targetLive = Int(Double(Chunk.cellCount) * targetFill)
        let lowMotion = chunk.liveCount > 0 &&
            chunk.recentActivity < max(3.0, Double(chunk.liveCount) * 0.08) &&
            chunk.stagnantSteps > 24
        let underpopulated = chunk.liveCount < targetLive && chunk.stagnantSteps > 18

        guard chunk.liveCount == 0 || underpopulated || lowMotion else { return }

        var rng = RNG64(seed: seed.stream(
            chunkX: chunk.cx,
            chunkY: chunk.cy,
            salt: generation ^ 0x454E455247495A45
        ))

        if chunk.liveCount > 0 && generation % 17 != UInt64(abs(Int(chunk.cx &+ chunk.cy)) % 17) {
            return
        }

        let deficit = max(8, targetLive - chunk.liveCount)
        let bursts = min(2, max(1, deficit / 96))
        var usedSlots = Set<Int>()
        for _ in 0..<bursts {
            let slot = nextEventSlot(index: Int(generation & 3), used: &usedSlots, rng: &rng)
            stampConwayEvent(into: chunk, slot: slot, rng: &rng)
        }

        chunk.recountLive()
    }

    private func nextEventSlot(index: Int, used: inout Set<Int>, rng: inout RNG64) -> Int {
        for attempt in 0..<4 {
            let candidate = (rng.nextInt(4) + index + attempt) & 3
            if !used.contains(candidate) {
                used.insert(candidate)
                return candidate
            }
        }
        return rng.nextInt(4)
    }

    private func slotBounds(_ slot: Int) -> (minX: Int, minY: Int, width: Int, height: Int) {
        let half = Chunk.size / 2
        let minX = (slot & 1) == 0 ? 4 : half + 2
        let minY = (slot & 2) == 0 ? 4 : half + 2
        return (minX, minY, half - 8, half - 8)
    }

    private func stampConwayEvent(into chunk: Chunk, slot: Int, rng: inout RNG64) {
        let roll = rng.nextDouble()
        if roll < 0.32 {
            stampLocalSoup(into: chunk, slot: slot, rng: &rng)
        } else if roll < 0.56 {
            stampCollision(into: chunk, slot: slot, rng: &rng)
        } else {
            let pattern = PatternLibrary.rotated(
                roll < 0.86
                    ? PatternLibrary.randomMethuselah(rng: &rng)
                    : PatternLibrary.randomIntruder(rng: &rng),
                turns: rng.nextInt(4)
            )
            let b = slotBounds(slot)
            let ox = b.minX + rng.nextInt(max(1, b.width - pattern.width))
            let oy = b.minY + rng.nextInt(max(1, b.height - pattern.height))
            chunk.stamp(pattern: pattern, originX: ox, originY: oy, age: 1)
        }
    }

    private func stampLocalSoup(into chunk: Chunk, slot: Int, rng: inout RNG64) {
        let w = 7 + rng.nextInt(7)
        let h = 7 + rng.nextInt(7)
        let b = slotBounds(slot)
        let ox = b.minX + rng.nextInt(max(1, b.width - w))
        let oy = b.minY + rng.nextInt(max(1, b.height - h))
        let fill = 0.17 + rng.nextDouble() * 0.10

        for y in 0..<h {
            for x in 0..<w {
                let edge = x == 0 || y == 0 || x == w - 1 || y == h - 1
                let p = edge ? fill * 0.45 : fill
                if rng.nextDouble() < p {
                    chunk.set(ox + x, oy + y, 1)
                }
            }
        }
    }

    private func stampCollision(into chunk: Chunk, slot: Int, rng: inout RNG64) {
        let b = slotBounds(slot)
        let cx = b.minX + 8 + rng.nextInt(max(1, b.width - 16))
        let cy = b.minY + 8 + rng.nextInt(max(1, b.height - 16))
        let p1 = PatternLibrary.rotated(PatternLibrary.glider, turns: rng.nextInt(4))
        let p2 = PatternLibrary.rotated(PatternLibrary.glider, turns: (rng.nextInt(4) + 2) % 4)
        let p3 = PatternLibrary.rotated(PatternLibrary.randomMethuselah(rng: &rng), turns: rng.nextInt(4))

        chunk.stamp(pattern: p1, originX: max(0, cx - 7), originY: max(0, cy - 6), age: 1)
        chunk.stamp(pattern: p2, originX: min(Chunk.size - p2.width, cx + 5), originY: min(Chunk.size - p2.height, cy + 4), age: 1)
        if rng.nextBool(probability: 0.45) {
            chunk.stamp(pattern: p3, originX: min(Chunk.size - p3.width, max(0, cx - 2)), originY: min(Chunk.size - p3.height, max(0, cy - 1)), age: 1)
        }
    }

    private func cleanAgedResidue(in chunk: Chunk, generation: UInt64, seed: WorldSeed) {
        guard chunk.liveCount > 0 else { return }
        let phase = Int((generation & 3) * 1021)
        var changed = false

        for idx in 0..<Chunk.cellCount {
            let age = chunk.cells[idx]
            guard age >= 12 else { continue }

            let x = idx % Chunk.size
            let y = idx / Chunk.size
            let key = UInt64(bitPattern: Int64(chunk.cx)) &* 0x9E3779B185EBCA87
                ^ UInt64(bitPattern: Int64(chunk.cy)) &* 0xC2B2AE3D27D4EB4F
                ^ UInt64(idx + phase)
                ^ seed.low

            if key % 13 == 0 {
                chunk.set(x, y, 0)
                changed = true
            }
        }

        if changed {
            chunk.recountLive()
        }
    }

    // MARK: - 描画データ

    /// 表示領域をグレースケールの行優先バッファへ書き出す。
    func renderToBuffer(
        buffer: inout [UInt8],
        width: Int,
        height: Int,
        worldRect: CGRect
    ) {
        guard width > 0, height > 0, buffer.count >= width * height else { return }

        // バッファを初期化する。
        for i in 0..<(width * height) {
            buffer[i] = 0
        }

        lock.lock()
        let snapshot = chunks
        lock.unlock()

        let originX = worldRect.minX
        let invScaleX = Double(width) / worldRect.width
        let invScaleY = Double(height) / worldRect.height
        let s = Chunk.size
        let sd = Double(s)
        let lut = CellularAutomata.brightnessLUT

        // 表示領域と重なるチャンクの生存セルだけを書き込む。
        for (key, chunk) in snapshot {
            let chunkMinX = Double(key.x) * sd
            let chunkMinY = Double(key.y) * sd
            let chunkMaxX = chunkMinX + sd
            let chunkMaxY = chunkMinY + sd

            if chunkMaxX < worldRect.minX || chunkMinX > worldRect.maxX ||
                chunkMaxY < worldRect.minY || chunkMinY > worldRect.maxY {
                continue
            }

            let cells = chunk.cells
            for ly in 0..<s {
                let worldY = chunkMinY + Double(ly) + 0.5
                // 画面上端をワールド座標の最大Yとする。
                let py = Int((worldRect.maxY - worldY) * invScaleY)
                guard py >= 0, py < height else { continue }
                let row = py * width
                let srcRow = ly * s
                for lx in 0..<s {
                    let age = cells[srcRow + lx]
                    if age == 0 { continue }
                    let worldX = chunkMinX + Double(lx) + 0.5
                    let px = Int((worldX - originX) * invScaleX)
                    if px >= 0 && px < width {
                        buffer[row + px] = lut[Int(age)]
                    }
                }
            }
        }
    }

    // MARK: - 状態保存

    struct Snapshot: Codable {
        var seedHigh: UInt64
        var seedLow: UInt64
        var generation: UInt64
        var cameraX: Double
        var cameraY: Double
        var chunks: [PersistedChunk]
    }

    struct PersistedChunk: Codable {
        var cx: Int32
        var cy: Int32
        var cells: Data
    }

    func exportSnapshot(camera: CameraController) -> Data? {
        lock.lock()
        let seed = self.seed
        let gen = generation
        let exported = chunks.map { key, chunk in
            PersistedChunk(cx: key.x, cy: key.y, cells: chunk.encodeCells())
        }
        lock.unlock()

        let cam = camera.export()
        let snap = Snapshot(
            seedHigh: seed.high,
            seedLow: seed.low,
            generation: gen,
            cameraX: cam.x,
            cameraY: cam.y,
            chunks: exported
        )
        return try? JSONEncoder().encode(snap)
    }

    func importSnapshot(_ data: Data, camera: CameraController) -> Bool {
        guard data.count <= Self.maximumSnapshotBytes,
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data),
              snap.chunks.count <= Self.maximumSnapshotChunks,
              snap.cameraX.isFinite,
              snap.cameraY.isFinite,
              abs(snap.cameraX) <= Self.maximumCameraDistance,
              abs(snap.cameraY) <= Self.maximumCameraDistance else {
            return false
        }

        var restoredChunks: [ChunkKey: Chunk] = [:]
        restoredChunks.reserveCapacity(snap.chunks.count)
        for persisted in snap.chunks {
            guard persisted.cells.count == Chunk.cellCount else { return false }
            let key = ChunkKey(x: persisted.cx, y: persisted.cy)
            guard restoredChunks[key] == nil else { return false }

            let chunk = Chunk(cx: persisted.cx, cy: persisted.cy)
            chunk.decodeCells(persisted.cells)
            restoredChunks[key] = chunk
        }

        lock.lock()
        seed = WorldSeed(high: snap.seedHigh, low: snap.seedLow)
        generation = snap.generation
        chunks = restoredChunks
        lock.unlock()
        camera.restore(x: snap.cameraX, y: snap.cameraY)
        return true
    }
}
