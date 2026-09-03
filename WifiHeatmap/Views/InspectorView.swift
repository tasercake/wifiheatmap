import SwiftUI

struct InspectorView: View {
    // Scanning
    let isScanning: Bool
    let availableSSIDs: [String]
    @Binding var activeBand: WiFiBand
    @Binding var selectedSSIDs: Set<String>
    @Binding var trackedBands: Set<WiFiBand>

    // Filter
    let availableBSSIDs: [String]
    @Binding var selectedBSSIDs: Set<String>

    // Heatmap
    @Binding var showHeatmap: Bool
    @Binding var showContours: Bool
    @Binding var contourSmoothingMeters: Double
    @Binding var metric: HeatmapMetric
    @Binding var colorScheme: HeatmapColorScheme
    @Binding var rssiRange: HeatmapValueRange
    @Binding var snrRange: HeatmapValueRange
    @Binding var outerRadius: Double

    // Survey modes
    @Binding var isCalibrating: Bool
    @Binding var isDeleteMode: Bool
    let hasRecordedPoints: Bool

    // Callbacks
    let onClearAll: () -> Void
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
                .help("The scanner stays idle until you tap the calibrated floor plan. Each tap stores the complete result of one successful CoreWLAN scan; sidebar selections only change what is displayed.")

                Picker("Band", selection: $activeBand) {
                    ForEach(WiFiBand.allCases, id: \.self) { band in
                        Text(band.displayName).tag(band)
                    }
                }
                .pickerStyle(.segmented)
                .help("Choose which recorded WiFi band to display on the floor plan and heatmap.")

                LabeledContent("Track Bands") {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(WiFiBand.allCases, id: \.self) { band in
                            Toggle(band.displayName, isOn: trackedBandBinding(band))
                                .toggleStyle(.checkbox)
                                .disabled(trackedBands == [band])
                        }
                    }
                }
                .disabled(isScanning)
                .help("Choose which bands future points must contain and record. At least one band must remain enabled; existing points are unchanged.")

                LabeledContent("Networks") {
                    MultiSelectionMenu(
                        allLabel: "All Networks",
                        options: availableSSIDs,
                        selection: $selectedSSIDs
                    )
                }
                .disabled(isScanning)
                .help("Select one or more required networks. The heatmap shows any selected network, and captures retry until every selected network appears on every tracked band. All requires only band coverage.")
            }

            Section("Filter") {
                LabeledContent("Access Points") {
                    MultiSelectionMenu(
                        allLabel: "All APs",
                        options: availableBSSIDs,
                        selection: $selectedBSSIDs
                    )
                }
                .disabled(isScanning)
                .help("Select one or more required access points. A capture retries until every selected BSSID appears on one of the tracked bands; a BSSID is not required on every band.")
            }

            Section("Heatmap") {
                Toggle("Show Heatmap", isOn: $showHeatmap)
                    .help("Overlay a color-coded signal map on the floor plan. Log at least a few readings first, and calibrate the scale so distances are accurate.")

                Toggle("Show Contours", isOn: $showContours)
                    .disabled(metric == .channel)
                    .help("Overlay labeled signal contours at 10 dB intervals. Crowded lines are automatically suppressed using the calibrated physical scale. Contours are unavailable for the Channel metric.")

                if showContours {
                    LabeledContent("Smoothing") {
                        HStack(spacing: 6) {
                            Slider(value: $contourSmoothingMeters, in: 0...3, step: 0.25)
                            Text(contourSmoothingMeters == 0
                                 ? "Off"
                                 : "\(contourSmoothingMeters, specifier: "%.2g") m")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 42, alignment: .trailing)
                                .monospacedDigit()
                        }
                    }
                    .disabled(metric == .channel)
                    .help("Smooth the calculated signal field before drawing contours. Higher values reduce point-scale bumps; zero preserves the raw interpolated field. Recorded readings and the heatmap are unchanged.")
                }
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
                .help("Red \u{2192} Blue: red is weak and blue is strong. Red \u{2192} Green: traffic-light convention, weak to strong. Colorblind Safe: blue and orange palette, readable for deuteranopia and protanopia.")

                if metric != .channel {
                    HeatmapRangeControl(
                        range: metric == .rssi ? $rssiRange : $snrRange,
                        metric: metric
                    )
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
                .help("How far each reading\u{2019}s signal influence extends in real-world meters. Smaller values produce sharper, more localized blobs; larger values smooth the heatmap across bigger gaps between readings.")
            }
            .disabled(!showHeatmap && !showContours)

            if showHeatmap || showContours {
                Section("Legend") {
                    HeatmapLegendView(
                        colorScheme: colorScheme,
                        metric: metric,
                        valueRange: metric == .rssi ? rssiRange : snrRange
                    )
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Section("Survey") {
                Toggle("Calibration Mode", isOn: $isCalibrating)
                    .help("Set the real-world scale by tapping two points of known distance on the floor plan. Required before logging readings \u{2014} without calibration the fade radius and distance calculations will be inaccurate.")

                Toggle("Delete Mode", isOn: $isDeleteMode)
                    .tint(isDeleteMode ? .red : nil)
                    .help("Click any reading marker on the map to remove it. Right-click a marker at any time to get a context menu with a delete option.")

                Button(role: .destructive, action: onClearAll) {
                    Label("Clear All", systemImage: "trash")
                }
                .disabled(!hasRecordedPoints || isScanning)
                .help("Delete every recorded point on the currently active floor. Use Undo to restore them.")
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

    private func trackedBandBinding(_ band: WiFiBand) -> Binding<Bool> {
        Binding(
            get: { trackedBands.contains(band) },
            set: { enabled in
                if enabled {
                    trackedBands.insert(band)
                } else if trackedBands.count > 1 {
                    trackedBands.remove(band)
                }
            }
        )
    }
}

private struct MultiSelectionMenu: View {
    let allLabel: String
    let options: [String]
    @Binding var selection: Set<String>

    private var summary: String {
        if selection.isEmpty { return allLabel }
        if selection.count == 1 { return selection.first! }
        return "\(selection.count) selected"
    }

    var body: some View {
        Menu(summary) {
            Button {
                selection.removeAll()
            } label: {
                if selection.isEmpty {
                    Label(allLabel, systemImage: "checkmark")
                } else {
                    Text(allLabel)
                }
            }

            Divider()

            ForEach(options, id: \.self) { option in
                Toggle(option, isOn: optionBinding(option))
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func optionBinding(_ option: String) -> Binding<Bool> {
        Binding(
            get: { selection.contains(option) },
            set: { selected in
                if selected { selection.insert(option) }
                else { selection.remove(option) }
            }
        )
    }
}

private struct HeatmapRangeControl: View {
    @Binding var range: HeatmapValueRange
    let metric: HeatmapMetric

    private var limits: ClosedRange<Double> {
        metric == .rssi ? -120...0 : -20...100
    }

    private var unit: String {
        metric == .rssi ? "dBm" : "dB"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Color Range")
                .font(.caption)
                .foregroundStyle(.secondary)

            TwoSidedSlider(range: $range, limits: limits)
                .frame(height: 22)

            HStack(spacing: 6) {
                TextField("Minimum", value: lowerBinding, format: .number.precision(.fractionLength(0...1)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 62)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel("Minimum \(metric.displayName)")

                Text("to")
                    .foregroundStyle(.secondary)

                TextField("Maximum", value: upperBinding, format: .number.precision(.fractionLength(0...1)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 62)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel("Maximum \(metric.displayName)")

                Text(unit)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .help("Values at or below the minimum use the weakest color; values at or above the maximum use the strongest color.")
    }

    private var lowerBinding: Binding<Double> {
        Binding(
            get: { range.lowerBound },
            set: { value in
                var updated = range
                updated.setLowerBound(value, within: limits)
                range = updated
            }
        )
    }

    private var upperBinding: Binding<Double> {
        Binding(
            get: { range.upperBound },
            set: { value in
                var updated = range
                updated.setUpperBound(value, within: limits)
                range = updated
            }
        )
    }
}

private struct TwoSidedSlider: View {
    @Binding var range: HeatmapValueRange
    let limits: ClosedRange<Double>

    private let thumbSize: CGFloat = 16

    var body: some View {
        GeometryReader { geometry in
            let usableWidth = max(geometry.size.width - thumbSize, 1)
            let lowerX = thumbSize / 2 + xPosition(for: range.lowerBound, width: usableWidth)
            let upperX = thumbSize / 2 + xPosition(for: range.upperBound, width: usableWidth)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(height: 4)
                    .padding(.horizontal, thumbSize / 2)

                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(upperX - lowerX, 0), height: 4)
                    .offset(x: lowerX)

                thumb(at: lowerX, label: "Minimum")
                    .gesture(dragGesture(width: usableWidth, isLower: true))

                thumb(at: upperX, label: "Maximum")
                    .gesture(dragGesture(width: usableWidth, isLower: false))
            }
            .coordinateSpace(name: "twoSidedSlider")
        }
    }

    private func thumb(at x: CGFloat, label: String) -> some View {
        Circle()
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
            .frame(width: thumbSize, height: thumbSize)
            .position(x: x, y: 11)
            .contentShape(Rectangle().inset(by: -5))
            .accessibilityLabel("\(label) heatmap bound")
    }

    private func dragGesture(width: CGFloat, isLower: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("twoSidedSlider"))
            .onChanged { gesture in
                let value = value(at: gesture.location.x - thumbSize / 2, width: width)
                var updated = range
                if isLower {
                    updated.setLowerBound(value, within: limits)
                } else {
                    updated.setUpperBound(value, within: limits)
                }
                range = updated
            }
    }

    private func xPosition(for value: Double, width: CGFloat) -> CGFloat {
        CGFloat((value - limits.lowerBound) / (limits.upperBound - limits.lowerBound)) * width
    }

    private func value(at x: CGFloat, width: CGFloat) -> Double {
        let fraction = min(max(Double(x / width), 0), 1)
        return (limits.lowerBound + fraction * (limits.upperBound - limits.lowerBound)).rounded()
    }
}
