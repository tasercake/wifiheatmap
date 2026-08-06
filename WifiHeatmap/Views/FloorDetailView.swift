import SwiftUI

struct FloorDetailView: View {
    @ObservedObject var document: WifiSurveyDocument
    @Binding var floor: Floor

    // Passed in from ContentView (Task 10 wires the real values)
    var latestBatch: [ScannedNetwork] = []
    var isScanning: Bool = false

    @State private var activeBand: WiFiBand = .ghz5
    @State private var selectedSSID: String? = nil
    @State private var isCalibrating = false

    private var availableSSIDs: [String] {
        Array(Set(latestBatch.map(\.ssid))).sorted()
    }

    private var lastRSSI: Int? {
        let relevant = selectedSSID == nil
            ? latestBatch
            : latestBatch.filter { $0.ssid == selectedSSID }
        return relevant.filter { $0.band == activeBand }.map(\.rssi).max()
    }

    var body: some View {
        VStack(spacing: 0) {
            FloorPlanView(
                document: document,
                floor: $floor,
                activeBand: activeBand,
                isCalibrating: isCalibrating,
                onTap: { _ in }  // wired in Task 10
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Bottom bar
            HStack {
                calibrationStatus
                Spacer()
                if let rssi = lastRSSI {
                    Text("Last RSSI: \(rssi) dBm")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
        }
        .toolbar { toolbarContent }
        .navigationTitle(floor.name)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Band", selection: $activeBand) {
                ForEach(WiFiBand.allCases, id: \.self) { band in
                    Text(band.displayName).tag(band)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
        }
        ToolbarItem {
            Picker("SSID", selection: $selectedSSID) {
                Text("All").tag(Optional<String>.none)
                ForEach(availableSSIDs, id: \.self) { ssid in
                    Text(ssid).tag(Optional(ssid))
                }
            }
            .frame(minWidth: 120)
        }
        ToolbarItem {
            Label(isScanning ? "Scanning\u{2026}" : "Idle",
                  systemImage: isScanning ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                .foregroundStyle(isScanning ? .green : .secondary)
        }
        ToolbarItem {
            Button(isCalibrating ? "Done Calibrating" : "Calibrate") {
                isCalibrating.toggle()
            }
        }
        ToolbarItem {
            Button("Import Floor Plan\u{2026}") {
                importFloorPlan()
            }
        }
    }

    private var calibrationStatus: some View {
        Group {
            if floor.calibration == nil {
                Label("No calibration \u{2014} tap Calibrate before logging", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.caption)
            } else {
                Label("Calibrated", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
        }
    }

    private func importFloorPlan() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Import Floor Plan"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? document.importFloorPlan(url: url, for: floor.id)
    }
}
