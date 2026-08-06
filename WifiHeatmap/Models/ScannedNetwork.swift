import Foundation

struct ScannedNetwork {
    var ssid: String
    var bssid: String
    var rssi: Int    // dBm
    var noise: Int   // dBm
    var band: WiFiBand
}
