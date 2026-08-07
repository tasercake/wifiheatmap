import Foundation

enum IDWInterpolator {
    static let gridSize = 200
    static let innerRadiusMeters: Double = 3.0  // full opacity within this distance
    static let outerRadiusMeters: Double = 5.0  // fades to transparent at this distance

    struct Cell {
        var rssi: Float
        var alpha: Float  // 0 (transparent) → 1 (opaque); driven by distance to nearest sample
    }

    /// Returns a gridSize×gridSize row-major grid (grid[row][col]) of interpolated cells.
    /// nil means no samples exist for this band. Cell.alpha encodes the distance-based mask.
    static func interpolate(
        samples: [WifiSample],
        calibration: Calibration,
        band: WiFiBand,
        imageSize: CGSize
    ) -> [[Cell?]] {
        let filtered = samples.filter { $0.band == band }
        guard !filtered.isEmpty else {
            return Array(repeating: Array(repeating: nil, count: gridSize), count: gridSize)
        }

        let mpp = calibration.metersPerPixel
        var grid = Array(repeating: Array(repeating: Optional<Cell>.none, count: gridSize),
                         count: gridSize)

        for row in 0..<gridSize {
            for col in 0..<gridSize {
                let px = Double(col) / Double(gridSize - 1) * Double(imageSize.width)
                let py = Double(row) / Double(gridSize - 1) * Double(imageSize.height)

                var weightSum: Double = 0
                var valueSum: Double = 0
                var nearestDist = Double.infinity

                for s in filtered {
                    let dx = px - s.position.x
                    let dy = py - s.position.y
                    let dist = sqrt(dx * dx + dy * dy)
                    nearestDist = min(nearestDist, dist)

                    if dist < 0.001 {
                        weightSum = 1.0
                        valueSum = Double(s.rssi)
                        break
                    }
                    let w = 1.0 / (dist * dist)
                    weightSum += w
                    valueSum += w * Double(s.rssi)
                }

                guard weightSum > 0 else { continue }
                let rssi  = Float(valueSum / weightSum)
                let alpha = alphaFor(nearestPixelDist: nearestDist, metersPerPixel: mpp)
                grid[row][col] = Cell(rssi: rssi, alpha: alpha)
            }
        }

        return grid
    }

    // Smooth fade: full opacity within innerRadius, zero at outerRadius, smooth-step in between.
    private static func alphaFor(nearestPixelDist: Double, metersPerPixel: Double) -> Float {
        let distMeters = nearestPixelDist * metersPerPixel
        if distMeters <= innerRadiusMeters { return 1.0 }
        if distMeters >= outerRadiusMeters { return 0.0 }
        let t = Float((distMeters - innerRadiusMeters) / (outerRadiusMeters - innerRadiusMeters))
        return 1.0 - (3 * t * t - 2 * t * t * t)  // smooth step
    }
}
