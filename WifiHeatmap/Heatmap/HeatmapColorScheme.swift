import Foundation

enum HeatmapColorScheme: String, CaseIterable {
    case classic        // blue (weak) → red (strong)
    case trafficLight   // red (weak) → green (strong)
    case colorblindSafe // blue (weak) → orange (strong); safe for deuteranopia/protanopia

    var displayName: String {
        switch self {
        case .classic:        return "Blue → Red"
        case .trafficLight:   return "Red → Green"
        case .colorblindSafe: return "Colorblind Safe"
        }
    }
}
