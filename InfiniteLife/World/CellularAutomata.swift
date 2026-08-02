import Foundation

enum CellularAutomata {
    static let maxAge: UInt8 = 40

    static let brightnessLUT: [UInt8] = {
        var t = [UInt8](repeating: 0, count: 256)
        for age in 1...Int(maxAge) {
            t[age] = 235
        }
        for age in (Int(maxAge) + 1)..<256 {
            t[age] = 235
        }
        return t
    }()

    static func computeNext(
        chunk: Chunk,
        padded: [UInt8],
        generation: UInt64,
        seed: WorldSeed
    ) -> Int {
        var activity = 0
        let size = Chunk.size
        let stride = size + 2
        for y in 0..<size {
            let py = y + 1
            let row = py * stride
            for x in 0..<size {
                let px = x + 1
                let center = row + px

                var neighbors = 0
                if padded[center - stride - 1] != 0 { neighbors += 1 }
                if padded[center - stride] != 0 { neighbors += 1 }
                if padded[center - stride + 1] != 0 { neighbors += 1 }
                if padded[center - 1] != 0 { neighbors += 1 }
                if padded[center + 1] != 0 { neighbors += 1 }
                if padded[center + stride - 1] != 0 { neighbors += 1 }
                if padded[center + stride] != 0 { neighbors += 1 }
                if padded[center + stride + 1] != 0 { neighbors += 1 }

                let idx = y * size + x
                let current = chunk.cells[idx]
                var next: UInt8 = 0

                if current == 0 {
                    if neighbors == 3 {
                        next = 1
                    }
                } else if neighbors == 2 || neighbors == 3 {
                    let aged = current &+ 1
                    next = aged > maxAge ? maxAge : aged

                    if current >= 14 && staleCellExpires(
                        x: x,
                        y: y,
                        chunk: chunk,
                        generation: generation,
                        seed: seed,
                        oneIn: neighbors == 2 ? 5 : 8
                    ) {
                        next = 0
                    }
                }

                if next != current { activity += 1 }
                chunk.writeNext(idx, next)
            }
        }

        return activity
    }

    private static func staleCellExpires(
        x: Int,
        y: Int,
        chunk: Chunk,
        generation: UInt64,
        seed: WorldSeed,
        oneIn: UInt64
    ) -> Bool {
        let worldX = Int64(chunk.cx) * Int64(Chunk.size) + Int64(x)
        let worldY = Int64(chunk.cy) * Int64(Chunk.size) + Int64(y)
        let h = cellHash(
            worldX: worldX,
            worldY: worldY,
            generation: generation,
            seed: seed,
            salt: 0x4252414E4348
        )
        return h % oneIn == 0
    }

    private static func cellHash(
        worldX: Int64,
        worldY: Int64,
        generation: UInt64,
        seed: WorldSeed,
        salt: UInt64
    ) -> UInt64 {
        var z = seed.high ^ (seed.low &* 0xD6E8FEB86659FD93) ^ salt
        z ^= UInt64(bitPattern: worldX) &* 0xA0761D6478BD642F
        z ^= UInt64(bitPattern: worldY) &* 0xE7037ED1A0B428DB
        z ^= generation &* 0x8EBC6AF09C88C6E3
        return mix(z)
    }

    private static func mix(_ value: UInt64) -> UInt64 {
        var z = value &+ 0x9E3779B97F4A7C15
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

}
