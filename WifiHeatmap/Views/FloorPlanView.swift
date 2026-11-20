import SwiftUI
import ImageIO

struct PointAdditionGestureState: Equatable {
    private enum Phase: Equatable {
        case idle
        case active
        case cancelled
    }

    private var phase: Phase = .idle

    var acceptsUpdates: Bool { phase == .active }

    mutating func beginIfNeeded() {
        guard phase == .idle else { return }
        phase = .active
    }

    mutating func cancel() {
        guard phase == .active else { return }
        phase = .cancelled
    }

    mutating func finishShouldCommit() -> Bool {
        let shouldCommit = phase == .active
        phase = .idle
        return shouldCommit
    }
}

enum ExistingPointInteractionPolicy {
    static func isEnabled(isCalibrating: Bool, isCaptureInProgress _: Bool) -> Bool {
        !isCalibrating
    }
}

struct FloorPlanView: View {
    @ObservedObject var document: WifiSurveyDocument
    @Binding var floor: Floor
    let points: [SurveyPoint]
    let sampleFilter: SampleFilter
    let showHeatmap: Bool
    let showContours: Bool
    let contourSmoothingMeters: Double
    let colorScheme: HeatmapColorScheme
    let metric: HeatmapMetric
    let valueRange: HeatmapValueRange
    let outerRadius: Double
    let isCalibrating: Bool
    @Binding var pendingPoint: PendingSurveyPoint?
    @Binding var selectedPointID: UUID?
    let pointAdditionCancellationToken: Int
    let isCaptureInProgress: Bool
    let onCaptureRequested: (PendingSurveyPoint) -> Void
    let onMovePoint: (UUID, CGPoint) -> Void
    let onSetPointOrientation: (UUID, Double?) -> Void
    let onImport: () -> Void
    let onCalibrationComplete: () -> Void
    var isDeleteMode: Bool = false
    var onDelete: (UUID) -> Void = { _ in }

    @State private var heatmapImage: CGImage? = nil
    @State private var contourImage: CGImage? = nil
    @State private var renderTask: Task<Void, Never>? = nil
    @State private var pointAdditionGestureState = PointAdditionGestureState()

    private var filteredSamples: [WifiSample] {
        sampleFilter.apply(to: points)
    }

    private var filteredPoints: [SurveyPoint] {
        let visibleIDs = Set(filteredSamples.map(\.id))
        return points.filter { visibleIDs.contains($0.id) }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                floorPlanImage(geo.size)
                HeatmapCanvas(image: showHeatmap ? heatmapImage : nil, displayRect: imageRect(in: geo.size))
                HeatmapCanvas(
                    image: showContours ? contourImage : nil,
                    displayRect: imageRect(in: geo.size),
                    opacity: 1
                )
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(mapGesture(in: geo.size))
                SampleMarkersView(
                    points: filteredPoints,
                    imageSize: imageNaturalSize,
                    displayRect: imageRect(in: geo.size),
                    selectedPointID: $selectedPointID,
                    isDeleteMode: isDeleteMode,
                    isInteractionEnabled: ExistingPointInteractionPolicy.isEnabled(
                        isCalibrating: isCalibrating,
                        isCaptureInProgress: isCaptureInProgress
                    ),
                    onMovePoint: onMovePoint,
                    onSetPointOrientation: onSetPointOrientation,
                    onDelete: onDelete
                )
                if let pendingPoint {
                    PendingPointMarker(
                        pendingPoint: pendingPoint,
                        imageSize: imageNaturalSize,
                        displayRect: imageRect(in: geo.size),
                        isScanning: isCaptureInProgress
                    )
                }
                if showHeatmap {
                    HeatmapLegendView(
                        colorScheme: colorScheme,
                        metric: metric,
                        valueRange: valueRange
                    )
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .allowsHitTesting(false)
                }
                if isCalibrating {
                    CalibrationOverlayView(imageSize: geo.size) { cal in
                        floor.calibration = cal
                        onCalibrationComplete()
                    }
                }
            }
        }
        .onChange(of: points)             { recomputeHeatmap() }
        .onChange(of: sampleFilter)        { recomputeHeatmap() }
        .onChange(of: colorScheme)         { recomputeHeatmap() }
        .onChange(of: metric)              { recomputeHeatmap() }
        .onChange(of: valueRange)          { recomputeHeatmap() }
        .onChange(of: outerRadius)         { recomputeHeatmap() }
        .onChange(of: showHeatmap)          { recomputeHeatmap() }
        .onChange(of: showContours)         { recomputeHeatmap() }
        .onChange(of: contourSmoothingMeters) { recomputeHeatmap() }
        .onChange(of: filteredPoints.map(\.id)) {
            if let selectedPointID, !filteredPoints.contains(where: { $0.id == selectedPointID }) {
                self.selectedPointID = nil
            }
        }
        .onChange(of: pointAdditionCancellationToken) {
            pointAdditionGestureState.cancel()
            pendingPoint = nil
        }
        .onAppear { recomputeHeatmap() }
        .onDisappear { renderTask?.cancel() }
    }

    private func imageRect(in viewSize: CGSize) -> CGRect {
        guard imageNaturalSize.width > 0, imageNaturalSize.height > 0 else {
            return CGRect(origin: .zero, size: viewSize)
        }
        let imageAspect = imageNaturalSize.width / imageNaturalSize.height
        let viewAspect  = viewSize.width / viewSize.height
        if imageAspect > viewAspect {
            // wider than view — letterboxed top/bottom
            let h = viewSize.width / imageAspect
            return CGRect(x: 0, y: (viewSize.height - h) / 2, width: viewSize.width, height: h)
        } else {
            // taller than view — letterboxed left/right
            let w = viewSize.height * imageAspect
            return CGRect(x: (viewSize.width - w) / 2, y: 0, width: w, height: viewSize.height)
        }
    }

    private var imageNaturalSize: CGSize {
        guard let data = document.imageCache[floor.floorPlanFilename],
              let src  = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth]  as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int
        else { return CGSize(width: 1000, height: 1000) }
        return CGSize(width: w, height: h)
    }

    private func mapGesture(in viewSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard !isCalibrating, !isCaptureInProgress else { return }
                let rect = imageRect(in: viewSize)
                guard rect.contains(value.startLocation) else { return }
                guard !isDeleteMode else { return }
                pointAdditionGestureState.beginIfNeeded()
                guard pointAdditionGestureState.acceptsUpdates else { return }

                selectedPointID = nil
                pendingPoint = PendingSurveyPoint(
                    position: imagePosition(from: value.startLocation, in: rect),
                    orientationDegrees: PointOrientation.degrees(
                        from: value.startLocation,
                        to: value.location
                    )
                )
            }
            .onEnded { value in
                let rect = imageRect(in: viewSize)
                guard rect.contains(value.startLocation) else { return }

                if isDeleteMode {
                    deleteNearestPoint(to: imagePosition(from: value.startLocation, in: rect), in: rect)
                    return
                }

                guard pointAdditionGestureState.finishShouldCommit() else {
                    pendingPoint = nil
                    return
                }
                guard !isCalibrating, !isCaptureInProgress else {
                    pendingPoint = nil
                    return
                }

                guard var pendingPoint else { return }
                pendingPoint.orientationDegrees = PointOrientation.degrees(
                    from: value.startLocation,
                    to: value.location
                )
                self.pendingPoint = pendingPoint
                onCaptureRequested(pendingPoint)
            }
    }

    private func imagePosition(from displayPosition: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: (displayPosition.x - rect.origin.x) / rect.size.width * imageNaturalSize.width,
            y: (displayPosition.y - rect.origin.y) / rect.size.height * imageNaturalSize.height
        )
    }

    private func deleteNearestPoint(to position: CGPoint, in rect: CGRect) {
        let thresholdPixels = 12 / rect.size.width * imageNaturalSize.width
        guard let nearest = filteredPoints.min(by: {
            hypot($0.position.x - position.x, $0.position.y - position.y) <
                hypot($1.position.x - position.x, $1.position.y - position.y)
        }), hypot(nearest.position.x - position.x, nearest.position.y - position.y) < thresholdPixels
        else { return }
        onDelete(nearest.id)
    }

    @ViewBuilder
    private func floorPlanImage(_ size: CGSize) -> some View {
        if let data = document.imageCache[floor.floorPlanFilename],
           let src  = CGImageSourceCreateWithData(data as CFData, nil),
           let img  = CGImageSourceCreateImageAtIndex(src, 0, nil) {
            Image(img, scale: 1, label: Text("Floor plan"))
                .resizable()
                .scaledToFit()
        } else {
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .overlay {
                    VStack(spacing: 12) {
                        Text("Import a floor plan to get started")
                            .foregroundStyle(.secondary)

                        Button(action: onImport) {
                            Label("Import Floor Plan\u{2026}", systemImage: "photo")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
        }
    }

    private func recomputeHeatmap() {
        renderTask?.cancel()
        guard let cal = floor.calibration else {
            heatmapImage = nil
            contourImage = nil
            return
        }
        let samples = filteredSamples
        let band    = sampleFilter.band
        let scheme  = colorScheme
        let radius  = outerRadius
        let met     = metric
        let range   = valueRange
        let imgSize = imageNaturalSize
        let includeHeatmap = showHeatmap
        let includeContours = showContours && metric != .channel
        let smoothing = contourSmoothingMeters
        renderTask = Task.detached(priority: .userInitiated) {
            let grid = IDWInterpolator.interpolate(samples: samples, calibration: cal, band: band,
                                                   imageSize: imgSize, outerRadius: radius, metric: met)
            let heatmap = includeHeatmap ? HeatmapRenderer.render(
                grid: grid, colorScheme: scheme, metric: met, valueRange: range
            ) : nil
            let contours = includeContours ? ContourRenderer.render(
                grid: grid, metric: met, valueRange: range,
                calibration: cal, imageSize: imgSize,
                smoothingMeters: smoothing
            ) : nil
            guard !Task.isCancelled else { return }
            await MainActor.run {
                heatmapImage = heatmap
                contourImage = contours
            }
        }
    }
}
