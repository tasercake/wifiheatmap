import Foundation

struct Calibration: Codable, Equatable {
    var pointA: CGPoint
    var pointB: CGPoint
    var realWorldDistanceMeters: Double

    var metersPerPixel: Double {
        let dx = pointB.x - pointA.x
        let dy = pointB.y - pointA.y
        let pixelDistance = sqrt(dx * dx + dy * dy)
        guard pixelDistance > 0 else { return 1 }
        return realWorldDistanceMeters / pixelDistance
    }
}
