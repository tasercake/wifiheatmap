import XCTest
@testable import WifiHeatmap

final class ModelTests: XCTestCase {

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func testWiFiBandRawValues() {
        XCTAssertEqual(WiFiBand.ghz2_4.rawValue, "ghz2_4")
        XCTAssertEqual(WiFiBand.ghz5.rawValue, "ghz5")
        XCTAssertEqual(WiFiBand.ghz6.rawValue, "ghz6")
    }

    func testWiFiBandRoundTrip() throws {
        for band in WiFiBand.allCases {
            let data = try encoder.encode(band)
            let decoded = try decoder.decode(WiFiBand.self, from: data)
            XCTAssertEqual(decoded, band)
        }
    }

    func testWifiSampleRoundTrip() throws {
        let sample = WifiSample(
            id: UUID(),
            position: CGPoint(x: 100, y: 200),
            timestamp: Date(timeIntervalSince1970: 0),
            ssid: "MyNetwork",
            bssid: "aa:bb:cc:dd:ee:ff",
            rssi: -65,
            noise: -90,
            band: .ghz5
        )
        let data = try encoder.encode(sample)
        let decoded = try decoder.decode(WifiSample.self, from: data)
        XCTAssertEqual(decoded.id, sample.id)
        XCTAssertEqual(decoded.position.x, sample.position.x, accuracy: 0.001)
        XCTAssertEqual(decoded.position.y, sample.position.y, accuracy: 0.001)
        XCTAssertEqual(decoded.rssi, sample.rssi)
        XCTAssertEqual(decoded.band, sample.band)
        XCTAssertEqual(decoded.timestamp, sample.timestamp)
        XCTAssertEqual(decoded.ssid, sample.ssid)
        XCTAssertEqual(decoded.bssid, sample.bssid)
        XCTAssertEqual(decoded.noise, sample.noise)
    }

    func testCalibrationMetersPerPixel() {
        // 100 px apart, 5 m real → 0.05 m/px
        let cal = Calibration(
            pointA: CGPoint(x: 0, y: 0),
            pointB: CGPoint(x: 100, y: 0),
            realWorldDistanceMeters: 5.0
        )
        XCTAssertEqual(cal.metersPerPixel, 0.05, accuracy: 0.0001)
    }

    func testCalibrationDiagonal() {
        // 3-4-5 triangle: 300px, 400px → 500px distance, 10m real → 0.02 m/px
        let cal = Calibration(
            pointA: CGPoint(x: 0, y: 0),
            pointB: CGPoint(x: 300, y: 400),
            realWorldDistanceMeters: 10.0
        )
        XCTAssertEqual(cal.metersPerPixel, 0.02, accuracy: 0.0001)
    }

    func testFloorRoundTrip() throws {
        let floor = Floor(
            id: UUID(),
            name: "Ground Floor",
            floorPlanFilename: "abc123.png",
            calibration: nil,
            points: []
        )
        let data = try encoder.encode(floor)
        let decoded = try decoder.decode(Floor.self, from: data)
        XCTAssertEqual(decoded.id, floor.id)
        XCTAssertEqual(decoded.name, floor.name)
        XCTAssertNil(decoded.calibration)
        XCTAssertTrue(decoded.points.isEmpty)
    }

    func testLegacyFloorSamplesDecodeAsSingleReadingCaptures() throws {
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let sample = WifiSample(
            id: UUID(),
            position: CGPoint(x: 21, y: 34),
            timestamp: timestamp,
            ssid: "Legacy Network",
            bssid: "aa:bb:cc:dd:ee:ff",
            rssi: -61,
            noise: -93,
            band: .ghz5,
            channel: 44
        )
        let legacyFloor = LegacyFloorPayload(
            id: UUID(),
            name: "Legacy Floor",
            floorPlanFilename: "legacy.png",
            calibration: nil,
            samples: [sample]
        )

        let data = try encoder.encode(legacyFloor)
        let decoded = try decoder.decode(Floor.self, from: data)

        XCTAssertEqual(decoded.points.count, 1)
        let capture = try XCTUnwrap(decoded.points.first)
        XCTAssertEqual(capture.id, sample.id)
        XCTAssertEqual(capture.position, sample.position)
        XCTAssertEqual(capture.startedAt, timestamp)
        XCTAssertEqual(capture.completedAt, timestamp)
        XCTAssertFalse(capture.scanCacheUpdated)
        XCTAssertNil(capture.snapshotChanged)
        XCTAssertEqual(capture.attemptCount, 1)
        XCTAssertEqual(
            capture.readings,
            [WifiNetworkReading(
                ssid: sample.ssid,
                bssid: sample.bssid,
                rssi: sample.rssi,
                noise: sample.noise,
                band: sample.band,
                channel: sample.channel
            )]
        )
    }

    func testV1SamplesWithExactLocationAndTimestampBecomeOneSurveyPoint() throws {
        let timestamp = Date(timeIntervalSince1970: 1_500)
        let position = CGPoint(x: 25, y: 40)
        let samples = [
            WifiSample(
                id: UUID(), position: position, timestamp: timestamp,
                ssid: "Home", bssid: "2g", rssi: -51, noise: -91,
                band: .ghz2_4, channel: 6
            ),
            WifiSample(
                id: UUID(), position: position, timestamp: timestamp,
                ssid: "Home", bssid: "5g", rssi: -47, noise: -93,
                band: .ghz5, channel: 44
            ),
            WifiSample(
                id: UUID(), position: CGPoint(x: 25.001, y: 40),
                timestamp: timestamp,
                ssid: "Home", bssid: "later", rssi: -49, noise: -92,
                band: .ghz5, channel: 149
            )
        ]
        let payload = LegacyFloorPayload(
            id: UUID(), name: "V1", floorPlanFilename: "v1.png",
            calibration: nil, samples: samples
        )

        let floor = try decoder.decode(Floor.self, from: encoder.encode(payload))

        XCTAssertEqual(floor.points.count, 2)
        XCTAssertEqual(floor.points[0].id, samples[0].id)
        XCTAssertEqual(floor.points[0].readings.map(\.bssid), ["2g", "5g"])
        XCTAssertEqual(floor.points[1].id, samples[2].id)
        XCTAssertEqual(floor.points[1].readings.map(\.bssid), ["later"])
    }

    func testFloorCaptureRoundTripPreservesMetadataAndEveryReading() throws {
        let capture = SurveyPoint(
            id: UUID(),
            position: CGPoint(x: 55, y: 89),
            startedAt: Date(timeIntervalSince1970: 2_000),
            completedAt: Date(timeIntervalSince1970: 2_002),
            scanCacheUpdated: true,
            snapshotChanged: false,
            attemptCount: 2,
            readings: [
                WifiNetworkReading(ssid: "Home", bssid: "2g", rssi: -50, noise: -91, band: .ghz2_4, channel: 6),
                WifiNetworkReading(ssid: "Home", bssid: "5g", rssi: -57, noise: -94, band: .ghz5, channel: 44),
                WifiNetworkReading(ssid: "Guest", bssid: "6g", rssi: -63, noise: -96, band: .ghz6, channel: 37)
            ]
        )
        let floor = Floor(
            id: UUID(),
            name: "Complete Scan Floor",
            floorPlanFilename: "full.png",
            calibration: nil,
            points: [capture]
        )

        let data = try encoder.encode(floor)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(json["points"])
        XCTAssertNil(json["samples"])

        let decoded = try decoder.decode(Floor.self, from: data)
        XCTAssertEqual(decoded.points, [capture])
    }

    func testV2CaptureDecodesLosslesslyAsSurveyPoint() throws {
        let legacyCapture = LegacyCapturePayload(
            id: UUID(),
            position: CGPoint(x: 11, y: 22),
            startedAt: Date(timeIntervalSince1970: 3_000),
            completedAt: Date(timeIntervalSince1970: 3_002),
            scanCacheUpdated: true,
            snapshotChanged: false,
            attemptCount: 2,
            readings: [
                WifiNetworkReading(ssid: "Home", bssid: "2g", rssi: -52, noise: -91, band: .ghz2_4, channel: 6),
                WifiNetworkReading(ssid: "Home", bssid: "5g", rssi: -48, noise: -93, band: .ghz5, channel: 44)
            ]
        )
        let payload = LegacyCaptureFloorPayload(
            id: UUID(), name: "V2", floorPlanFilename: "v2.png",
            calibration: nil, captures: [legacyCapture]
        )

        let floor = try decoder.decode(Floor.self, from: encoder.encode(payload))
        let point: SurveyPoint = try XCTUnwrap(floor.points.first)

        XCTAssertEqual(point.id, legacyCapture.id)
        XCTAssertEqual(point.position, legacyCapture.position)
        XCTAssertEqual(point.startedAt, legacyCapture.startedAt)
        XCTAssertEqual(point.completedAt, legacyCapture.completedAt)
        XCTAssertEqual(point.scanCacheUpdated, legacyCapture.scanCacheUpdated)
        XCTAssertEqual(point.snapshotChanged, legacyCapture.snapshotChanged)
        XCTAssertEqual(point.attemptCount, legacyCapture.attemptCount)
        XCTAssertEqual(point.readings, legacyCapture.readings)
    }

    func testV3FloorRoundTripPersistsOnlyPoints() throws {
        let point = SurveyPoint(
            id: UUID(), position: CGPoint(x: 7, y: 9),
            startedAt: Date(timeIntervalSince1970: 4_000),
            completedAt: Date(timeIntervalSince1970: 4_001),
            scanCacheUpdated: true, snapshotChanged: true, attemptCount: 1,
            readings: [
                WifiNetworkReading(ssid: "Home", bssid: "ap", rssi: -45, noise: -94, band: .ghz6, channel: 37)
            ]
        )
        let floor = Floor(
            id: UUID(), name: "V3", floorPlanFilename: "v3.png",
            calibration: nil, points: [point]
        )

        let data = try encoder.encode(floor)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(json["points"])
        XCTAssertNil(json["captures"])
        XCTAssertNil(json["samples"])
        XCTAssertEqual(try decoder.decode(Floor.self, from: data).points, [point])
    }

    func testWifiSurveyRoundTrip() throws {
        let survey = WifiSurvey(name: "Home Survey", floors: [])
        let data = try encoder.encode(survey)
        let decoded = try decoder.decode(WifiSurvey.self, from: data)
        XCTAssertEqual(decoded.name, survey.name)
        XCTAssertTrue(decoded.floors.isEmpty)
    }

    func testSampleFilterMatchesBandNetworkAndAccessPoint() {
        let samples = [
            sample(ssid: "Home", bssid: "ap-1", band: .ghz5),
            sample(ssid: "Home", bssid: "ap-2", band: .ghz5),
            sample(ssid: "Guest", bssid: "ap-1", band: .ghz5),
            sample(ssid: "Home", bssid: "ap-1", band: .ghz2_4)
        ]

        let filtered = SampleFilter(band: .ghz5, ssid: "Home", bssid: "ap-1")
            .apply(to: samples)

        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered[0].ssid, "Home")
        XCTAssertEqual(filtered[0].bssid, "ap-1")
        XCTAssertEqual(filtered[0].band, .ghz5)
    }

    func testSampleFilterTreatsNilNetworkAndAccessPointAsAll() {
        let samples = [
            sample(ssid: "Home", bssid: "ap-1", band: .ghz5),
            sample(ssid: "Guest", bssid: "ap-2", band: .ghz5),
            sample(ssid: "Home", bssid: "ap-1", band: .ghz2_4)
        ]

        let filtered = SampleFilter(band: .ghz5, ssid: nil, bssid: nil)
            .apply(to: samples)

        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.allSatisfy { $0.band == .ghz5 })
    }

    func testSampleFilterProjectsTheStrongestMatchingReadingFromEachCapture() {
        let captureID = UUID()
        let position = CGPoint(x: 12, y: 34)
        let completedAt = Date(timeIntervalSince1970: 500)
        let capture = SurveyPoint(
            id: captureID,
            position: position,
            startedAt: completedAt.addingTimeInterval(-1),
            completedAt: completedAt,
            scanCacheUpdated: true,
            snapshotChanged: true,
            attemptCount: 1,
            readings: [
                WifiNetworkReading(ssid: "Home", bssid: "weak", rssi: -70, noise: -92, band: .ghz5, channel: 36),
                WifiNetworkReading(ssid: "Home", bssid: "strong", rssi: -45, noise: -90, band: .ghz5, channel: 44),
                WifiNetworkReading(ssid: "Guest", bssid: "guest", rssi: -20, noise: -91, band: .ghz5, channel: 149),
                WifiNetworkReading(ssid: "Home", bssid: "2g", rssi: -30, noise: -89, band: .ghz2_4, channel: 6)
            ]
        )

        let samples = SampleFilter(band: .ghz5, ssid: "Home", bssid: nil)
            .apply(to: [capture])

        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples[0].id, captureID)
        XCTAssertEqual(samples[0].position, position)
        XCTAssertEqual(samples[0].timestamp, completedAt)
        XCTAssertEqual(samples[0].bssid, "strong")
    }

    func testSampleFilterMatchesAnySelectedNetworkAndAccessPoint() {
        let samples = [
            sample(ssid: "Home", bssid: "home-5", band: .ghz5),
            sample(ssid: "Office", bssid: "office-5", band: .ghz5),
            sample(ssid: "Guest", bssid: "guest-5", band: .ghz5),
            sample(ssid: "Home", bssid: "home-2", band: .ghz2_4)
        ]

        let filtered = SampleFilter(
            band: .ghz5,
            ssids: ["Home", "Office"],
            bssids: ["home-5", "office-5"]
        ).apply(to: samples)

        XCTAssertEqual(Set(filtered.map(\.ssid)), ["Home", "Office"])
        XCTAssertEqual(Set(filtered.map(\.bssid)), ["home-5", "office-5"])
    }

    func testEmptyFilterSelectionsMeanAll() {
        let samples = [
            sample(ssid: "Home", bssid: "home-5", band: .ghz5),
            sample(ssid: "Guest", bssid: "guest-5", band: .ghz5)
        ]

        let filtered = SampleFilter(band: .ghz5, ssids: [], bssids: []).apply(to: samples)

        XCTAssertEqual(filtered.count, 2)
    }

    func testStandardHeatmapRangesUseUsefulRSSIAndSNRDefaults() {
        XCTAssertEqual(
            SurveyViewSettings.standard.rssiRange,
            HeatmapValueRange(lowerBound: -90, upperBound: -20)
        )
        XCTAssertEqual(
            SurveyViewSettings.standard.snrRange,
            HeatmapValueRange(lowerBound: 0, upperBound: 40)
        )
    }

    func testHeatmapRangeKeepsLowerBoundBelowUpperBound() {
        var range = HeatmapValueRange(lowerBound: -90, upperBound: -20)

        range.setLowerBound(-10, within: -120...0)
        XCTAssertEqual(range.lowerBound, -21)

        range.setUpperBound(-100, within: -120...0)
        XCTAssertEqual(range.upperBound, -20)
    }

    private func sample(ssid: String, bssid: String, band: WiFiBand) -> WifiSample {
        WifiSample(
            id: UUID(),
            position: .zero,
            timestamp: Date(timeIntervalSince1970: 0),
            ssid: ssid,
            bssid: bssid,
            rssi: -60,
            noise: -90,
            band: band
        )
    }
}

private struct LegacyFloorPayload: Encodable {
    var id: UUID
    var name: String
    var floorPlanFilename: String
    var calibration: Calibration?
    var samples: [WifiSample]
}

private struct LegacyCaptureFloorPayload: Encodable {
    var id: UUID
    var name: String
    var floorPlanFilename: String
    var calibration: Calibration?
    var captures: [LegacyCapturePayload]
}

private struct LegacyCapturePayload: Codable, Equatable {
    var id: UUID
    var position: CGPoint
    var startedAt: Date
    var completedAt: Date
    var scanCacheUpdated: Bool
    var snapshotChanged: Bool?
    var attemptCount: Int
    var readings: [WifiNetworkReading]
}
