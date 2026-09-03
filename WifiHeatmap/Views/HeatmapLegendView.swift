import SwiftUI

struct HeatmapLegendView: View {
    let colorScheme: HeatmapColorScheme
    let metric: HeatmapMetric
    let valueRange: HeatmapValueRange

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
        let minV = Float(valueRange.lowerBound)
        let maxV = Float(valueRange.upperBound)
        let value = minV + (maxV - minV) * t
        return HeatmapRenderer.gradientColor(value: value, min: minV, max: maxV, scheme: colorScheme)
    }

    private var rangeLabels: some View {
        let minV = valueRange.lowerBound
        let maxV = valueRange.upperBound
        let unit = metric == .snr ? " dB" : " dBm"
        return HStack {
            Text("\(minV, specifier: "%.0f")\(unit)")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.8))
            Spacer()
            Text("\(maxV, specifier: "%.0f")\(unit)")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(width: 100)
    }
}
