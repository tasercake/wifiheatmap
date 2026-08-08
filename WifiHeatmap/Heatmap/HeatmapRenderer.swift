import CoreGraphics
import CoreFoundation
import AppKit

enum HeatmapRenderer {
    static let minRSSI: Float = -90
    static let maxRSSI: Float = -50

    static func valueRange(for metric: HeatmapMetric) -> (min: Float, max: Float) {
        switch metric {
        case .rssi:    return (minRSSI, maxRSSI)
        case .snr:     return (0, 40)
        case .channel: return (0, 0)
        }
    }

    static func render(
        grid: [[IDWInterpolator.Cell?]],
        colorScheme: HeatmapColorScheme = .classic,
        metric: HeatmapMetric = .rssi
    ) -> CGImage? {
        let size = IDWInterpolator.gridSize
        let bytesPerRow = size * 4
        let totalBytes = size * bytesPerRow

        guard let mutableData = CFDataCreateMutable(nil, totalBytes) else { return nil }
        CFDataSetLength(mutableData, totalBytes)
        guard let bytes = CFDataGetMutableBytePtr(mutableData) else { return nil }
        let pixels = UnsafeMutableBufferPointer<UInt8>(start: bytes, count: totalBytes)

        for i in 0..<totalBytes { pixels[i] = 0 }

        let (rangeMin, rangeMax) = valueRange(for: metric)

        for row in 0..<size {
            for col in 0..<size {
                guard let cell = grid[row][col], cell.alpha > 0 else { continue }
                let idx = (row * size + col) * 4
                let (r, g, b): (UInt8, UInt8, UInt8)
                if metric == .channel {
                    (r, g, b) = channelColor(channel: Int(cell.value))
                } else {
                    (r, g, b) = gradientColor(value: cell.value, min: rangeMin, max: rangeMax,
                                              scheme: colorScheme)
                }
                let a = cell.alpha
                pixels[idx]   = UInt8(Float(r) * a)
                pixels[idx+1] = UInt8(Float(g) * a)
                pixels[idx+2] = UInt8(Float(b) * a)
                pixels[idx+3] = UInt8(a * 255)
            }
        }

        guard let provider = CGDataProvider(data: mutableData) else { return nil }
        return CGImage(
            width: size, height: size,
            bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil, shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    static func gradientColor(value: Float, min: Float, max: Float,
                              scheme: HeatmapColorScheme) -> (UInt8, UInt8, UInt8) {
        let clamped = Swift.max(min, Swift.min(max, value))
        let t = (clamped - min) / (max - min)
        switch scheme {
        case .classic:
            let hue = CGFloat((1.0 - t) * (240.0 / 360.0))
            return hsbToRGB(hue: hue, saturation: 1, brightness: 1)
        case .trafficLight:
            let hue = CGFloat(t * (120.0 / 360.0))
            return hsbToRGB(hue: hue, saturation: 0.9, brightness: 0.85)
        case .colorblindSafe:
            let r = UInt8(lerp(0,   230, t))
            let g = UInt8(lerp(114, 159, t))
            let b = UInt8(lerp(178,   0, t))
            return (r, g, b)
        }
    }

    private static func channelColor(channel: Int) -> (UInt8, UInt8, UInt8) {
        let hue = CGFloat(channel % 12) / 12.0
        return hsbToRGB(hue: hue, saturation: 0.8, brightness: 0.9)
    }

    private static func hsbToRGB(hue: CGFloat, saturation: CGFloat,
                                  brightness: CGFloat) -> (UInt8, UInt8, UInt8) {
        let c = NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: nil)
        return (UInt8(r * 255), UInt8(g * 255), UInt8(b * 255))
    }

    private static func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
        a + (b - a) * t
    }
}
