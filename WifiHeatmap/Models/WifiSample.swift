import Foundation

struct WifiNetworkReading: Codable, Equatable {
    var ssid: String
    var bssid: String
    var rssi: Int
    var noise: Int
    var band: WiFiBand
    var channel: Int
}

struct SurveyPoint: Codable, Identifiable, Equatable {
    var id: UUID
    var position: CGPoint
    var startedAt: Date
    var completedAt: Date
    var scanCacheUpdated: Bool
    var snapshotChanged: Bool?
    var attemptCount: Int
    var readings: [WifiNetworkReading]

    var duration: TimeInterval {
        max(0, completedAt.timeIntervalSince(startedAt))
    }

    var bandCount: Int {
        Set(readings.map(\.band)).count
    }
}

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

struct SampleFilter: Equatable {
    let band: WiFiBand
    let ssids: Set<String>
    let bssids: Set<String>

    init(band: WiFiBand, ssids: Set<String>, bssids: Set<String>) {
        self.band = band
        self.ssids = ssids
        self.bssids = bssids
    }

    init(band: WiFiBand, ssid: String?, bssid: String?) {
        self.init(
            band: band,
            ssids: ssid.map { [$0] } ?? [],
            bssids: bssid.map { [$0] } ?? []
        )
    }

    func apply(to samples: [WifiSample]) -> [WifiSample] {
        samples.filter { sample in
            sample.band == band
                && (ssids.isEmpty || ssids.contains(sample.ssid))
                && (bssids.isEmpty || bssids.contains(sample.bssid))
        }
    }

    func apply(to points: [SurveyPoint]) -> [WifiSample] {
        points.compactMap { point in
            let readings = point.readings.filter { reading in
                reading.band == band
                    && (ssids.isEmpty || ssids.contains(reading.ssid))
                    && (bssids.isEmpty || bssids.contains(reading.bssid))
            }
            guard let best = readings.max(by: { $0.rssi < $1.rssi }) else {
                return nil
            }
            return WifiSample(
                id: point.id,
                position: point.position,
                timestamp: point.completedAt,
                ssid: best.ssid,
                bssid: best.bssid,
                rssi: best.rssi,
                noise: best.noise,
                band: best.band,
                channel: best.channel
            )
        }
    }
}
