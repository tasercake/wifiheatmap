import Foundation

struct ScannedNetwork {
    var ssid: String
    var bssid: String
    var rssi: Int
    var noise: Int
    var band: WiFiBand
    var channel: Int
}
