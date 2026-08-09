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
                .help("Continuous WiFi scan running in the background. Signal readings are captured each time you tap the floor plan.")

                Picker("Band", selection: $activeBand) {
                    ForEach(WiFiBand.allCases, id: \.self) { band in
                        Text(band.displayName).tag(band)
                    }
                }
                .pickerStyle(.segmented)
                .help("Select the WiFi frequency band to scan and display. Choose the band your network operates on — most modern routers use 5 GHz.")

                Picker("Network", selection: $selectedSSID) {
                    Text("All").tag(Optional<String>.none)
                    ForEach(availableSSIDs, id: \.self) { ssid in
                        Text(ssid).tag(Optional(ssid))
                    }
                }
                .help("Filter readings to a single network name (SSID). Use \u{201C}All\u{201D} to show every network detected on this band.")
            }

            Section("Filter") {
                Picker("Access Point", selection: $selectedBSSID) {
                    Text("All APs").tag(Optional<String>.none)
                    ForEach(availableBSSIDs, id: \.self) { bssid in
                        Text(bssid).tag(Optional(bssid))
                    }
                }
                .help("Narrow the heatmap to one specific access point by its hardware address (BSSID). Useful when multiple APs share the same network name and you want to see each one\u{2019}s coverage area separately.")
            }

            Section("Heatmap") {
                Toggle("Show Heatmap", isOn: $showHeatmap)
                    .help("Overlay a color-coded signal map on the floor plan. Log at least a few readings first, and calibrate the scale so distances are accurate.")
            }

            Section {
                Picker("Metric", selection: $metric) {
                    ForEach(HeatmapMetric.allCases, id: \.self) { m in
                        Text(m.displayName).tag(m)
                    }
                }
                .help("RSSI: raw received signal strength in dBm \u{2014} higher (less negative) is stronger. SNR: signal-to-noise ratio in dB \u{2014} measures connection quality independent of raw power. Channel: shows which WiFi channel dominates each area, useful for spotting interference between overlapping networks.")

                Picker("Color Scheme", selection: $colorScheme) {
                    ForEach(HeatmapColorScheme.allCases, id: \.self) { scheme in
                        Text(scheme.displayName).tag(scheme)
                    }
                }
                .help("Blue \u{2192} Red: classic heatmap style, cold to hot. Red \u{2192} Green: traffic-light convention, weak to strong. Colorblind Safe: blue and orange palette, readable for deuteranopia and protanopia.")

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
                .help("How far each reading\u{2019}s signal influence extends in real-world meters. Smaller values produce sharper, more localized blobs; larger values smooth the heatmap across bigger gaps between readings.")
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
                    .help("Set the real-world scale by tapping two points of known distance on the floor plan. Required before logging readings \u{2014} without calibration the fade radius and distance calculations will be inaccurate.")

                Toggle("Delete Mode", isOn: $isDeleteMode)
                    .tint(isDeleteMode ? .red : nil)
                    .help("Click any reading marker on the map to remove it. Right-click a marker at any time to get a context menu with a delete option.")
            }

            Section("Floor Plan") {
                Button("Import Floor Plan\u{2026}", action: onImport)
                    .help("Load a floor plan image (PNG, JPEG, or PDF) as the background for this floor. The image is stored inside the survey document.")
                Button("Export as PNG\u{2026}", action: onExport)
                    .help("Save the floor plan with the heatmap composited on top as a PNG image. If the heatmap is hidden, only the floor plan is exported.")
            }
        }
        .formStyle(.grouped)
    }
}
