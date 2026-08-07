import CoreGraphics
import CoreFoundation
import AppKit

enum HeatmapRenderer {
    static let minRSSI: Float = -90
    static let maxRSSI: Float = -50

    /// Returns a gridSize×gridSize RGBA CGImage.
    /// nil cells → alpha = 0 (transparent); non-nil cells → fully opaque.
    static func render(grid: [[Float?]], colorScheme: HeatmapColorScheme = .classic) -> CGImage? {
        let size = IDWInterpolator.gridSize
        let bytesPerRow = size * 4
        let totalBytes = size * bytesPerRow

        guard let mutableData = CFDataCreateMutable(nil, totalBytes) else { return nil }
        CFDataSetLength(mutableData, totalBytes)
        guard let bytes = CFDataGetMutableBytePtr(mutableData) else { return nil }
        let pixels = UnsafeMutableBufferPointer<UInt8>(start: bytes, count: totalBytes)

        for i in 0..<totalBytes { pixels[i] = 0 }

        for row in 0..<size {
            for col in 0..<size {
                guard let rssi = grid[row][col] else { continue }
                let idx = (row * size + col) * 4
                let (r, g, b) = color(for: rssi, scheme: colorScheme)
                pixels[idx]   = r
                pixels[idx+1] = g
                pixels[idx+2] = b
                pixels[idx+3] = 255
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

    private static func color(for rssi: Float, scheme: HeatmapColorScheme) -> (UInt8, UInt8, UInt8) {
        let clamped = max(minRSSI, min(maxRSSI, rssi))
        let t = (clamped - minRSSI) / (maxRSSI - minRSSI)  // 0 = weak, 1 = strong

        switch scheme {
        case .classic:
            // hue 240° (blue, weak) → 0° (red, strong)
            let hue = CGFloat((1.0 - t) * (240.0 / 360.0))
            return hsbToRGB(hue: hue, saturation: 1, brightness: 1)

        case .trafficLight:
            // hue 0° (red, weak) → 120° (green, strong)
            let hue = CGFloat(t * (120.0 / 360.0))
            return hsbToRGB(hue: hue, saturation: 0.9, brightness: 0.85)

        case .colorblindSafe:
            // Okabe-Ito: blue (0,114,178) weak → orange (230,159,0) strong
            let r = UInt8(lerp(0,   230, t))
            let g = UInt8(lerp(114, 159, t))
            let b = UInt8(lerp(178,   0, t))
            return (r, g, b)
        }
    }

    private static func hsbToRGB(hue: CGFloat, saturation: CGFloat, brightness: CGFloat) -> (UInt8, UInt8, UInt8) {
        let c = NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: nil)
        return (UInt8(r * 255), UInt8(g * 255), UInt8(b * 255))
    }

    private static func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
        a + (b - a) * t
    }
}
