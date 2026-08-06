import Foundation

struct WifiSample: Codable, Identifiable, Equatable {
    var id: UUID
    var position: CGPoint
    var timestamp: Date
    var ssid: String
    var bssid: String
    var rssi: Int    // dBm
    var noise: Int   // dBm
    var band: WiFiBand
}
