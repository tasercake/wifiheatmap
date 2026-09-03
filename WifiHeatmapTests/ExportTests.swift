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

    func testCompositeIncludesContourLayer() throws {
        let floor = try solidImage(width: 80, height: 60, red: 1, green: 1, blue: 1)
        let contours = try solidImage(width: 80, height: 60, red: 1, green: 0, blue: 0)

        let result = try XCTUnwrap(FloorDetailView.composeExportImage(
            floorImage: floor,
            heatmapImage: nil,
            contourImage: contours
        ))
        let pixel = rgba(result, x: 40, y: 30)

        XCTAssertGreaterThan(pixel.r, 240)
        XCTAssertGreaterThan(Int(pixel.r) - Int(pixel.g), 180)
        XCTAssertGreaterThan(Int(pixel.r) - Int(pixel.b), 180)
    }

    func testExportDrawsFloorNameAndLegendPanelsWithoutChangingImageSize() throws {
        let floor = try solidImage(width: 600, height: 400, red: 1, green: 1, blue: 1)
        let legend = ExportLegend(
            colorScheme: .classic,
            metric: .rssi,
            valueRange: HeatmapValueRange(lowerBound: -90, upperBound: -20)
        )

        let result = try XCTUnwrap(FloorDetailView.composeExportImage(
            floorImage: floor,
            heatmapImage: nil,
            contourImage: nil,
            floorName: "Ground Floor",
            legend: legend
        ))

        XCTAssertEqual(result.width, 600)
        XCTAssertEqual(result.height, 400)
        let titleBackground = rgba(result, x: 22, y: 22)
        let legendBackground = rgba(result, x: 22, y: 378)
        XCTAssertLessThan(titleBackground.r, 245)
        XCTAssertLessThan(legendBackground.r, 245)
    }

    private func solidImage(
        width: Int,
        height: Int,
        red: CGFloat,
        green: CGFloat,
        blue: CGFloat
    ) throws -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw CocoaError(.coderInvalidValue)
        }
        context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { throw CocoaError(.coderInvalidValue) }
        return image
    }

    private func rgba(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(
            image,
            in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height)
        )
        return (pixel[0], pixel[1], pixel[2], pixel[3])
    }
}
