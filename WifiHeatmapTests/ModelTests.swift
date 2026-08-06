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
            samples: []
        )
        let data = try encoder.encode(floor)
        let decoded = try decoder.decode(Floor.self, from: data)
        XCTAssertEqual(decoded.id, floor.id)
        XCTAssertEqual(decoded.name, floor.name)
        XCTAssertNil(decoded.calibration)
        XCTAssertTrue(decoded.samples.isEmpty)
    }

    func testWifiSurveyRoundTrip() throws {
        let survey = WifiSurvey(name: "Home Survey", floors: [])
        let data = try encoder.encode(survey)
        let decoded = try decoder.decode(WifiSurvey.self, from: data)
        XCTAssertEqual(decoded.name, survey.name)
        XCTAssertTrue(decoded.floors.isEmpty)
    }
}
