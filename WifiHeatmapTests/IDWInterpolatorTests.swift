import XCTest
@testable import WifiHeatmap

final class IDWInterpolatorTests: XCTestCase {

    // Calibration: 100px = 1m (simple scale)
    let cal = Calibration(
        pointA: CGPoint(x: 0, y: 0),
        pointB: CGPoint(x: 100, y: 0),
        realWorldDistanceMeters: 1.0
    )

    // 200×200px image — with 1m/100px scale, innerRadius=3m covers the whole image
    // so all non-nil cells have alpha = 1.0 in these tests
    let testImageSize = CGSize(width: 200, height: 200)

    func testNoSamplesReturnsAllNil() {
        let grid = IDWInterpolator.interpolate(samples: [], calibration: cal, band: .ghz5, imageSize: testImageSize)
        XCTAssertEqual(grid.count, IDWInterpolator.gridSize)
        XCTAssertEqual(grid[0].count, IDWInterpolator.gridSize)
        XCTAssertTrue(grid.allSatisfy { row in row.allSatisfy { $0 == nil } })
    }

    func testSingleSampleFillsNearbyCell() {
        let sample = WifiSample(
            id: UUID(),
            position: CGPoint(x: 0, y: 0),
            timestamp: Date(timeIntervalSince1970: 0),
            ssid: "Net", bssid: "aa:bb:cc:dd:ee:ff",
            rssi: -60, noise: -90, band: .ghz5
        )
        let grid = IDWInterpolator.interpolate(samples: [sample], calibration: cal, band: .ghz5, imageSize: testImageSize)
        XCTAssertNotNil(grid[0][0])
        XCTAssertEqual(grid[0][0]!.rssi, -60, accuracy: 1.0)
        XCTAssertEqual(grid[0][0]!.alpha, 1.0, accuracy: 0.001)  // distance = 0 → full opacity
    }

    func testBandFilteringExcludesWrongBand() {
        let sample = WifiSample(
            id: UUID(),
            position: CGPoint(x: 0, y: 0),
            timestamp: Date(timeIntervalSince1970: 0),
            ssid: "Net", bssid: "aa:bb:cc:dd:ee:ff",
            rssi: -60, noise: -90, band: .ghz2_4
        )
        let grid = IDWInterpolator.interpolate(samples: [sample], calibration: cal, band: .ghz5, imageSize: testImageSize)
        XCTAssertTrue(grid.allSatisfy { row in row.allSatisfy { $0 == nil } })
    }

    func testTwoSamplesInterpolatesCorrectly() {
        let s1 = WifiSample(id: UUID(), position: CGPoint(x: 0,   y: 0),
                            timestamp: .init(timeIntervalSince1970: 0),
                            ssid: "N", bssid: "a", rssi: -50, noise: -90, band: .ghz5)
        let s2 = WifiSample(id: UUID(), position: CGPoint(x: 200, y: 0),
                            timestamp: .init(timeIntervalSince1970: 0),
                            ssid: "N", bssid: "b", rssi: -90, noise: -90, band: .ghz5)
        let grid = IDWInterpolator.interpolate(samples: [s1, s2], calibration: cal, band: .ghz5, imageSize: testImageSize)
        // Center cell: both samples are ~100px away = 1m, well within innerRadius (3m) → alpha = 1.0
        XCTAssertNotNil(grid[0][IDWInterpolator.gridSize / 2], "Center cell must be non-nil when samples bracket the center")
        if let midCell = grid[0][IDWInterpolator.gridSize / 2] {
            XCTAssertGreaterThan(midCell.rssi, -90)
            XCTAssertLessThan(midCell.rssi, -50)
            XCTAssertEqual(midCell.alpha, 1.0, accuracy: 0.001)
        }
    }
}
