import SwiftUI

struct ContentView: View {
    @ObservedObject var document: WifiSurveyDocument
    @State private var selectedFloorID: UUID? = nil
    @StateObject private var locationAuth = LocationAuthManager()
    @State private var scanActor = ScanActor()
    @State private var latestBatch: [ScannedNetwork] = []
    @State private var isScanning = false

    private var selectedFloorIndex: Int? {
        document.survey.floors.firstIndex(where: { $0.id == selectedFloorID })
    }

    var body: some View {
        NavigationSplitView {
            FloorSidebarView(document: document, selectedFloorID: $selectedFloorID)
                .frame(minWidth: 160)
        } detail: {
            if let idx = selectedFloorIndex {
                FloorDetailView(
                    document: document,
                    floor: $document.survey.floors[idx],
                    latestBatch: latestBatch,
                    isScanning: isScanning
                )
            } else {
                Text("Select or add a floor in the sidebar.")
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            isScanning = true
            let stream = await scanActor.startScanning()
            for await batch in stream {
                latestBatch = batch
            }
            isScanning = false
        }
        .onDisappear {
            Task { await scanActor.stopScanning() }
        }
        .onAppear { locationAuth.requestIfNeeded() }
        .overlay(alignment: .top) {
            if locationAuth.isDenied {
                locationDeniedBanner
            }
        }
    }

    private var locationDeniedBanner: some View {
        HStack {
            Image(systemName: "location.slash")
            Text("Location access denied \u{2014} BSSIDs will be empty. Grant access in System Settings > Privacy > Location.")
                .font(.caption)
            Spacer()
            Button("Open Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Location")!)
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(8)
        .background(Color.yellow.opacity(0.85))
    }
}
