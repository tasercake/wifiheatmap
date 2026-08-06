import Foundation

enum IDWInterpolator {
    static let gridSize = 200
    static let idwMaxRadiusMeters: Double = 5.0

    /// Returns a gridSize×gridSize row-major grid (grid[row][col]) of interpolated RSSI values.
    /// nil means no sample is within idwMaxRadiusMeters of that cell.
    /// Samples are pre-filtered by `band`.
    /// The grid is mapped over the full `imageSize` pixel space so it aligns with
    /// the floor plan image and sample marker overlays.
    static func interpolate(
        samples: [WifiSample],
        calibration: Calibration,
        band: WiFiBand,
        imageSize: CGSize
    ) -> [[Float?]] {
        let filtered = samples.filter { $0.band == band }
        guard !filtered.isEmpty else {
            return Array(repeating: Array(repeating: nil, count: gridSize), count: gridSize)
        }

        let mpp = calibration.metersPerPixel
        let maxPx = idwMaxRadiusMeters / mpp  // max radius in pixels

        var grid = Array(repeating: Array(repeating: Optional<Float>.none, count: gridSize),
                         count: gridSize)

        for row in 0..<gridSize {
            for col in 0..<gridSize {
                // Map grid cell to full floor plan pixel space
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
