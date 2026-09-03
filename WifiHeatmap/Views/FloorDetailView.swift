import SwiftUI
import ImageIO

struct FloorDetailView: View {
    @Environment(\.undoManager) var undoManager
    @ObservedObject var document: WifiSurveyDocument
    @Binding var floor: Floor

    var latestBatch: [ScannedNetwork] = []
    var latestScanAt: Date? = nil
    var isScanning: Bool = false
    var scanForReading: (Int) async throws -> ScanBatch
    @Binding var showInspector: Bool

    @State private var isCalibrating = false
    @State private var isDeleteMode: Bool = false
    @State private var measurementState: MeasurementState = .idle
    @State private var pendingPosition: CGPoint?

    private var settings: SurveyViewSettings {
        document.survey.viewSettings
    }

    private var sampleFilter: SampleFilter {
        SampleFilter(
            band: settings.activeBand,
            ssids: settings.selectedSSIDs,
            bssids: settings.selectedBSSIDs
        )
    }

    private var heatmapValueRange: HeatmapValueRange {
        settings.valueRange(for: settings.metric)
    }

    private var availableSSIDs: [String] {
        var ssids = Set(latestBatch.map(\.ssid))
        ssids.formUnion(floor.points.flatMap(\.readings).map(\.ssid))
        ssids.formUnion(settings.selectedSSIDs)
        return ssids.sorted()
    }

    private var availableBSSIDs: [String] {
        var bssids = Set(floor.points.flatMap(\.readings).filter {
            $0.band == settings.activeBand
                && (settings.selectedSSIDs.isEmpty || settings.selectedSSIDs.contains($0.ssid))
        }.map(\.bssid))
        bssids.formUnion(latestBatch.filter {
            $0.band == settings.activeBand
                && (settings.selectedSSIDs.isEmpty || settings.selectedSSIDs.contains($0.ssid))
        }.map(\.bssid))
        bssids.formUnion(settings.selectedBSSIDs)
        return bssids.sorted()
    }

    private var latestSignal: ScannedNetwork? {
        latestBatch
            .filter {
                $0.band == settings.activeBand
                    && (settings.selectedSSIDs.isEmpty || settings.selectedSSIDs.contains($0.ssid))
                    && (settings.selectedBSSIDs.isEmpty || settings.selectedBSSIDs.contains($0.bssid))
            }
            .max(by: { $0.rssi < $1.rssi })
    }

    private var knownBSSIDBands: [String: WiFiBand] {
        let stored = floor.points.flatMap(\.readings).map { ($0.bssid, $0.band) }
        let recent = latestBatch.map { ($0.bssid, $0.band) }
        return Dictionary(stored + recent, uniquingKeysWith: { _, newest in newest })
    }

    private var lastTaggedAt: Date? {
        sampleFilter.apply(to: floor.points)
            .map(\.timestamp)
            .max()
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                FloorPlanView(
                    document: document,
                    floor: $floor,
                    sampleFilter: sampleFilter,
                    showHeatmap: settings.showHeatmap,
                    showContours: settings.showContours,
                    contourSmoothingMeters: settings.contourSmoothingMeters,
                    colorScheme: settings.colorScheme,
                    metric: settings.metric,
                    valueRange: heatmapValueRange,
                    outerRadius: settings.fadeRadius,
                    isCalibrating: isCalibrating,
                    onTap: logReading,
                    isDeleteMode: isDeleteMode,
                    onDelete: deleteReading
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                HStack {
                    calibrationStatus
                    Spacer()
                    SignalStatusView(
                        signal: latestSignal,
                        filter: sampleFilter,
                        latestScanAt: latestSignal == nil ? nil : latestScanAt,
                        lastTaggedAt: lastTaggedAt,
                        measurementState: measurementState
                    )
                }
                .padding(.horizontal, 8)
                .frame(height: BottomStatusBarLayout.height)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showInspector {
                Divider()
                InspectorView(
                    isScanning: measurementState.isScanning || isScanning,
                    availableSSIDs: availableSSIDs,
                    activeBand: $document.survey.viewSettings.activeBand,
                    selectedSSIDs: $document.survey.viewSettings.selectedSSIDs,
                    trackedBands: $document.survey.viewSettings.trackedBands,
                    availableBSSIDs: availableBSSIDs,
                    selectedBSSIDs: $document.survey.viewSettings.selectedBSSIDs,
                    showHeatmap: $document.survey.viewSettings.showHeatmap,
                    showContours: $document.survey.viewSettings.showContours,
                    contourSmoothingMeters: $document.survey.viewSettings.contourSmoothingMeters,
                    metric: $document.survey.viewSettings.metric,
                    colorScheme: $document.survey.viewSettings.colorScheme,
                    rssiRange: $document.survey.viewSettings.rssiRange,
                    snrRange: $document.survey.viewSettings.snrRange,
                    outerRadius: $document.survey.viewSettings.fadeRadius,
                    isCalibrating: $isCalibrating,
                    isDeleteMode: $isDeleteMode,
                    hasRecordedPoints: !floor.points.isEmpty,
                    onClearAll: clearAllPoints,
                    onImport: importFloorPlan,
                    onExport: exportFloorPlan
                )
                .frame(width: 260)
            }
        }
    }

    private var calibrationStatus: some View {
        Group {
            if floor.calibration == nil {
                Label("No calibration \u{2014} tap Calibrate in the inspector before logging", systemImage: "exclamationmark.triangle")
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
        guard !measurementState.isScanning else { return }

        pendingPosition = position
        let requirements = CaptureRequirements(
            requiredSSIDs: settings.selectedSSIDs,
            requiredBSSIDs: settings.selectedBSSIDs,
            requiredBSSIDBands: knownBSSIDBands.filter { settings.selectedBSSIDs.contains($0.key) },
            trackedBands: settings.trackedBands
        )
        measurementState = .scanning(attempt: 1, maxAttempts: PointCaptureCoordinator.maximumAttempts)

        Task {
            do {
                guard let pendingPosition else { return }
                let point = try await PointCaptureCoordinator.capture(
                    at: pendingPosition,
                    requirements: requirements,
                    scan: scanForReading,
                    onProgress: { progress in
                        switch progress {
                        case .scanning(let attempt, let maxAttempts):
                            measurementState = .scanning(attempt: attempt, maxAttempts: maxAttempts)
                        case .retrying(let reason, let nextAttempt, let maxAttempts):
                            measurementState = .retrying(
                                reason: reason,
                                nextAttempt: nextAttempt,
                                maxAttempts: maxAttempts
                            )
                        }
                    }
                )
                let insertionIndex = floor.points.endIndex
                floor.points.append(point)
                self.pendingPosition = nil
                measurementState = .recorded(point)

                PointUndo.registerUndoForInsertion(
                    point,
                    at: insertionIndex,
                    floorID: floor.id,
                    document: document,
                    undoManager: undoManager,
                    actionName: "Log Point"
                )
            } catch {
                pendingPosition = nil
                measurementState = .failed(error.localizedDescription)
            }
        }
    }

    private func deleteReading(id: UUID) {
        guard let index = floor.points.firstIndex(where: { $0.id == id }) else { return }
        let removed = floor.points.remove(at: index)
        PointUndo.registerUndoForRemoval(
            removed,
            at: index,
            floorID: floor.id,
            document: document,
            undoManager: undoManager,
            actionName: "Delete Point"
        )
    }

    private func clearAllPoints() {
        guard !measurementState.isScanning else { return }
        guard PointUndo.clearAllPoints(
            floorID: floor.id,
            document: document,
            undoManager: undoManager
        ) else { return }

        pendingPosition = nil
        measurementState = .idle
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

    nonisolated static func composeExportImage(
        floorImage: CGImage,
        heatmapImage: CGImage?,
        contourImage: CGImage? = nil,
        floorName: String? = nil,
        legend: ExportLegend? = nil
    ) -> CGImage? {
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
        if let contours = contourImage {
            ctx.setAlpha(1)
            ctx.draw(contours, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        ctx.setAlpha(1)
        ExportOverlayRenderer.draw(
            floorName: floorName,
            legend: legend,
            canvasSize: CGSize(width: w, height: h),
            in: ctx
        )
        return ctx.makeImage()
    }

    private func exportFloorPlan() {
        guard let imageData = document.imageCache[floor.floorPlanFilename],
              let src = CGImageSourceCreateWithData(imageData as CFData, nil),
              let floorImg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return }

        let imgSize = CGSize(width: floorImg.width, height: floorImg.height)
        let samples = sampleFilter.apply(to: floor.points)
        let band    = settings.activeBand
        let radius  = settings.fadeRadius
        let met     = settings.metric
        let scheme  = settings.colorScheme
        let valueRange = heatmapValueRange
        let cal     = floor.calibration
        let includeHeatmap = settings.showHeatmap
        let includeContours = settings.showContours && met != .channel
        let contourSmoothing = settings.contourSmoothingMeters
        let floorName = floor.name

        Task.detached(priority: .userInitiated) {
            let heatmapImg: CGImage?
            let contourImg: CGImage?
            if (includeHeatmap || includeContours), let c = cal {
                let grid = IDWInterpolator.interpolate(
                    samples: samples, calibration: c,
                    band: band, imageSize: imgSize,
                    outerRadius: radius, metric: met
                )
                heatmapImg = includeHeatmap ? HeatmapRenderer.render(
                    grid: grid,
                    colorScheme: scheme,
                    metric: met,
                    valueRange: valueRange
                ) : nil
                contourImg = includeContours ? ContourRenderer.render(
                    grid: grid,
                    metric: met,
                    valueRange: valueRange,
                    calibration: c,
                    imageSize: imgSize,
                    smoothingMeters: contourSmoothing
                ) : nil
            } else {
                heatmapImg = nil
                contourImg = nil
            }
            let composite = Self.composeExportImage(
                floorImage: floorImg,
                heatmapImage: heatmapImg,
                contourImage: contourImg,
                floorName: floorName,
                legend: ExportLegend(
                    colorScheme: scheme,
                    metric: met,
                    valueRange: valueRange
                )
            )

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

enum PointUndo {
    @discardableResult
    static func clearAllPoints(
        floorID: UUID,
        document: WifiSurveyDocument,
        undoManager: UndoManager?
    ) -> Bool {
        guard let floorIndex = document.survey.floors.firstIndex(where: { $0.id == floorID }),
              !document.survey.floors[floorIndex].points.isEmpty
        else { return false }

        let removedPoints = document.survey.floors[floorIndex].points
        document.survey.floors[floorIndex].points = []
        registerUndoForReplacement(
            removedPoints,
            floorID: floorID,
            document: document,
            undoManager: undoManager,
            actionName: "Clear All Points"
        )
        return true
    }

    static func registerUndoForInsertion(
        _ point: SurveyPoint,
        at index: Int,
        floorID: UUID,
        document: WifiSurveyDocument,
        undoManager: UndoManager?,
        actionName: String
    ) {
        undoManager?.registerUndo(withTarget: document) { document in
            guard let floorIndex = document.survey.floors.firstIndex(where: { $0.id == floorID }),
                  let pointIndex = document.survey.floors[floorIndex].points.firstIndex(where: { $0.id == point.id })
            else { return }

            document.survey.floors[floorIndex].points.remove(at: pointIndex)
            registerUndoForRemoval(
                point,
                at: index,
                floorID: floorID,
                document: document,
                undoManager: undoManager,
                actionName: actionName
            )
        }
        undoManager?.setActionName(actionName)
    }

    static func registerUndoForRemoval(
        _ point: SurveyPoint,
        at index: Int,
        floorID: UUID,
        document: WifiSurveyDocument,
        undoManager: UndoManager?,
        actionName: String
    ) {
        undoManager?.registerUndo(withTarget: document) { document in
            guard let floorIndex = document.survey.floors.firstIndex(where: { $0.id == floorID }) else {
                return
            }

            let restoredIndex = min(index, document.survey.floors[floorIndex].points.endIndex)
            document.survey.floors[floorIndex].points.insert(point, at: restoredIndex)
            registerUndoForInsertion(
                point,
                at: restoredIndex,
                floorID: floorID,
                document: document,
                undoManager: undoManager,
                actionName: actionName
            )
        }
        undoManager?.setActionName(actionName)
    }

    private static func registerUndoForReplacement(
        _ replacement: [SurveyPoint],
        floorID: UUID,
        document: WifiSurveyDocument,
        undoManager: UndoManager?,
        actionName: String
    ) {
        undoManager?.registerUndo(withTarget: document) { document in
            guard let floorIndex = document.survey.floors.firstIndex(where: { $0.id == floorID }) else {
                return
            }

            let currentPoints = document.survey.floors[floorIndex].points
            document.survey.floors[floorIndex].points = replacement
            registerUndoForReplacement(
                currentPoints,
                floorID: floorID,
                document: document,
                undoManager: undoManager,
                actionName: actionName
            )
        }
        undoManager?.setActionName(actionName)
    }
}

enum BottomStatusBarLayout {
    static let height: CGFloat = 112
    static let statusCardWidth: CGFloat = 440
    static let statusCardHeight: CGFloat = 96
}

private enum MeasurementState {
    case idle
    case scanning(attempt: Int, maxAttempts: Int)
    case retrying(reason: CaptureRetryReason, nextAttempt: Int, maxAttempts: Int)
    case recorded(SurveyPoint)
    case failed(String)

    var isScanning: Bool {
        switch self {
        case .scanning, .retrying: return true
        case .idle, .recorded, .failed: return false
        }
    }
}

private struct SignalStatusView: View {
    let signal: ScannedNetwork?
    let filter: SampleFilter
    let latestScanAt: Date?
    let lastTaggedAt: Date?
    let measurementState: MeasurementState

    private var status: SignalUpdateStatus {
        SignalUpdateStatus(latestScanAt: latestScanAt, lastTaggedAt: lastTaggedAt)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .trailing, spacing: 3) {
                HStack(spacing: 5) {
                    if measurementState.isScanning {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: statusIcon)
                            .foregroundStyle(statusColor)
                    }
                    Text(statusTitle)
                        .fontWeight(.medium)
                }

                switch measurementState {
                case .scanning(let attempt, let maxAttempts):
                    Text("Attempt \(attempt) of \(maxAttempts)")
                        .foregroundStyle(.secondary)
                    Text("Points will be added after the scan completes")
                        .foregroundStyle(.secondary)
                case .retrying(let reason, let nextAttempt, let maxAttempts):
                    Text(reason.message)
                        .foregroundStyle(.orange)
                    Text("Next: attempt \(nextAttempt) of \(maxAttempts)")
                        .foregroundStyle(.secondary)
                case .failed(let message):
                    Text(message)
                        .foregroundStyle(.secondary)
                    Text("No points were added")
                        .foregroundStyle(.red)
                case .recorded(let point):
                    if let sample = filter.apply(to: [point]).first {
                        Text("\(sample.rssi) dBm \u{00B7} \(sample.ssid) \u{00B7} \(sample.band.displayName)")
                            .foregroundStyle(.primary)
                    } else {
                        Text("No recorded reading matches the current filters")
                            .foregroundStyle(.secondary)
                    }
                    Text("\(SignalUpdateStatus(latestScanAt: point.completedAt, lastTaggedAt: nil).updatedText(at: context.date)) \u{00B7} \(point.duration, specifier: "%.1f")s \u{00B7} \(point.scanCacheUpdated ? "cache updated" : "no cache-update event")")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    if point.attemptCount > 1 {
                        Text("Completed after \(point.attemptCount) scan attempts")
                            .foregroundStyle(.secondary)
                    }
                case .idle:
                    if let signal {
                        Text("\(signal.rssi) dBm \u{00B7} \(signal.ssid) \u{00B7} \(filter.band.displayName)")
                            .foregroundStyle(.primary)
                    } else {
                        Text("No signal on \(filter.band.displayName)")
                            .foregroundStyle(.secondary)
                    }

                    Text(status.updatedText(at: context.date))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .font(.caption)
            .multilineTextAlignment(.trailing)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(
                width: BottomStatusBarLayout.statusCardWidth,
                height: BottomStatusBarLayout.statusCardHeight,
                alignment: .topTrailing
            )
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.secondary.opacity(0.2))
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var statusTitle: String {
        switch measurementState {
        case .scanning: return "Scanning\u{2026}"
        case .retrying: return "Retrying scan\u{2026}"
        case .recorded(let point):
            let networkLabel = point.readings.count == 1 ? "network" : "networks"
            let bandLabel = point.bandCount == 1 ? "band" : "bands"
            return "New CoreWLAN scan completed \u{00B7} \(point.readings.count) \(networkLabel) \u{00B7} \(point.bandCount) \(bandLabel)"
        case .failed: return "Scan unsuccessful"
        case .idle: return "Tap map to scan and record"
        }
    }

    private var statusIcon: String {
        switch measurementState {
        case .recorded: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .idle, .scanning, .retrying: break
        }

        switch status.freshness {
        case .noSignal: return "antenna.radiowaves.left.and.right.slash"
        case .readyToLog: return "checkmark.circle.fill"
        case .waitingForNewScan: return "clock.arrow.circlepath"
        case .freshScanAvailable: return "sparkles"
        }
    }

    private var statusColor: Color {
        switch measurementState {
        case .recorded: return .green
        case .failed: return .red
        case .idle, .scanning, .retrying: break
        }

        switch status.freshness {
        case .noSignal: return .secondary
        case .readyToLog, .freshScanAvailable: return .green
        case .waitingForNewScan: return .orange
        }
    }
}
