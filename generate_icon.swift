#!/usr/bin/env swift
import Cocoa

// Classic heatmap colormap: 0=blue, 1=red
func heatmapRGB(t: Float) -> (Float, Float, Float) {
    let t = max(0, min(1, t))
    if t < 0.25 {
        let s = t / 0.25
        return (0, s, 1)
    } else if t < 0.5 {
        let s = (t - 0.25) / 0.25
        return (0, 1, 1 - s)
    } else if t < 0.75 {
        let s = (t - 0.5) / 0.25
        return (s, 1, 0)
    } else {
        let s = (t - 0.75) / 0.25
        return (1, 1 - s, 0)
    }
}

// Sources: (cx, cy, strength, sigma) — all in [0,1] relative coords
// Arranged so there's a clear hot zone (upper-right) fading to cool (lower-left)
let sources: [(Float, Float, Float, Float)] = [
    (0.68, 0.28, 1.00, 0.28),  // primary hotspot, upper-right
    (0.78, 0.68, 0.82, 0.20),  // secondary warm, lower-right
    (0.88, 0.44, 0.75, 0.15),  // warm accent, far right
    (0.46, 0.46, 0.58, 0.24),  // medium center
    (0.22, 0.62, 0.38, 0.20),  // cool-ish, lower-left
    (0.18, 0.22, 0.28, 0.18),  // cold, upper-left
]

func generateIcon(size: Int) -> NSBitmapImageRep? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: size * 4,
        bitsPerPixel: 32
    ), let pixels = rep.bitmapData else { return nil }

    // Dark navy background
    let bgR: Float = 0.055, bgG: Float = 0.063, bgB: Float = 0.094

    for y in 0..<size {
        for x in 0..<size {
            let fx = Float(x) / Float(size - 1)
            let fy = Float(y) / Float(size - 1)

            // Max-Gaussian heat from all sources
            var heat: Float = 0
            for (sx, sy, strength, sigma) in sources {
                let dx = fx - sx
                let dy = fy - sy
                let d2 = dx*dx + dy*dy
                let contrib = strength * exp(-d2 / (2 * sigma * sigma))
                heat = max(heat, contrib)
            }
            heat = min(heat, 1.0)

            // Map heat to heatmap color
            let (hr, hg, hb) = heatmapRGB(t: heat)

            // Alpha-composite heatmap over dark background (nonlinear for glow)
            let alpha = pow(heat, 0.55)
            let finalR = bgR + (hr - bgR) * alpha
            let finalG = bgG + (hg - bgG) * alpha
            let finalB = bgB + (hb - bgB) * alpha

            let i = (y * size + x) * 4
            pixels[i + 0] = UInt8(max(0, min(255, finalR * 255)))
            pixels[i + 1] = UInt8(max(0, min(255, finalG * 255)))
            pixels[i + 2] = UInt8(max(0, min(255, finalB * 255)))
            pixels[i + 3] = 255
        }
    }

    return rep
}

let outDir = "/Users/jhludwig/ws/git/wifiheatmap/WifiHeatmap/Assets.xcassets/AppIcon.appiconset"
let sizes = [16, 32, 64, 128, 256, 512, 1024]

for size in sizes {
    guard let rep = generateIcon(size: size),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("FAILED \(size)x\(size)")
        continue
    }
    let path = "\(outDir)/icon_\(size)x\(size).png"
    try! png.write(to: URL(fileURLWithPath: path))
    print("OK \(size)x\(size)")
}
print("Done.")
