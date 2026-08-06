import Foundation

struct Floor: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var floorPlanFilename: String
    var calibration: Calibration?
    var samples: [WifiSample]
}
