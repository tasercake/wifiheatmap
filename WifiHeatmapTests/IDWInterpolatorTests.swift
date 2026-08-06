import XCTest
@testable import WifiHeatmap

final class IDWInterpolatorTests: XCTestCase {

    // Calibration: 100px = 1m (simple scale)
    let cal = Calibration(
        pointA: CGPoint(x: 0, y: 0),
        pointB: CGPoint(x: 100, y: 0),
        realWorldDistanceMeters: 1.0
    )

    // Floor plan is 200px × 200px = same as gridSize, so pixel ≈ cell
    // (exact mapping is floor plan pixel → normalized grid coordinate)

    // Image size used for tests: 200×200px matches the gridSize so pixel ≈ cell
    let testImageSize = CGSize(width: 200, height: 200)

    func testNoSamplesReturnsAllNil() {
        let grid = IDWInterpolator.interpolate(samples: [], calibration: cal, band: .ghz5, imageSize: testImageSize)
        XCTAssertEqual(grid.count, IDWInterpolator.gridSize)
        XCTAssertEqual(grid[0].count, IDWInterpolator.gridSize)
        XCTAssertTrue(grid.allSatisfy { row in row.allSatisfy { $0 == nil } })
    }

    func testSingleSampleFillsNearbyCell() {
        // Sample at floor plan pixel (0, 0), RSSI = -60
        let sample = WifiSample(
            id: UUID(),
            position: CGPoint(x: 0, y: 0),
            timestamp: Date(timeIntervalSince1970: 0),
            ssid: "Net", bssid: "aa:bb:cc:dd:ee:ff",
            rssi: -60, noise: -90, band: .ghz5
        )
        let grid = IDWInterpolator.interpolate(samples: [sample], calibration: cal, band: .ghz5, imageSize: testImageSize)
        // Cell (0,0) should be -60 (the only sample, distance = 0)
        XCTAssertNotNil(grid[0][0])
        XCTAssertEqual(grid[0][0]!, -60, accuracy: 1.0)
    }

    func testBandFilteringExcludesWrongBand() {
        let sample = WifiSample(
            id: UUID(),
            position: CGPoint(x: 0, y: 0),
            timestamp: Date(timeIntervalSince1970: 0),
            ssid: "Net", bssid: "aa:bb:cc:dd:ee:ff",
            rssi: -60, noise: -90, band: .ghz2_4
        )
        // Interpolating for .ghz5 — should find no samples → all nil
        let grid = IDWInterpolator.interpolate(samples: [sample], calibration: cal, band: .ghz5, imageSize: testImageSize)
        XCTAssertTrue(grid.allSatisfy { row in row.allSatisfy { $0 == nil } })
    }

    func testTwoSamplesInterpolatesCorrectly() {
        // Two samples at opposite corners of the 200×200 image, RSSI = -50 and -90
        // The midpoint cell should have an RSSI between -50 and -90
        let s1 = WifiSample(id: UUID(), position: CGPoint(x: 0,   y: 0),
                            timestamp: .init(timeIntervalSince1970: 0),
                            ssid: "N", bssid: "a", rssi: -50, noise: -90, band: .ghz5)
        let s2 = WifiSample(id: UUID(), position: CGPoint(x: 200, y: 0),
                            timestamp: .init(timeIntervalSince1970: 0),
                            ssid: "N", bssid: "b", rssi: -90, noise: -90, band: .ghz5)
        let grid = IDWInterpolator.interpolate(samples: [s1, s2], calibration: cal, band: .ghz5, imageSize: testImageSize)
        // With 1m/100px calibration and 5m radius, both samples are within range of the center
        XCTAssertNotNil(grid[0][IDWInterpolator.gridSize / 2], "Center cell must be non-nil when samples bracket the center")
        if let midCell = grid[0][IDWInterpolator.gridSize / 2] {
            XCTAssertGreaterThan(midCell, -90)
            XCTAssertLessThan(midCell, -50)
        }
    }
}
