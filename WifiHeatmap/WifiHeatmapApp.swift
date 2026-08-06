import SwiftUI

@main
struct WifiHeatmapApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { WifiSurveyDocument() }) { config in
            ContentView(document: config.document)
        }
    }
}
