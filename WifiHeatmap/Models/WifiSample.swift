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
    var orientationDegrees: Double?
    var startedAt: Date
    var completedAt: Date
    var scanCacheUpdated: Bool
    var snapshotChanged: Bool?
    var attemptCount: Int
    var readings: [WifiNetworkReading]

    init(
        id: UUID,
        position: CGPoint,
        orientationDegrees: Double? = nil,
        startedAt: Date,
        completedAt: Date,
        scanCacheUpdated: Bool,
        snapshotChanged: Bool?,
        attemptCount: Int,
        readings: [WifiNetworkReading]
    ) {
        self.id = id
        self.position = position
        self.orientationDegrees = orientationDegrees
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.scanCacheUpdated = scanCacheUpdated
        self.snapshotChanged = snapshotChanged
        self.attemptCount = attemptCount
        self.readings = readings
    }

    private enum CodingKeys: String, CodingKey {
        case id, position, orientationDegrees, startedAt, completedAt
        case scanCacheUpdated, snapshotChanged, attemptCount, readings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        position = try container.decode(CGPoint.self, forKey: .position)
        orientationDegrees = try container.decodeIfPresent(Double.self, forKey: .orientationDegrees)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        completedAt = try container.decode(Date.self, forKey: .completedAt)
        scanCacheUpdated = try container.decode(Bool.self, forKey: .scanCacheUpdated)
        snapshotChanged = try container.decodeIfPresent(Bool.self, forKey: .snapshotChanged)
        attemptCount = try container.decode(Int.self, forKey: .attemptCount)
        readings = try container.decode([WifiNetworkReading].self, forKey: .readings)
    }

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
    let ssid: String?
    let bssids: Set<String>

    init(band: WiFiBand, ssid: String?, bssids: Set<String>) {
        self.band = band
        self.ssid = ssid
        self.bssids = bssids
    }

    init(band: WiFiBand, ssid: String?, bssid: String?) {
        self.init(
            band: band,
            ssid: ssid,
            bssids: bssid.map { [$0] } ?? []
        )
    }

    func apply(to samples: [WifiSample]) -> [WifiSample] {
        guard let ssid else { return [] }
        return samples.filter { sample in
            sample.band == band
                && sample.ssid == ssid
                && (bssids.isEmpty || bssids.contains(sample.bssid))
        }
    }

    func apply(to points: [SurveyPoint]) -> [WifiSample] {
        guard let ssid else { return [] }
        return points.compactMap { point in
            let readings = point.readings.filter { reading in
                reading.band == band
                    && reading.ssid == ssid
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
