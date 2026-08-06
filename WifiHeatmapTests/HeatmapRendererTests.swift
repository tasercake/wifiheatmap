import XCTest
import CoreGraphics
@testable import WifiHeatmap

final class HeatmapRendererTests: XCTestCase {

    func testAllNilGridReturnsNilOrTransparent() {
        let grid = Array(repeating: Array(repeating: Optional<Float>.none,
                                         count: IDWInterpolator.gridSize),
                         count: IDWInterpolator.gridSize)
        // Either returns nil or a fully-transparent image
        if let img = HeatmapRenderer.render(grid: grid) {
            let alpha = pixelAlpha(img, x: 0, y: 0)
            XCTAssertEqual(alpha, 0)
        }
    }

    func testMinRSSIIsBlue() {
        var grid = Array(repeating: Array(repeating: Optional<Float>.none,
                                         count: IDWInterpolator.gridSize),
                         count: IDWInterpolator.gridSize)
        grid[0][0] = HeatmapRenderer.minRSSI  // -90 dBm
        guard let img = HeatmapRenderer.render(grid: grid) else {
            return XCTFail("render returned nil")
        }
        let (r, g, b, a) = pixelRGBA(img, x: 0, y: 0)
        XCTAssertEqual(a, 255)
        // Blue: r ≈ 0, g ≈ 0, b ≈ 255 (within 20 counts tolerance)
        XCTAssertLessThan(r, 20)
        XCTAssertLessThan(g, 20)
        XCTAssertGreaterThan(b, 235)
    }

    func testMaxRSSIIsRed() {
        var grid = Array(repeating: Array(repeating: Optional<Float>.none,
                                         count: IDWInterpolator.gridSize),
                         count: IDWInterpolator.gridSize)
        grid[0][0] = HeatmapRenderer.maxRSSI  // -50 dBm
        guard let img = HeatmapRenderer.render(grid: grid) else {
            return XCTFail("render returned nil")
        }
        let (r, g, b, a) = pixelRGBA(img, x: 0, y: 0)
        XCTAssertEqual(a, 255)
        // Red: r ≈ 255, g ≈ 0, b ≈ 0
        XCTAssertGreaterThan(r, 235)
        XCTAssertLessThan(g, 20)
        XCTAssertLessThan(b, 20)
    }

    func testNilCellIsTransparent() {
        var grid = Array(repeating: Array(repeating: Optional<Float>.none,
                                         count: IDWInterpolator.gridSize),
                         count: IDWInterpolator.gridSize)
        grid[0][0] = -70  // only cell 0,0 has data
        guard let img = HeatmapRenderer.render(grid: grid) else {
            return XCTFail("render returned nil")
        }
        // Cell (1,1) should be transparent
        let alpha = pixelAlpha(img, x: 1, y: 1)
        XCTAssertEqual(alpha, 0)
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
