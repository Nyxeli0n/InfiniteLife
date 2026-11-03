import Foundation

final class Chunk {
    static let size: Int = 64
    static let cellCount: Int = size * size

    let cx: Int32
    let cy: Int32

    private(set) var cells: [UInt8]
    private var next: [UInt8]

    private(set) var recentActivity: Double = 0
    private(set) var liveCount: Int = 0
    private(set) var stagnantSteps: Int = 0
    private(set) var lastActivityGeneration: UInt64 = 0

    init(cx: Int32, cy: Int32) {
        self.cx = cx
        self.cy = cy
        self.cells = [UInt8](repeating: 0, count: Chunk.cellCount)
        self.next = [UInt8](repeating: 0, count: Chunk.cellCount)
    }

    @inline(__always)
    func set(_ x: Int, _ y: Int, _ value: UInt8) {
        guard x >= 0, y >= 0, x < Chunk.size, y < Chunk.size else { return }
        cells[y * Chunk.size + x] = value
    }

    func recountLive() {
        var count = 0
        for v in cells where v != 0 { count += 1 }
        liveCount = count
    }

    func stamp(pattern: PatternLibrary.Pattern, originX: Int, originY: Int, age: UInt8 = 1) {
        for py in 0..<pattern.height {
            for px in 0..<pattern.width {
                if pattern.cells[py * pattern.width + px] {
                    let x = originX + px
                    let y = originY + py
                    if x >= 0, y >= 0, x < Chunk.size, y < Chunk.size {
                        if cells[y * Chunk.size + x] == 0 {
                            cells[y * Chunk.size + x] = age
                            liveCount += 1
                        }
                    }
                }
            }
        }
    }

    func commitNext(activity: Int, generation: UInt64) {
        swap(&cells, &next)
        recentActivity = recentActivity * 0.85 + Double(activity) * 0.15
        if activity > 2 {
            stagnantSteps = 0
            lastActivityGeneration = generation
        } else {
            stagnantSteps += 1
        }
        var count = 0
        for v in cells where v != 0 { count += 1 }
        liveCount = count
    }

    func writeNext(_ index: Int, _ value: UInt8) {
        next[index] = value
    }


    func encodeCells() -> Data {
        Data(cells)
    }

    func decodeCells(_ data: Data) {
        guard data.count == Chunk.cellCount else { return }
        cells = [UInt8](data)
        recountLive()
    }
}

struct ChunkKey: Hashable {
    let x: Int32
    let y: Int32
}
