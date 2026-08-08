import Foundation

enum IDWInterpolator {
    static let gridSize = 200
    static let innerRadiusMeters: Double = 3.0
    static let outerRadiusMeters: Double = 5.0

    struct Cell {
        var value: Float   // RSSI (dBm), SNR (dB), or channel number — depends on metric
        var alpha: Float
    }

    static func interpolate(
        samples: [WifiSample],
        calibration: Calibration,
        band: WiFiBand,
        imageSize: CGSize,
        outerRadius: Double = outerRadiusMeters,
        metric: HeatmapMetric = .rssi
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
                var nearestChannel = 0

                for s in filtered {
                    let dx = px - s.position.x
                    let dy = py - s.position.y
                    let dist = sqrt(dx * dx + dy * dy)

                    if dist < nearestDist {
                        nearestDist = dist
                        nearestChannel = s.channel
                    }

                    if metric == .channel { continue }

                    if dist < 0.001 {
                        weightSum = 1.0
                        valueSum = metric == .snr ? Double(s.rssi - s.noise) : Double(s.rssi)
                        break
                    }
                    let w = 1.0 / (dist * dist)
                    weightSum += w
                    valueSum += w * (metric == .snr ? Double(s.rssi - s.noise) : Double(s.rssi))
                }

                let cellValue: Float
                if metric == .channel {
                    cellValue = Float(nearestChannel)
                } else {
                    guard weightSum > 0 else { continue }
                    cellValue = Float(valueSum / weightSum)
                }

                let alpha = alphaFor(nearestPixelDist: nearestDist, metersPerPixel: mpp,
                                     outerRadius: outerRadius)
                grid[row][col] = Cell(value: cellValue, alpha: alpha)
            }
        }

        return grid
    }

    private static func alphaFor(nearestPixelDist: Double, metersPerPixel: Double,
                                  outerRadius: Double) -> Float {
        let distMeters = nearestPixelDist * metersPerPixel
        if distMeters <= innerRadiusMeters { return 1.0 }
        if distMeters >= outerRadius { return 0.0 }
        let t = Float((distMeters - innerRadiusMeters) / (outerRadius - innerRadiusMeters))
        return 1.0 - (3 * t * t - 2 * t * t * t)
    }
}
