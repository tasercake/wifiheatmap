import SwiftUI

struct InspectorView: View {
    // Scanning
    let isScanning: Bool
    let availableSSIDs: [String]
    @Binding var activeBand: WiFiBand
    @Binding var selectedSSID: String?

    // Filter
    let availableBSSIDs: [String]
    @Binding var selectedBSSID: String?

    // Heatmap
    @Binding var showHeatmap: Bool
    @Binding var metric: HeatmapMetric
    @Binding var colorScheme: HeatmapColorScheme
    @Binding var outerRadius: Double

    // Survey modes
    @Binding var isCalibrating: Bool
    @Binding var isDeleteMode: Bool

    // Callbacks
    let onImport: () -> Void
    let onExport: () -> Void

    var body: some View {
        Form {
            Section("Scanning") {
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Image(systemName: isScanning
                              ? "antenna.radiowaves.left.and.right"
                              : "antenna.radiowaves.left.and.right.slash")
                            .foregroundStyle(isScanning ? .green : .secondary)
                        Text(isScanning ? "Scanning\u{2026}" : "Idle")
                            .foregroundStyle(isScanning ? .primary : .secondary)
                    }
                }

                Picker("Band", selection: $activeBand) {
                    ForEach(WiFiBand.allCases, id: \.self) { band in
                        Text(band.displayName).tag(band)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Network", selection: $selectedSSID) {
                    Text("All").tag(Optional<String>.none)
                    ForEach(availableSSIDs, id: \.self) { ssid in
                        Text(ssid).tag(Optional(ssid))
                    }
                }
            }

            Section("Filter") {
                Picker("Access Point", selection: $selectedBSSID) {
                    Text("All APs").tag(Optional<String>.none)
                    ForEach(availableBSSIDs, id: \.self) { bssid in
                        Text(bssid).tag(Optional(bssid))
                    }
                }
            }

            Section("Heatmap") {
                Toggle("Show Heatmap", isOn: $showHeatmap)
            }

            Section {
                Picker("Metric", selection: $metric) {
                    ForEach(HeatmapMetric.allCases, id: \.self) { m in
                        Text(m.displayName).tag(m)
                    }
                }

                Picker("Color Scheme", selection: $colorScheme) {
                    ForEach(HeatmapColorScheme.allCases, id: \.self) { scheme in
                        Text(scheme.displayName).tag(scheme)
                    }
                }

                LabeledContent("Fade Radius") {
                    HStack(spacing: 6) {
                        Slider(value: $outerRadius, in: IDWInterpolator.innerRadiusMeters...30, step: 0.5)
                        Text("\(outerRadius, specifier: "%.0f") m")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .trailing)
                            .monospacedDigit()
                    }
                }
            }
            .disabled(!showHeatmap)

            if showHeatmap {
                Section("Legend") {
                    HeatmapLegendView(colorScheme: colorScheme, metric: metric)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Section("Survey") {
                Toggle("Calibration Mode", isOn: $isCalibrating)
                    .help("Mark two reference points to set the map scale")

                Toggle("Delete Mode", isOn: $isDeleteMode)
                    .tint(isDeleteMode ? .red : nil)
                    .help("Click a reading to delete it; right-click for context menu")
            }

            Section("Floor Plan") {
                Button("Import Floor Plan\u{2026}", action: onImport)
                Button("Export as PNG\u{2026}", action: onExport)
            }
        }
        .formStyle(.grouped)
    }
}
