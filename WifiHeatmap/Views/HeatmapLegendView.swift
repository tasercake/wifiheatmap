import SwiftUI

struct HeatmapLegendView: View {
    let colorScheme: HeatmapColorScheme
    let metric: HeatmapMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(metric.displayName)
                .font(.caption2.bold())
                .foregroundStyle(.white)
            if metric == .channel {
                Text("Colors by channel number")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
            } else {
                gradientBar
                rangeLabels
            }
        }
        .padding(8)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    }

    private var gradientBar: some View {
        LinearGradient(
            colors: gradientColors,
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: 100, height: 12)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private var gradientColors: [Color] {
        let steps = 8
        return (0..<steps).map { i in
            let t = Float(i) / Float(steps - 1)
            let (r, g, b) = sampleGradientColor(t: t)
            return Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
        }
    }

    private func sampleGradientColor(t: Float) -> (UInt8, UInt8, UInt8) {
        let (minV, maxV) = HeatmapRenderer.valueRange(for: metric)
        let value = minV + (maxV - minV) * t
        var grid: [[IDWInterpolator.Cell?]] = Array(
            repeating: Array(repeating: nil, count: IDWInterpolator.gridSize),
            count: IDWInterpolator.gridSize
        )
        grid[0][0] = IDWInterpolator.Cell(value: value, alpha: 1.0)
        guard let img = HeatmapRenderer.render(grid: grid, colorScheme: colorScheme, metric: metric)
        else { return (128, 128, 128) }
        var data = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(
            data: &data, width: 1, height: 1,
            bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return (128, 128, 128) }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return (data[0], data[1], data[2])
    }

    private var rangeLabels: some View {
        let (minV, maxV) = HeatmapRenderer.valueRange(for: metric)
        let unit = metric == .snr ? " dB" : " dBm"
        return HStack {
            Text("\(Int(minV))\(unit)")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.8))
            Spacer()
            Text("\(Int(maxV))\(unit)")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(width: 100)
    }
}
