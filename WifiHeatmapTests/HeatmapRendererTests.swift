import XCTest
import CoreGraphics
@testable import WifiHeatmap

final class HeatmapRendererTests: XCTestCase {

    // Convenience: fully-opaque cell at a given RSSI
    private func cell(_ rssi: Float) -> IDWInterpolator.Cell {
        IDWInterpolator.Cell(rssi: rssi, alpha: 1.0)
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

    func testMinRSSIIsBlue() {
        var grid = emptyGrid()
        grid[0][0] = cell(HeatmapRenderer.minRSSI)  // -90 dBm, alpha=1
        guard let img = HeatmapRenderer.render(grid: grid) else {
            return XCTFail("render returned nil")
        }
        let (r, g, b, a) = pixelRGBA(img, x: 0, y: 0)
        XCTAssertEqual(a, 255)
        XCTAssertLessThan(r, 20)
        XCTAssertLessThan(g, 20)
        XCTAssertGreaterThan(b, 235)
    }

    func testMaxRSSIIsRed() {
        var grid = emptyGrid()
        grid[0][0] = cell(HeatmapRenderer.maxRSSI)  // -50 dBm, alpha=1
        guard let img = HeatmapRenderer.render(grid: grid) else {
            return XCTFail("render returned nil")
        }
        let (r, g, b, a) = pixelRGBA(img, x: 0, y: 0)
        XCTAssertEqual(a, 255)
        XCTAssertGreaterThan(r, 235)
        XCTAssertLessThan(g, 20)
        XCTAssertLessThan(b, 20)
    }

    func testNilCellIsTransparent() {
        var grid = emptyGrid()
        grid[0][0] = cell(-70)  // only cell 0,0 has data
        guard let img = HeatmapRenderer.render(grid: grid) else {
            return XCTFail("render returned nil")
        }
        XCTAssertEqual(pixelAlpha(img, x: 1, y: 1), 0)
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
