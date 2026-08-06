import Foundation

struct WifiSurvey: Codable, Equatable {
    var name: String
    var floors: [Floor]
}
