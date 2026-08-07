import SwiftUI
import ImageIO

struct FloorPlanView: View {
    @ObservedObject var document: WifiSurveyDocument
    @Binding var floor: Floor
    let activeBand: WiFiBand
    let showHeatmap: Bool
    let colorScheme: HeatmapColorScheme
    let outerRadius: Double
    let isCalibrating: Bool
    let onTap: (CGPoint) -> Void

    @State private var heatmapImage: CGImage? = nil
    @State private var renderTask: Task<Void, Never>? = nil

    var body: some View {
        GeometryReader { geo in
            ZStack {
                floorPlanImage(geo.size)
                HeatmapCanvas(image: showHeatmap ? heatmapImage : nil, displayRect: imageRect(in: geo.size))
                SampleMarkersView(
                    samples: floor.samples.filter { $0.band == activeBand },
                    imageSize: imageNaturalSize,
                    displayRect: imageRect(in: geo.size)
                )
                if isCalibrating {
                    CalibrationOverlayView(imageSize: geo.size) { cal in
                        floor.calibration = cal
                    }
                } else {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { loc in
                            let rect = imageRect(in: geo.size)
                            guard rect.contains(loc) else { return }
                            let px = (loc.x - rect.origin.x) / rect.size.width  * imageNaturalSize.width
                            let py = (loc.y - rect.origin.y) / rect.size.height * imageNaturalSize.height
                            onTap(CGPoint(x: px, y: py))
                        }
                }
            }
        }
        .onChange(of: floor.samples.count) { recomputeHeatmap() }
        .onChange(of: activeBand)          { recomputeHeatmap() }
        .onChange(of: colorScheme)         { recomputeHeatmap() }
        .onChange(of: outerRadius)         { recomputeHeatmap() }
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
                .overlay(Text("Import a floor plan to get started").foregroundStyle(.secondary))
        }
    }

    private func recomputeHeatmap() {
        renderTask?.cancel()
        guard let cal = floor.calibration else { heatmapImage = nil; return }
        let samples = floor.samples
        let band    = activeBand
        let scheme  = colorScheme
        let radius  = outerRadius
        let imgSize = imageNaturalSize
        renderTask = Task.detached(priority: .userInitiated) {
            let grid = IDWInterpolator.interpolate(samples: samples, calibration: cal, band: band, imageSize: imgSize, outerRadius: radius)
            let img  = HeatmapRenderer.render(grid: grid, colorScheme: scheme)
            guard !Task.isCancelled else { return }
            await MainActor.run { heatmapImage = img }
        }
    }
}
