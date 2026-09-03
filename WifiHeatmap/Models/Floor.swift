import Foundation

struct Floor: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var floorPlanFilename: String
    var calibration: Calibration?
    var points: [SurveyPoint]

    init(
        id: UUID,
        name: String,
        floorPlanFilename: String,
        calibration: Calibration?,
        points: [SurveyPoint]
    ) {
        self.id = id
        self.name = name
        self.floorPlanFilename = floorPlanFilename
        self.calibration = calibration
        self.points = points
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, floorPlanFilename, calibration, points, captures, samples
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        floorPlanFilename = try container.decode(String.self, forKey: .floorPlanFilename)
        calibration = try container.decodeIfPresent(Calibration.self, forKey: .calibration)

        if let decodedPoints = try container.decodeIfPresent([SurveyPoint].self, forKey: .points) {
            points = decodedPoints
        } else if let decodedCaptures = try container.decodeIfPresent([SurveyPoint].self, forKey: .captures) {
            points = decodedCaptures
        } else {
            let legacySamples = try container.decodeIfPresent([WifiSample].self, forKey: .samples) ?? []
            points = Self.points(from: legacySamples)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(floorPlanFilename, forKey: .floorPlanFilename)
        try container.encodeIfPresent(calibration, forKey: .calibration)
        try container.encode(points, forKey: .points)
    }

    private static func points(from samples: [WifiSample]) -> [SurveyPoint] {
        struct Key: Hashable {
            let x: CGFloat
            let y: CGFloat
            let timestamp: Date
        }

        var result: [SurveyPoint] = []
        var indexByKey: [Key: Int] = [:]
        for sample in samples {
            let key = Key(x: sample.position.x, y: sample.position.y, timestamp: sample.timestamp)
            if let index = indexByKey[key] {
                result[index].readings.append(WifiNetworkReading(legacySample: sample))
            } else {
                indexByKey[key] = result.count
                result.append(SurveyPoint(legacySample: sample))
            }
        }
        return result
    }
}

private extension SurveyPoint {
    init(legacySample sample: WifiSample) {
        self.init(
            id: sample.id,
            position: sample.position,
            startedAt: sample.timestamp,
            completedAt: sample.timestamp,
            scanCacheUpdated: false,
            snapshotChanged: nil,
            attemptCount: 1,
            readings: [WifiNetworkReading(legacySample: sample)]
        )
    }
}

private extension WifiNetworkReading {
    init(legacySample sample: WifiSample) {
        self.init(
            ssid: sample.ssid,
            bssid: sample.bssid,
            rssi: sample.rssi,
            noise: sample.noise,
            band: sample.band,
            channel: sample.channel
        )
    }
}
