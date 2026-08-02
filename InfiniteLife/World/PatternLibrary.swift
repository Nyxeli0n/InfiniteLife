import Foundation

enum PatternLibrary {
    struct Pattern {
        let width: Int
        let height: Int
        let cells: [Bool]
    }

    static let glider = Pattern(
        width: 3, height: 3,
        cells: [
            false, true, false,
            false, false, true,
            true, true, true
        ]
    )

    static let lwss = Pattern(
        width: 5, height: 4,
        cells: [
            false, true, true, true, true,
            true, false, false, false, true,
            false, false, false, false, true,
            true, false, false, true, false
        ]
    )

    static let rPentomino = Pattern(
        width: 3, height: 3,
        cells: [
            false, true, true,
            true, true, false,
            false, true, false
        ]
    )

    static let acorn = Pattern(
        width: 7, height: 3,
        cells: [
            false, true, false, false, false, false, false,
            false, false, false, true, false, false, false,
            true, true, false, false, true, true, true
        ]
    )

    static let diehard = Pattern(
        width: 8, height: 3,
        cells: [
            false, false, false, false, false, false, true, false,
            true, true, false, false, false, false, false, false,
            false, true, false, false, false, true, true, true
        ]
    )

    static let bHeptomino = Pattern(
        width: 4, height: 3,
        cells: [
            true, false, true, true,
            true, true, true, false,
            false, true, false, false
        ]
    )

    static let piHeptomino = Pattern(
        width: 3, height: 3,
        cells: [
            true, true, true,
            true, false, true,
            true, false, true
        ]
    )

    static let queenBee = Pattern(
        width: 7, height: 4,
        cells: [
            false, false, true, true, false, false, false,
            false, true, false, false, true, false, false,
            true, false, false, false, false, true, false,
            false, true, false, false, true, false, false
        ]
    )

    static let smallExploder = Pattern(
        width: 5, height: 4,
        cells: [
            false, true, true, true, false,
            true, false, false, false, true,
            false, false, true, false, false,
            true, false, false, false, true
        ]
    )

    static let switchEngineSeed = Pattern(
        width: 6, height: 4,
        cells: [
            false, true, false, false, true, true,
            true, false, false, false, true, false,
            false, true, false, false, false, false,
            false, false, true, true, true, false
        ]
    )

    static func randomMethuselah(rng: inout RNG64) -> Pattern {
        switch rng.nextInt(9) {
        case 0: return rPentomino
        case 1: return acorn
        case 2: return diehard
        case 3: return bHeptomino
        case 4: return piHeptomino
        case 5: return queenBee
        case 6: return smallExploder
        case 7: return switchEngineSeed
        default: return rPentomino
        }
    }

    static func randomIntruder(rng: inout RNG64) -> Pattern {
        switch rng.nextInt(8) {
        case 0: return glider
        case 1: return lwss
        case 2: return rPentomino
        case 3: return acorn
        case 4: return bHeptomino
        case 5: return piHeptomino
        case 6: return smallExploder
        default: return queenBee
        }
    }

    static func rotated(_ pattern: Pattern, turns: Int) -> Pattern {
        let t = ((turns % 4) + 4) % 4
        if t == 0 { return pattern }
        var current = pattern
        for _ in 0..<t {
            current = rotate90(current)
        }
        return current
    }

    private static func rotate90(_ p: Pattern) -> Pattern {
        var cells = [Bool](repeating: false, count: p.width * p.height)
        for y in 0..<p.height {
            for x in 0..<p.width {
                let v = p.cells[y * p.width + x]
                let nx = p.height - 1 - y
                let ny = x
                cells[ny * p.height + nx] = v
            }
        }
        return Pattern(width: p.height, height: p.width, cells: cells)
    }
}
