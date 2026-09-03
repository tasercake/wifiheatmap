import Foundation

enum HeatmapColorScheme: String, Codable, CaseIterable {
    case classic        // red (weak) → blue (strong)
    case trafficLight   // red (weak) → green (strong)
    case colorblindSafe // blue (weak) → orange (strong); safe for deuteranopia/protanopia

    var displayName: String {
        switch self {
        case .classic:        return "Red → Blue"
        case .trafficLight:   return "Red → Green"
        case .colorblindSafe: return "Colorblind Safe"
        }
    }
}
