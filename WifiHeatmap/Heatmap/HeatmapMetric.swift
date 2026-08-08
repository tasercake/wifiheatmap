enum HeatmapMetric: String, CaseIterable {
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
}
