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
    @State private var showHeatmap = false
    @State private var colorScheme: HeatmapColorScheme = .classic
    @State private var outerRadius: Double = IDWInterpolator.outerRadiusMeters

    private var availableSSIDs: [String] {
        Array(Set(latestBatch.map(\.ssid))).sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            FloorPlanView(
                document: document,
                floor: $floor,
                activeBand: activeBand,
                showHeatmap: showHeatmap,
                colorScheme: colorScheme,
                outerRadius: outerRadius,
                isCalibrating: isCalibrating,
                onTap: logReading
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Bottom bar
            HStack {
                calibrationStatus
                Spacer()
                if let best = latestBatch
                    .filter({ $0.band == activeBand && (selectedSSID == nil || $0.ssid == selectedSSID) })
                    .max(by: { $0.rssi < $1.rssi }) {
                    Text("Last: \(best.rssi) dBm \u{2014} tap map to log")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No signal on \(activeBand.displayName)")
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
            Toggle(isOn: $showHeatmap) {
                Label("Heatmap", systemImage: "thermometer.medium")
            }
            .toggleStyle(.button)
            .help(showHeatmap ? "Hide heatmap" : "Show heatmap")
        }
        ToolbarItem {
            Picker("Colors", selection: $colorScheme) {
                ForEach(HeatmapColorScheme.allCases, id: \.self) { scheme in
                    Text(scheme.displayName).tag(scheme)
                }
            }
            .frame(minWidth: 140)
            .disabled(!showHeatmap)
        }
        ToolbarItem {
            HStack(spacing: 4) {
                Text("Fade:")
                    .font(.caption)
                    .foregroundStyle(showHeatmap ? .primary : .tertiary)
                Slider(
                    value: $outerRadius,
                    in: IDWInterpolator.innerRadiusMeters...30,
                    step: 0.5
                )
                .frame(width: 90)
                .disabled(!showHeatmap)
                Text("\(outerRadius, specifier: "%.0f")m")
                    .font(.caption)
                    .foregroundStyle(showHeatmap ? .primary : .tertiary)
                    .frame(width: 24, alignment: .leading)
            }
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

    private func logReading(at position: CGPoint) {
        guard floor.calibration != nil else { return }
        let candidates = latestBatch.filter { n in
            n.band == activeBand && (selectedSSID == nil || n.ssid == selectedSSID)
        }
        guard let best = candidates.max(by: { $0.rssi < $1.rssi }) else { return }
        let sample = WifiSample(
            id: UUID(),
            position: position,
            timestamp: Date(),
            ssid: best.ssid,
            bssid: best.bssid,
            rssi: best.rssi,
            noise: best.noise,
            band: best.band
        )
        floor.samples.append(sample)
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
