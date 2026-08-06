import Foundation

enum WiFiBand: String, Codable, CaseIterable, Equatable {
    case ghz2_4 = "ghz2_4"
    case ghz5   = "ghz5"
    case ghz6   = "ghz6"

    var displayName: String {
        switch self {
        case .ghz2_4: return "2.4 GHz"
        case .ghz5:   return "5 GHz"
        case .ghz6:   return "6 GHz"
        }
    }
}
