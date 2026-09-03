import XCTest
import CoreGraphics
@testable import WifiHeatmap

final class HeatmapRendererTests: XCTestCase {

    // Convenience: fully-opaque cell at a given value
    private func cell(_ value: Float) -> IDWInterpolator.Cell {
        IDWInterpolator.Cell(value: value, alpha: 1.0)
    }

    private func emptyGrid() -> [[IDWInterpolator.Cell?]] {
        Array(repeating: Array(repeating: nil, count: IDWInterpolator.gridSize),
              count: IDWInterpolator.gridSize)
    }

    func testAllNilGridReturnsNilOrTransparent() {
        let grid = emptyGrid()
        if let img = HeatmapRenderer.render(grid: grid) {
            XCTAssertEqual(pixelAlpha(img, x: 0, y: 0), 0)
        }
    }

    func testMinRSSIIsRed() {
        var grid = emptyGrid()
        grid[0][0] = cell(HeatmapRenderer.minRSSI)  // -90 dBm, alpha=1
        guard let img = HeatmapRenderer.render(grid: grid) else {
            return XCTFail("render returned nil")
        }
        let (r, g, b, a) = pixelRGBA(img, x: 0, y: 0)
        XCTAssertEqual(a, 255)
        XCTAssertGreaterThan(r, 235)
        XCTAssertLessThan(g, 20)
        XCTAssertLessThan(b, 20)
    }

    func testMaxRSSIIsBlue() {
        var grid = emptyGrid()
        grid[0][0] = cell(HeatmapRenderer.maxRSSI)  // -20 dBm, alpha=1
        guard let img = HeatmapRenderer.render(grid: grid) else {
            return XCTFail("render returned nil")
        }
        let (r, g, b, a) = pixelRGBA(img, x: 0, y: 0)
        XCTAssertEqual(a, 255)
        XCTAssertLessThan(r, 20)
        XCTAssertLessThan(g, 20)
        XCTAssertGreaterThan(b, 235)
    }

    func testConfiguredRSSIRangeDoesNotCrushMinusFiftyToMaximumColor() {
        var grid = emptyGrid()
        grid[0][0] = cell(-50)
        let range = HeatmapValueRange(lowerBound: -90, upperBound: -20)
        guard let img = HeatmapRenderer.render(grid: grid, metric: .rssi, valueRange: range) else {
            return XCTFail("render returned nil")
        }

        let (_, g, b, a) = pixelRGBA(img, x: 0, y: 0)
        XCTAssertEqual(a, 255)
        XCTAssertLessThan(b, 235)
        XCTAssertGreaterThan(g, 100)
    }

    func testNilCellIsTransparent() {
        var grid = emptyGrid()
        grid[0][0] = cell(-70)  // only cell 0,0 has data
        guard let img = HeatmapRenderer.render(grid: grid) else {
            return XCTFail("render returned nil")
        }
        XCTAssertEqual(pixelAlpha(img, x: 1, y: 1), 0)
    }

    func testSNRRangeIsZeroToForty() {
        let (min, max) = HeatmapRenderer.valueRange(for: .snr)
        XCTAssertEqual(min, 0)
        XCTAssertEqual(max, 40)
    }

    func testDefaultRSSIRangeIsMinusNinetyToMinusTwenty() {
        let (min, max) = HeatmapRenderer.valueRange(for: .rssi)
        XCTAssertEqual(min, -90)
        XCTAssertEqual(max, -20)
    }

    func testChannelColorIsNotTransparent() {
        var grid = emptyGrid()
        grid[0][0] = IDWInterpolator.Cell(value: 36, alpha: 1.0)
        guard let img = HeatmapRenderer.render(grid: grid, metric: .channel) else {
            return XCTFail("render returned nil")
        }
        let (_, _, _, a) = pixelRGBA(img, x: 0, y: 0)
        XCTAssertEqual(a, 255)
    }

    func testContourLevelsUseTenUnitStepsInsideConfiguredRange() {
        let levels = ContourGenerator.levels(
            for: .rssi,
            valueRange: HeatmapValueRange(lowerBound: -87, upperBound: -23)
        )

        XCTAssertEqual(levels, [-80, -70, -60, -50, -40, -30])
        XCTAssertTrue(ContourGenerator.levels(
            for: .channel,
            valueRange: HeatmapValueRange(lowerBound: 0, upperBound: 100)
        ).isEmpty)
    }

    func testMarchingSquaresInterpolatesAContourAcrossOneCell() throws {
        let grid: [[IDWInterpolator.Cell?]] = [
            [cell(-80), cell(-40)],
            [cell(-80), cell(-40)]
        ]

        let line = try XCTUnwrap(ContourGenerator.lines(in: grid, level: -60).first)

        XCTAssertEqual(line.level, -60)
        XCTAssertEqual(line.points.count, 2)
        XCTAssertEqual(line.points[0].x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(line.points[1].x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(Set(line.points.map(\.y)), [0, 1])
    }

    func testContoursDoNotCrossLowConfidenceCells() {
        let opaqueLow = IDWInterpolator.Cell(value: -80, alpha: 1)
        let opaqueHigh = IDWInterpolator.Cell(value: -40, alpha: 1)
        let fadedHigh = IDWInterpolator.Cell(value: -40, alpha: 0.05)
        let grid: [[IDWInterpolator.Cell?]] = [
            [opaqueLow, opaqueHigh],
            [opaqueLow, fadedHigh]
        ]

        XCTAssertTrue(ContourGenerator.lines(in: grid, level: -60).isEmpty)
    }

    func testCrowdedMinorContourIsSuppressedUsingPhysicalDistance() {
        let lines = [
            ContourLine(level: -80, points: [CGPoint(x: 0.10, y: 0), CGPoint(x: 0.10, y: 1)]),
            ContourLine(level: -70, points: [CGPoint(x: 0.11, y: 0), CGPoint(x: 0.11, y: 1)]),
            ContourLine(level: -50, points: [CGPoint(x: 0.50, y: 0), CGPoint(x: 0.50, y: 1)])
        ]

        let filtered = ContourGenerator.enforceMinimumSeparation(
            lines,
            imageSize: CGSize(width: 100, height: 100),
            metersPerPixel: 0.1,
            minimumMeters: 0.75
        )

        XCTAssertEqual(filtered.map(\.level), [-80, -50])
    }

    func testContourLabelsReserveTitleAndLegendCorners() {
        let size = CGSize(width: 900, height: 600)

        XCTAssertTrue(ContourRenderer.isReservedLabelArea(
            CGRect(x: 10, y: 530, width: 120, height: 35),
            imageSize: size
        ))
        XCTAssertTrue(ContourRenderer.isReservedLabelArea(
            CGRect(x: 10, y: 10, width: 160, height: 60),
            imageSize: size
        ))
        XCTAssertFalse(ContourRenderer.isReservedLabelArea(
            CGRect(x: 400, y: 260, width: 100, height: 40),
            imageSize: size
        ))
    }

    func testZeroContourSmoothingLeavesFieldValuesUnchanged() {
        let grid: [[IDWInterpolator.Cell?]] = [
            [cell(-80), cell(-70), cell(-60)],
            [cell(-70), cell(-40), cell(-50)],
            [cell(-60), cell(-50), cell(-40)]
        ]

        let smoothed = ContourGenerator.smooth(
            grid: grid,
            radiusMeters: 0,
            imageSize: CGSize(width: 30, height: 30),
            metersPerPixel: 0.1
        )

        XCTAssertEqual(smoothed[1][1]?.value, -40)
        XCTAssertEqual(smoothed[0][2]?.value, -60)
    }

    func testContourSmoothingReducesPointImpulseWithoutExpandingCoverage() {
        let base = cell(-80)
        var grid = Array(repeating: Array<IDWInterpolator.Cell?>(repeating: base, count: 5), count: 5)
        grid[2][2] = cell(-20)
        grid[0][0] = nil

        let smoothed = ContourGenerator.smooth(
            grid: grid,
            radiusMeters: 1.5,
            imageSize: CGSize(width: 40, height: 40),
            metersPerPixel: 0.1
        )

        let center = smoothed[2][2]?.value ?? -100
        let neighbor = smoothed[2][1]?.value ?? -100
        XCTAssertGreaterThan(center, -80)
        XCTAssertLessThan(center, -20)
        XCTAssertGreaterThan(neighbor, -80)
        XCTAssertNil(smoothed[0][0])
        XCTAssertEqual(smoothed[2][2]?.alpha, 1)
    }

    // MARK: - Helpers

    private func pixelAlpha(_ img: CGImage, x: Int, y: Int) -> UInt8 {
        pixelRGBA(img, x: x, y: y).3
    }

    private func pixelRGBA(_ img: CGImage, x: Int, y: Int) -> (UInt8, UInt8, UInt8, UInt8) {
        let w = img.width, h = img.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h,
                            bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        let idx = (y * w + x) * 4
        return (data[idx], data[idx+1], data[idx+2], data[idx+3])
    }
}
