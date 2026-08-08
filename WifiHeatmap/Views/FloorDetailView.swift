import SwiftUI
import ImageIO

struct FloorDetailView: View {
    @Environment(\.undoManager) var undoManager
    @ObservedObject var document: WifiSurveyDocument
    @Binding var floor: Floor

    // Passed in from ContentView (Task 10 wires the real values)
    var latestBatch: [ScannedNetwork] = []
    var isScanning: Bool = false

    @State private var activeBand: WiFiBand = .ghz5
    @State private var selectedSSID: String? = nil
    @State private var selectedBSSID: String? = nil
    @State private var isCalibrating = false
    @State private var showHeatmap = false
    @State private var colorScheme: HeatmapColorScheme = .classic
    @State private var metric: HeatmapMetric = .rssi
    @State private var outerRadius: Double = IDWInterpolator.outerRadiusMeters
    @State private var isDeleteMode: Bool = false

    private var availableSSIDs: [String] {
        Array(Set(latestBatch.map(\.ssid))).sorted()
    }

    private var availableBSSIDs: [String] {
        let filtered = floor.samples.filter {
            $0.band == activeBand && (selectedSSID == nil || $0.ssid == selectedSSID)
        }
        return Array(Set(filtered.map(\.bssid))).sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            FloorPlanView(
                document: document,
                floor: $floor,
                activeBand: activeBand,
                showHeatmap: showHeatmap,
                colorScheme: colorScheme,
                metric: metric,
                outerRadius: outerRadius,
                isCalibrating: isCalibrating,
                onTap: logReading,
                filterBSSID: selectedBSSID,
                isDeleteMode: isDeleteMode,
                onDelete: deleteReading
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
        .onChange(of: activeBand)   { selectedBSSID = nil }
        .onChange(of: selectedSSID) { selectedBSSID = nil }
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
            Picker("AP", selection: $selectedBSSID) {
                Text("All APs").tag(Optional<String>.none)
                ForEach(availableBSSIDs, id: \.self) { bssid in
                    Text(bssid).tag(Optional(bssid))
                }
            }
            .frame(minWidth: 130)
            .help("Filter heatmap to a single access point by BSSID")
        }
        ToolbarItem {
            Label(isScanning ? "Scanning\u{2026}" : "Idle",
                  systemImage: isScanning ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                .foregroundStyle(isScanning ? .green : .secondary)
        }
        ToolbarItem {
            HStack(spacing: 4) {
                Toggle(isOn: $showHeatmap) {
                    Label("Heatmap", systemImage: "thermometer.medium")
                }
                .toggleStyle(.button)
                .help(showHeatmap ? "Hide heatmap" : "Show heatmap")
                Toggle(isOn: $isDeleteMode) {
                    Label("Delete Mode", systemImage: "minus.circle")
                }
                .toggleStyle(.button)
                .help(isDeleteMode ? "Exit delete mode" : "Right-click any marker to delete it")
                .tint(isDeleteMode ? .red : nil)
                Button("Export\u{2026}") {
                    exportFloorPlan()
                }
                .help("Export floor plan with heatmap as PNG")
            }
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
            Picker("Metric", selection: $metric) {
                ForEach(HeatmapMetric.allCases, id: \.self) { m in
                    Text(m.displayName).tag(m)
                }
            }
            .frame(minWidth: 110)
            .disabled(!showHeatmap)
            .help("Switch between RSSI, SNR, and Channel interference map")
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
            id:        UUID(),
            position:  position,
            timestamp: Date(),
            ssid:      best.ssid,
            bssid:     best.bssid,
            rssi:      best.rssi,
            noise:     best.noise,
            band:      best.band,
            channel:   best.channel
        )
        floor.samples.append(sample)
        let floorID = floor.id
        let sampleID = sample.id
        undoManager?.registerUndo(withTarget: document) { [floorID, sampleID] doc in
            if let fi = doc.survey.floors.firstIndex(where: { $0.id == floorID }) {
                doc.survey.floors[fi].samples.removeAll { $0.id == sampleID }
            }
        }
        undoManager?.setActionName("Log Reading")
    }

    private func deleteReading(id: UUID) {
        let floorID = floor.id
        guard let idx = floor.samples.firstIndex(where: { $0.id == id }) else { return }
        let removed = floor.samples[idx]
        floor.samples.remove(at: idx)
        undoManager?.registerUndo(withTarget: document) { [floorID, removed] doc in
            if let fi = doc.survey.floors.firstIndex(where: { $0.id == floorID }) {
                doc.survey.floors[fi].samples.append(removed)
            }
        }
        undoManager?.setActionName("Delete Reading")
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

    // MARK: - Export

    static func composeExportImage(floorImage: CGImage, heatmapImage: CGImage?) -> CGImage? {
        let w = floorImage.width
        let h = floorImage.height
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }
        ctx.draw(floorImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        if let hm = heatmapImage {
            ctx.setAlpha(0.6)
            ctx.draw(hm, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return ctx.makeImage()
    }

    private func exportFloorPlan() {
        guard let imageData = document.imageCache[floor.floorPlanFilename],
              let src = CGImageSourceCreateWithData(imageData as CFData, nil),
              let floorImg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return }

        let imgSize = CGSize(width: floorImg.width, height: floorImg.height)
        let samples = floor.samples
        let band    = activeBand
        let radius  = outerRadius
        let met     = metric
        let scheme  = colorScheme
        let cal     = floor.calibration
        let includeHeatmap = showHeatmap
        let floorName = floor.name

        Task.detached(priority: .userInitiated) {
            let heatmapImg: CGImage?
            if includeHeatmap, let c = cal {
                let grid = IDWInterpolator.interpolate(
                    samples: samples, calibration: c,
                    band: band, imageSize: imgSize,
                    outerRadius: radius, metric: met
                )
                heatmapImg = HeatmapRenderer.render(grid: grid, colorScheme: scheme, metric: met)
            } else {
                heatmapImg = nil
            }
            let composite = Self.composeExportImage(floorImage: floorImg, heatmapImage: heatmapImg)

            await MainActor.run {
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.png]
                panel.nameFieldStringValue = "\(floorName).png"
                panel.title = "Export Floor Plan"
                guard panel.runModal() == .OK, let url = panel.url,
                      let img = composite else { return }
                guard let dest = CGImageDestinationCreateWithURL(
                    url as CFURL, "public.png" as CFString, 1, nil
                ) else { return }
                CGImageDestinationAddImage(dest, img, nil)
                CGImageDestinationFinalize(dest)
            }
        }
    }
}
