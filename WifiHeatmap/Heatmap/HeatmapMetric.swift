enum HeatmapMetric: String, Codable, CaseIterable {
    case rssi
    case snr
    case channel

    var displayName: String {
        switch self {
        case .rssi:    return "RSSI"
        case .snr:     return "SNR"
        case .channel: return "Channel"
        }
    }

    var defaultValueRange: HeatmapValueRange {
        switch self {
        case .rssi: return HeatmapValueRange(lowerBound: -90, upperBound: -20)
        case .snr: return HeatmapValueRange(lowerBound: 0, upperBound: 40)
        case .channel: return HeatmapValueRange(lowerBound: 0, upperBound: 0)
        }
    }
}

struct HeatmapValueRange: Codable, Equatable {
    var lowerBound: Double
    var upperBound: Double

    mutating func setLowerBound(_ value: Double, within limits: ClosedRange<Double>) {
        let clamped = min(max(value, limits.lowerBound), limits.upperBound)
        lowerBound = min(clamped, upperBound - 1)
    }

    mutating func setUpperBound(_ value: Double, within limits: ClosedRange<Double>) {
        let clamped = min(max(value, limits.lowerBound), limits.upperBound)
        upperBound = max(clamped, lowerBound + 1)
    }
}
