import XCTest
import CoreGraphics
@testable import WifiHeatmap

final class ExportTests: XCTestCase {

    func testCompositeProducesCorrectSize() {
        let w = 400, h = 300
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                   bitsPerComponent: 8, bytesPerRow: w * 4,
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue),
              let floorImg = ctx.makeImage() else {
            return XCTFail("Could not create test floor image")
        }
        let result = FloorDetailView.composeExportImage(floorImage: floorImg, heatmapImage: nil)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.width, w)
        XCTAssertEqual(result?.height, h)
    }

    func testCompositeWithHeatmapIsNotNil() {
        let w = 100, h = 100
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                   bitsPerComponent: 8, bytesPerRow: w * 4,
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue),
              let img = ctx.makeImage() else {
            return XCTFail("Could not create test image")
        }
        let result = FloorDetailView.composeExportImage(floorImage: img, heatmapImage: img)
        XCTAssertNotNil(result)
    }
}
