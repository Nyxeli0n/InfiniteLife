import Foundation
import CoreGraphics

final class CameraController {
    private(set) var x: Double = 0
    private(set) var y: Double = 0

    func reset(startX: Double = 0, startY: Double = 0) {
        x = startX
        y = startY
    }

    func restore(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    func export() -> (x: Double, y: Double) {
        (x, y)
    }

    func visibleWorldRect(cellWidth: Int, cellHeight: Int) -> CGRect {
        let cellsW = Double(max(1, cellWidth))
        let cellsH = Double(max(1, cellHeight))
        let minX = floor(x - cellsW * 0.5)
        let minY = floor(y - cellsH * 0.5)
        return CGRect(
            x: minX,
            y: minY,
            width: cellsW,
            height: cellsH
        )
    }
}
