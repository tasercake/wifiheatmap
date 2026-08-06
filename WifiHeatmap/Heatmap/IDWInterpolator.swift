import Foundation

enum IDWInterpolator {
    static let gridSize = 200
    static let idwMaxRadiusMeters: Double = 5.0

    /// Returns a gridSize×gridSize row-major grid (grid[row][col]) of interpolated RSSI values.
    /// nil means no sample is within idwMaxRadiusMeters of that cell.
    /// Samples are pre-filtered by `band`.
    static func interpolate(
        samples: [WifiSample],
        calibration: Calibration,
        band: WiFiBand
    ) -> [[Float?]] {
        let filtered = samples.filter { $0.band == band }
        guard !filtered.isEmpty else {
            return Array(repeating: Array(repeating: nil, count: gridSize), count: gridSize)
        }

        let mpp = calibration.metersPerPixel
        let maxPx = idwMaxRadiusMeters / mpp  // max radius in pixels

        // Determine the floor plan bounds from samples
        let xs = filtered.map(\.position.x)
        let ys = filtered.map(\.position.y)
        let minX = xs.min()!
        let maxX = xs.max()!
        let minY = ys.min()!
        let maxY = ys.max()!

        // Floor plan coordinates span [minX, maxX] × [minY, maxY]
        // Map this to a gridSize × gridSize grid
        let floorW = max(maxX - minX, 1.0)
        let floorH = max(maxY - minY, 1.0)

        var grid = Array(repeating: Array(repeating: Optional<Float>.none, count: gridSize),
                         count: gridSize)

        for row in 0..<gridSize {
            for col in 0..<gridSize {
                // Map grid cell to floor plan pixel space
                let normCol = gridSize > 1 ? Double(col) / Double(gridSize - 1) : 0.0
                let normRow = gridSize > 1 ? Double(row) / Double(gridSize - 1) : 0.0

                let px = minX + normCol * floorW
                let py = minY + normRow * floorH

                var weightSum: Double = 0
                var valueSum: Double = 0
                var nearestDist = Double.infinity

                for s in filtered {
                    let dx = px - s.position.x
                    let dy = py - s.position.y
                    let dist = sqrt(dx * dx + dy * dy)
                    nearestDist = min(nearestDist, dist)

                    if dist < 0.001 {
                        // Exactly on a sample point
                        weightSum = 1.0
                        valueSum = Double(s.rssi)
                        break
                    }
                    let w = 1.0 / (dist * dist)
                    weightSum += w
                    valueSum += w * Double(s.rssi)
                }

                guard nearestDist <= maxPx, weightSum > 0 else { continue }
                grid[row][col] = Float(valueSum / weightSum)
            }
        }

        return grid
    }
}
