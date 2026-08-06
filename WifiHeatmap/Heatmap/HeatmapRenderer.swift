import CoreGraphics
import CoreFoundation
import AppKit

enum HeatmapRenderer {
    static let minRSSI: Float = -90
    static let maxRSSI: Float = -50

    /// Returns a gridSize×gridSize RGBA CGImage
    /// nil cells → alpha = 0 (transparent)
    /// non-nil cells → fully opaque, color mapped via HSB hue
    static func render(grid: [[Float?]]) -> CGImage? {
        let size = IDWInterpolator.gridSize
        let bytesPerRow = size * 4
        let totalBytes = size * bytesPerRow

        // Allocate mutable data buffer
        guard let mutableData = CFDataCreateMutable(nil, totalBytes) else { return nil }
        CFDataSetLength(mutableData, totalBytes)

        guard let bytes = CFDataGetMutableBytePtr(mutableData) else { return nil }
        let pixels = UnsafeMutableBufferPointer<UInt8>(
            start: bytes,
            count: totalBytes
        )

        // Initialize all pixels to transparent (alpha = 0)
        for i in 0..<totalBytes {
            pixels[i] = 0
        }

        // Fill in data cells with color
        for row in 0..<size {
            for col in 0..<size {
                guard let rssi = grid[row][col] else { continue }
                let idx = (row * size + col) * 4
                let (r, g, b) = color(for: rssi)
                pixels[idx]   = r
                pixels[idx+1] = g
                pixels[idx+2] = b
                pixels[idx+3] = 255
            }
        }

        // Create CGImage from mutable data
        guard let provider = CGDataProvider(data: mutableData) else { return nil }
        let image = CGImage(
            width: size, height: size,
            bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil, shouldInterpolate: false,
            intent: .defaultIntent
        )

        return image
    }

    // Maps dBm → (R, G, B) by linearly interpolating hue from 240° (blue) to 0° (red)
    private static func color(for rssi: Float) -> (UInt8, UInt8, UInt8) {
        let clamped = max(minRSSI, min(maxRSSI, rssi))
        let t = CGFloat((clamped - minRSSI) / (maxRSSI - minRSSI))  // 0 = blue, 1 = red
        let hue = (1.0 - t) * (240.0 / 360.0)
        let c = NSColor(hue: hue, saturation: 1, brightness: 1, alpha: 1)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: nil)
        return (UInt8(r * 255), UInt8(g * 255), UInt8(b * 255))
    }
}
