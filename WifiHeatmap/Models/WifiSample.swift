import Foundation

struct WifiSample: Codable, Identifiable, Equatable {
    var id: UUID
    var position: CGPoint
    var timestamp: Date
    var ssid: String
    var bssid: String
    var rssi: Int
    var noise: Int
    var band: WiFiBand
    var channel: Int

    enum CodingKeys: String, CodingKey {
        case id, position, timestamp, ssid, bssid, rssi, noise, band, channel
    }

    init(id: UUID, position: CGPoint, timestamp: Date, ssid: String, bssid: String,
         rssi: Int, noise: Int, band: WiFiBand, channel: Int = 0) {
        self.id = id; self.position = position; self.timestamp = timestamp
        self.ssid = ssid; self.bssid = bssid; self.rssi = rssi
        self.noise = noise; self.band = band; self.channel = channel
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decode(UUID.self,     forKey: .id)
        position  = try c.decode(CGPoint.self,  forKey: .position)
        timestamp = try c.decode(Date.self,     forKey: .timestamp)
        ssid      = try c.decode(String.self,   forKey: .ssid)
        bssid     = try c.decode(String.self,   forKey: .bssid)
        rssi      = try c.decode(Int.self,      forKey: .rssi)
        noise     = try c.decode(Int.self,      forKey: .noise)
        band      = try c.decode(WiFiBand.self, forKey: .band)
        channel   = try c.decodeIfPresent(Int.self, forKey: .channel) ?? 0
    }
}
