import CoreGraphics
import CoreFoundation
import CoreText
import AppKit

enum HeatmapRenderer {
    static let minRSSI: Float = -90
    static let maxRSSI: Float = -20

    static func valueRange(for metric: HeatmapMetric) -> (min: Float, max: Float) {
        switch metric {
        case .rssi:    return (minRSSI, maxRSSI)
        case .snr:     return (0, 40)
        case .channel: return (0, 0)
        }
    }

    static func render(
        grid: [[IDWInterpolator.Cell?]],
        colorScheme: HeatmapColorScheme = .classic,
        metric: HeatmapMetric = .rssi,
        valueRange: HeatmapValueRange? = nil
    ) -> CGImage? {
        let size = IDWInterpolator.gridSize
        let bytesPerRow = size * 4
        let totalBytes = size * bytesPerRow

        guard let mutableData = CFDataCreateMutable(nil, totalBytes) else { return nil }
        CFDataSetLength(mutableData, totalBytes)
        guard let bytes = CFDataGetMutableBytePtr(mutableData) else { return nil }
        let pixels = UnsafeMutableBufferPointer<UInt8>(start: bytes, count: totalBytes)

        for i in 0..<totalBytes { pixels[i] = 0 }

        let selectedRange = valueRange ?? metric.defaultValueRange
        let rangeMin = Float(selectedRange.lowerBound)
        let rangeMax = Float(selectedRange.upperBound)

        for row in 0..<size {
            for col in 0..<size {
                guard let cell = grid[row][col], cell.alpha > 0 else { continue }
                let idx = (row * size + col) * 4
                let (r, g, b): (UInt8, UInt8, UInt8)
                if metric == .channel {
                    (r, g, b) = channelColor(channel: Int(cell.value))
                } else {
                    (r, g, b) = gradientColor(value: cell.value, min: rangeMin, max: rangeMax,
                                              scheme: colorScheme)
                }
                let a = cell.alpha
                pixels[idx]   = UInt8(Float(r) * a)
                pixels[idx+1] = UInt8(Float(g) * a)
                pixels[idx+2] = UInt8(Float(b) * a)
                pixels[idx+3] = UInt8(a * 255)
            }
        }

        guard let provider = CGDataProvider(data: mutableData) else { return nil }
        return CGImage(
            width: size, height: size,
            bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil, shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    static func gradientColor(value: Float, min: Float, max: Float,
                              scheme: HeatmapColorScheme) -> (UInt8, UInt8, UInt8) {
        let clamped = Swift.max(min, Swift.min(max, value))
        let t = (clamped - min) / (max - min)
        switch scheme {
        case .classic:
            let hue = CGFloat(t * (240.0 / 360.0))
            return hsbToRGB(hue: hue, saturation: 1, brightness: 1)
        case .trafficLight:
            let hue = CGFloat(t * (120.0 / 360.0))
            return hsbToRGB(hue: hue, saturation: 0.9, brightness: 0.85)
        case .colorblindSafe:
            let r = UInt8(lerp(0,   230, t))
            let g = UInt8(lerp(114, 159, t))
            let b = UInt8(lerp(178,   0, t))
            return (r, g, b)
        }
    }

    private static func channelColor(channel: Int) -> (UInt8, UInt8, UInt8) {
        let hue = CGFloat(channel % 12) / 12.0
        return hsbToRGB(hue: hue, saturation: 0.8, brightness: 0.9)
    }

    private static func hsbToRGB(hue: CGFloat, saturation: CGFloat,
                                  brightness: CGFloat) -> (UInt8, UInt8, UInt8) {
        let c = NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: nil)
        return (UInt8(r * 255), UInt8(g * 255), UInt8(b * 255))
    }

    private static func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
        a + (b - a) * t
    }
}

struct ContourLine: Equatable {
    let level: Float
    let points: [CGPoint]

    var isMajor: Bool {
        Int(abs(level.rounded())) % 20 == 0
    }
}

enum ContourGenerator {
    static let interval: Float = 10
    static let minimumConfidenceAlpha: Float = 0.15
    static let minimumSeparationMeters: Double = 0.75

    private struct Segment {
        let start: CGPoint
        let end: CGPoint
    }

    private struct PointKey: Hashable {
        let x: Int
        let y: Int

        init(_ point: CGPoint) {
            x = Int((point.x * 1_000_000).rounded())
            y = Int((point.y * 1_000_000).rounded())
        }
    }

    static func levels(for metric: HeatmapMetric, valueRange: HeatmapValueRange) -> [Float] {
        guard metric != .channel, valueRange.upperBound > valueRange.lowerBound else { return [] }
        let lower = Float(valueRange.lowerBound)
        let upper = Float(valueRange.upperBound)
        var value = (floor(lower / interval) + 1) * interval
        var result: [Float] = []
        while value < upper {
            result.append(value)
            value += interval
        }
        return result
    }

    static func generate(
        grid: [[IDWInterpolator.Cell?]],
        metric: HeatmapMetric,
        valueRange: HeatmapValueRange,
        imageSize: CGSize,
        metersPerPixel: Double,
        smoothingMeters: Double = 1.0
    ) -> [ContourLine] {
        let smoothedGrid = smooth(
            grid: grid,
            radiusMeters: smoothingMeters,
            imageSize: imageSize,
            metersPerPixel: metersPerPixel
        )
        let candidates = levels(for: metric, valueRange: valueRange).flatMap {
            lines(in: smoothedGrid, level: $0)
        }
        return enforceMinimumSeparation(
            candidates,
            imageSize: imageSize,
            metersPerPixel: metersPerPixel,
            minimumMeters: minimumSeparationMeters
        )
    }

    static func smooth(
        grid: [[IDWInterpolator.Cell?]],
        radiusMeters: Double,
        imageSize: CGSize,
        metersPerPixel: Double
    ) -> [[IDWInterpolator.Cell?]] {
        guard radiusMeters > 0,
              metersPerPixel > 0,
              grid.count >= 2,
              let columnCount = grid.first?.count,
              columnCount >= 2,
              grid.allSatisfy({ $0.count == columnCount }) else { return grid }

        let rowCount = grid.count
        let horizontalSpacing = imageSize.width / CGFloat(columnCount - 1) * metersPerPixel
        let verticalSpacing = imageSize.height / CGFloat(rowCount - 1) * metersPerPixel
        guard horizontalSpacing > 0, verticalSpacing > 0 else { return grid }

        let horizontalKernel = gaussianKernel(radiusInCells: radiusMeters / horizontalSpacing)
        let verticalKernel = gaussianKernel(radiusInCells: radiusMeters / verticalSpacing)
        let horizontal = blur(grid: grid, kernel: horizontalKernel, horizontal: true)
        return blur(grid: horizontal, kernel: verticalKernel, horizontal: false)
    }

    private static func gaussianKernel(radiusInCells: Double) -> [Double] {
        let support = max(1, min(24, Int(ceil(radiusInCells))))
        let sigma = max(0.5, radiusInCells / 2)
        return (-support...support).map { offset in
            exp(-0.5 * pow(Double(offset) / sigma, 2))
        }
    }

    private static func blur(
        grid: [[IDWInterpolator.Cell?]],
        kernel: [Double],
        horizontal: Bool
    ) -> [[IDWInterpolator.Cell?]] {
        let rowCount = grid.count
        let columnCount = grid[0].count
        let support = kernel.count / 2
        var result = grid

        for row in 0..<rowCount {
            for column in 0..<columnCount {
                guard let source = grid[row][column] else {
                    result[row][column] = nil
                    continue
                }
                var weightedValue = 0.0
                var totalWeight = 0.0
                for offset in -support...support {
                    let neighborRow = horizontal ? row : row + offset
                    let neighborColumn = horizontal ? column + offset : column
                    guard grid.indices.contains(neighborRow),
                          grid[neighborRow].indices.contains(neighborColumn),
                          let neighbor = grid[neighborRow][neighborColumn] else { continue }
                    let weight = kernel[offset + support] * Double(neighbor.alpha)
                    weightedValue += Double(neighbor.value) * weight
                    totalWeight += weight
                }
                guard totalWeight > 0 else { continue }
                result[row][column] = IDWInterpolator.Cell(
                    value: Float(weightedValue / totalWeight),
                    alpha: source.alpha
                )
            }
        }
        return result
    }

    static func lines(
        in grid: [[IDWInterpolator.Cell?]],
        level: Float
    ) -> [ContourLine] {
        guard grid.count >= 2, let columnCount = grid.first?.count, columnCount >= 2,
              grid.allSatisfy({ $0.count == columnCount }) else { return [] }

        let rowCount = grid.count
        var segments: [Segment] = []

        for row in 0..<(rowCount - 1) {
            for column in 0..<(columnCount - 1) {
                guard let topLeft = grid[row][column],
                      let topRight = grid[row][column + 1],
                      let bottomRight = grid[row + 1][column + 1],
                      let bottomLeft = grid[row + 1][column],
                      min(topLeft.alpha, topRight.alpha, bottomRight.alpha, bottomLeft.alpha)
                        >= minimumConfidenceAlpha else { continue }

                let corners = [topLeft, topRight, bottomRight, bottomLeft]
                let points = [
                    CGPoint(x: column, y: row),
                    CGPoint(x: column + 1, y: row),
                    CGPoint(x: column + 1, y: row + 1),
                    CGPoint(x: column, y: row + 1)
                ]
                let edgePairs = [(0, 1), (1, 2), (3, 2), (0, 3)]
                var crossings: [CGPoint] = []

                for (first, second) in edgePairs {
                    let firstValue = corners[first].value
                    let secondValue = corners[second].value
                    guard (firstValue < level) != (secondValue < level) else { continue }
                    crossings.append(intersection(
                        from: points[first], value: firstValue,
                        to: points[second], value: secondValue,
                        level: level,
                        columnCount: columnCount,
                        rowCount: rowCount
                    ))
                }

                if crossings.count == 2 {
                    segments.append(Segment(start: crossings[0], end: crossings[1]))
                } else if crossings.count == 4 {
                    let centerIsHigh = corners.map(\.value).reduce(0, +) / 4 >= level
                    if centerIsHigh {
                        segments.append(Segment(start: crossings[0], end: crossings[3]))
                        segments.append(Segment(start: crossings[1], end: crossings[2]))
                    } else {
                        segments.append(Segment(start: crossings[0], end: crossings[1]))
                        segments.append(Segment(start: crossings[2], end: crossings[3]))
                    }
                }
            }
        }

        return stitch(segments).map { ContourLine(level: level, points: $0) }
    }

    static func enforceMinimumSeparation(
        _ lines: [ContourLine],
        imageSize: CGSize,
        metersPerPixel: Double,
        minimumMeters: Double
    ) -> [ContourLine] {
        guard minimumMeters > 0, metersPerPixel > 0 else { return lines }
        let prioritized = lines.enumerated().sorted { lhs, rhs in
            if lhs.element.isMajor != rhs.element.isMajor { return lhs.element.isMajor }
            return lhs.offset < rhs.offset
        }
        var accepted: [(index: Int, line: ContourLine)] = []

        for candidate in prioritized {
            let isCrowded = accepted.contains { existing in
                existing.line.level != candidate.element.level
                    && physicalDistance(
                        between: candidate.element,
                        and: existing.line,
                        imageSize: imageSize,
                        metersPerPixel: metersPerPixel
                    ) < minimumMeters
            }
            if !isCrowded { accepted.append((candidate.offset, candidate.element)) }
        }

        return accepted.sorted { $0.index < $1.index }.map(\.line)
    }

    private static func intersection(
        from start: CGPoint,
        value startValue: Float,
        to end: CGPoint,
        value endValue: Float,
        level: Float,
        columnCount: Int,
        rowCount: Int
    ) -> CGPoint {
        let denominator = endValue - startValue
        let fraction = denominator == 0 ? 0.5 : CGFloat((level - startValue) / denominator)
        let x = start.x + (end.x - start.x) * fraction
        let y = start.y + (end.y - start.y) * fraction
        return CGPoint(
            x: x / CGFloat(columnCount - 1),
            y: y / CGFloat(rowCount - 1)
        )
    }

    private static func stitch(_ segments: [Segment]) -> [[CGPoint]] {
        guard !segments.isEmpty else { return [] }
        var adjacency: [PointKey: [Int]] = [:]
        for (index, segment) in segments.enumerated() {
            adjacency[PointKey(segment.start), default: []].append(index)
            adjacency[PointKey(segment.end), default: []].append(index)
        }

        var unused = Set(segments.indices)
        var result: [[CGPoint]] = []
        while let firstIndex = unused.first {
            unused.remove(firstIndex)
            let first = segments[firstIndex]
            var points = [first.start, first.end]
            extend(&points, atEnd: true, segments: segments, adjacency: adjacency, unused: &unused)
            extend(&points, atEnd: false, segments: segments, adjacency: adjacency, unused: &unused)
            result.append(points)
        }
        return result
    }

    private static func extend(
        _ points: inout [CGPoint],
        atEnd: Bool,
        segments: [Segment],
        adjacency: [PointKey: [Int]],
        unused: inout Set<Int>
    ) {
        while let endpoint = atEnd ? points.last : points.first,
              let nextIndex = adjacency[PointKey(endpoint)]?.first(where: { unused.contains($0) }) {
            unused.remove(nextIndex)
            let segment = segments[nextIndex]
            let nextPoint = PointKey(segment.start) == PointKey(endpoint) ? segment.end : segment.start
            if atEnd { points.append(nextPoint) }
            else { points.insert(nextPoint, at: 0) }
        }
    }

    private static func physicalDistance(
        between first: ContourLine,
        and second: ContourLine,
        imageSize: CGSize,
        metersPerPixel: Double
    ) -> Double {
        let firstPoints = first.points.map { physicalPoint($0, imageSize: imageSize, metersPerPixel: metersPerPixel) }
        let secondPoints = second.points.map { physicalPoint($0, imageSize: imageSize, metersPerPixel: metersPerPixel) }
        guard firstPoints.count >= 2, secondPoints.count >= 2 else { return .infinity }
        var closest = Double.infinity
        for point in firstPoints {
            for index in 0..<(secondPoints.count - 1) {
                closest = min(closest, distance(point, toSegmentFrom: secondPoints[index], to: secondPoints[index + 1]))
            }
        }
        for point in secondPoints {
            for index in 0..<(firstPoints.count - 1) {
                closest = min(closest, distance(point, toSegmentFrom: firstPoints[index], to: firstPoints[index + 1]))
            }
        }
        return closest
    }

    private static func physicalPoint(
        _ point: CGPoint,
        imageSize: CGSize,
        metersPerPixel: Double
    ) -> CGPoint {
        CGPoint(
            x: point.x * imageSize.width * metersPerPixel,
            y: point.y * imageSize.height * metersPerPixel
        )
    }

    private static func distance(_ point: CGPoint, toSegmentFrom start: CGPoint, to end: CGPoint) -> Double {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(point.x - start.x, point.y - start.y) }
        let projection = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        let nearest = CGPoint(x: start.x + projection * dx, y: start.y + projection * dy)
        return hypot(point.x - nearest.x, point.y - nearest.y)
    }
}

enum ContourRenderer {
    static func isReservedLabelArea(_ rect: CGRect, imageSize: CGSize) -> Bool {
        let titleArea = CGRect(
            x: 0,
            y: imageSize.height * 0.84,
            width: imageSize.width * 0.72,
            height: imageSize.height * 0.16
        )
        let legendArea = CGRect(
            x: 0,
            y: 0,
            width: imageSize.width * 0.30,
            height: imageSize.height * 0.20
        )
        return rect.intersects(titleArea) || rect.intersects(legendArea)
    }

    static func render(
        grid: [[IDWInterpolator.Cell?]],
        metric: HeatmapMetric,
        valueRange: HeatmapValueRange,
        calibration: Calibration,
        imageSize: CGSize,
        smoothingMeters: Double = 1.0
    ) -> CGImage? {
        guard metric != .channel, imageSize.width >= 1, imageSize.height >= 1 else { return nil }
        let lines = ContourGenerator.generate(
            grid: grid,
            metric: metric,
            valueRange: valueRange,
            imageSize: imageSize,
            metersPerPixel: calibration.metersPerPixel,
            smoothingMeters: smoothingMeters
        )
        guard !lines.isEmpty else { return nil }
        return render(lines: lines, metric: metric, imageSize: imageSize)
    }

    static func render(lines: [ContourLine], metric: HeatmapMetric, imageSize: CGSize) -> CGImage? {
        let width = max(1, Int(imageSize.width.rounded()))
        let height = max(1, Int(imageSize.height.rounded()))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setLineCap(.round)
        context.setLineJoin(.round)
        let scale = max(0.75, min(2.5, min(imageSize.width, imageSize.height) / 700))
        for line in lines where line.points.count >= 2 {
            let path = path(for: line, imageSize: imageSize)
            context.addPath(path)
            context.setStrokeColor(CGColor(gray: 1, alpha: 0.88))
            context.setLineWidth((line.isMajor ? 4.5 : 3.5) * scale)
            context.strokePath()
            context.addPath(path)
            context.setStrokeColor(CGColor(gray: 0.08, alpha: 0.86))
            context.setLineWidth((line.isMajor ? 2.0 : 1.4) * scale)
            context.strokePath()
        }
        drawLabels(for: lines, metric: metric, imageSize: imageSize, scale: scale, in: context)
        return context.makeImage()
    }

    private static func path(for line: ContourLine, imageSize: CGSize) -> CGPath {
        let path = CGMutablePath()
        guard let first = line.points.first else { return path }
        path.move(to: renderPoint(first, imageSize: imageSize))
        for point in line.points.dropFirst() {
            path.addLine(to: renderPoint(point, imageSize: imageSize))
        }
        return path
    }

    private static func renderPoint(_ point: CGPoint, imageSize: CGSize) -> CGPoint {
        CGPoint(x: point.x * imageSize.width, y: (1 - point.y) * imageSize.height)
    }

    private static func drawLabels(
        for lines: [ContourLine],
        metric: HeatmapMetric,
        imageSize: CGSize,
        scale: CGFloat,
        in context: CGContext
    ) {
        var occupied: [CGRect] = []
        var countByLevel: [Float: Int] = [:]
        let fontSize = max(10, min(24, 12 * scale))

        for line in lines {
            guard countByLevel[line.level, default: 0] < 2,
                  let placement = midpointPlacement(for: line, imageSize: imageSize),
                  placement.length >= 90 * scale else { continue }
            let unit = metric == .rssi ? "dBm" : "dB"
            let number = Int(line.level.rounded())
            let text = "\(number < 0 ? "\u{2212}\(abs(number))" : "\(number)") \(unit)"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
            let attributed = NSAttributedString(string: text, attributes: attributes)
            let textLine = CTLineCreateWithAttributedString(attributed)
            let textWidth = CGFloat(CTLineGetTypographicBounds(textLine, nil, nil, nil))
            let box = CGRect(
                x: placement.point.x - textWidth / 2 - 6 * scale,
                y: placement.point.y - fontSize / 2 - 4 * scale,
                width: textWidth + 12 * scale,
                height: fontSize + 8 * scale
            )
            guard !isReservedLabelArea(box, imageSize: imageSize),
                  !occupied.contains(where: { $0.insetBy(dx: -8 * scale, dy: -5 * scale).intersects(box) }) else {
                continue
            }

            var angle = placement.angle
            if cos(angle) < 0 { angle += .pi }
            context.saveGState()
            context.translateBy(x: placement.point.x, y: placement.point.y)
            context.rotate(by: angle)
            let background = CGRect(
                x: -textWidth / 2 - 5 * scale,
                y: -fontSize / 2 - 3 * scale,
                width: textWidth + 10 * scale,
                height: fontSize + 6 * scale
            )
            context.addPath(CGPath(roundedRect: background, cornerWidth: 4 * scale, cornerHeight: 4 * scale, transform: nil))
            context.setFillColor(CGColor(gray: 0.05, alpha: 0.78))
            context.fillPath()
            context.textPosition = CGPoint(x: -textWidth / 2, y: -fontSize * 0.36)
            CTLineDraw(textLine, context)
            context.restoreGState()

            occupied.append(box)
            countByLevel[line.level, default: 0] += 1
        }
    }

    private static func midpointPlacement(
        for line: ContourLine,
        imageSize: CGSize
    ) -> (point: CGPoint, angle: CGFloat, length: CGFloat)? {
        let points = line.points.map { renderPoint($0, imageSize: imageSize) }
        guard points.count >= 2 else { return nil }
        let lengths = zip(points, points.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }
        let total = lengths.reduce(0, +)
        guard total > 0 else { return nil }
        let target = total / 2
        var traversed: CGFloat = 0
        for index in lengths.indices {
            let segmentLength = lengths[index]
            if traversed + segmentLength >= target {
                let fraction = (target - traversed) / segmentLength
                let start = points[index]
                let end = points[index + 1]
                return (
                    CGPoint(x: start.x + (end.x - start.x) * fraction,
                            y: start.y + (end.y - start.y) * fraction),
                    atan2(end.y - start.y, end.x - start.x),
                    total
                )
            }
            traversed += segmentLength
        }
        return nil
    }
}

struct ExportLegend: Equatable {
    let colorScheme: HeatmapColorScheme
    let metric: HeatmapMetric
    let valueRange: HeatmapValueRange
}

enum ExportOverlayRenderer {
    static func draw(
        floorName: String?,
        legend: ExportLegend?,
        canvasSize: CGSize,
        in context: CGContext
    ) {
        let scale = max(0.8, min(2.5, min(canvasSize.width, canvasSize.height) / 650))
        let margin = 14 * scale
        if let floorName, !floorName.isEmpty {
            drawTitle(floorName, canvasSize: canvasSize, margin: margin, scale: scale, in: context)
        }
        if let legend {
            drawLegend(legend, canvasSize: canvasSize, margin: margin, scale: scale, in: context)
        }
    }

    private static func drawTitle(
        _ title: String,
        canvasSize: CGSize,
        margin: CGFloat,
        scale: CGFloat,
        in context: CGContext
    ) {
        let fontSize = 22 * scale
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let attributed = NSAttributedString(string: title, attributes: attributes)
        let sourceLine = CTLineCreateWithAttributedString(attributed)
        let naturalWidth = CGFloat(CTLineGetTypographicBounds(sourceLine, nil, nil, nil))
        let maximumTextWidth = max(80, canvasSize.width * 0.66 - 24 * scale)
        let textWidth = min(naturalWidth, maximumTextWidth)
        let height = fontSize + 18 * scale
        let panel = CGRect(
            x: margin,
            y: canvasSize.height - margin - height,
            width: textWidth + 24 * scale,
            height: height
        )
        fillPanel(panel, radius: 9 * scale, in: context)
        let line = CTLineCreateTruncatedLine(sourceLine, Double(maximumTextWidth), .end, nil) ?? sourceLine
        context.textPosition = CGPoint(x: panel.minX + 12 * scale, y: panel.midY - fontSize * 0.36)
        CTLineDraw(line, context)
    }

    private static func drawLegend(
        _ legend: ExportLegend,
        canvasSize: CGSize,
        margin: CGFloat,
        scale: CGFloat,
        in context: CGContext
    ) {
        let panel = CGRect(x: margin, y: margin, width: 190 * scale, height: 78 * scale)
        fillPanel(panel, radius: 9 * scale, in: context)
        let titleFont = NSFont.systemFont(ofSize: 12 * scale, weight: .semibold)
        drawText(
            legend.metric.displayName,
            font: titleFont,
            color: .white,
            at: CGPoint(x: panel.minX + 11 * scale, y: panel.maxY - 21 * scale),
            in: context
        )

        if legend.metric == .channel {
            drawText(
                "Colors by channel number",
                font: NSFont.systemFont(ofSize: 10 * scale),
                color: NSColor.white.withAlphaComponent(0.82),
                at: CGPoint(x: panel.minX + 11 * scale, y: panel.minY + 18 * scale),
                in: context
            )
            return
        }

        let gradientRect = CGRect(
            x: panel.minX + 11 * scale,
            y: panel.minY + 30 * scale,
            width: panel.width - 22 * scale,
            height: 12 * scale
        )
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let colors: [CGColor] = (0..<8).map { index in
            let fraction = Float(index) / 7
            let minimum = Float(legend.valueRange.lowerBound)
            let maximum = Float(legend.valueRange.upperBound)
            let value = minimum + (maximum - minimum) * fraction
            let (red, green, blue) = HeatmapRenderer.gradientColor(
                value: value,
                min: minimum,
                max: maximum,
                scheme: legend.colorScheme
            )
            return CGColor(
                red: CGFloat(red) / 255,
                green: CGFloat(green) / 255,
                blue: CGFloat(blue) / 255,
                alpha: 1
            )
        }
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: nil) {
            context.saveGState()
            context.addPath(CGPath(roundedRect: gradientRect, cornerWidth: 3 * scale, cornerHeight: 3 * scale, transform: nil))
            context.clip()
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: gradientRect.minX, y: gradientRect.midY),
                end: CGPoint(x: gradientRect.maxX, y: gradientRect.midY),
                options: []
            )
            context.restoreGState()
        }

        let unit = legend.metric == .rssi ? "dBm" : "dB"
        let minimum = "\(Int(legend.valueRange.lowerBound.rounded())) \(unit)"
        let maximum = "\(Int(legend.valueRange.upperBound.rounded())) \(unit)"
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 9.5 * scale, weight: .regular)
        drawText(
            minimum,
            font: valueFont,
            color: NSColor.white.withAlphaComponent(0.84),
            at: CGPoint(x: gradientRect.minX, y: panel.minY + 12 * scale),
            in: context
        )
        let maximumWidth = textWidth(maximum, font: valueFont)
        drawText(
            maximum,
            font: valueFont,
            color: NSColor.white.withAlphaComponent(0.84),
            at: CGPoint(x: gradientRect.maxX - maximumWidth, y: panel.minY + 12 * scale),
            in: context
        )
    }

    private static func fillPanel(_ rect: CGRect, radius: CGFloat, in context: CGContext) {
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.setFillColor(CGColor(gray: 0.04, alpha: 0.72))
        context.fillPath()
    }

    private static func drawText(
        _ text: String,
        font: NSFont,
        color: NSColor,
        at point: CGPoint,
        in context: CGContext
    ) {
        let attributed = NSAttributedString(
            string: text,
            attributes: [.font: font, .foregroundColor: color]
        )
        context.textPosition = point
        CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
    }

    private static func textWidth(_ text: String, font: NSFont) -> CGFloat {
        let attributed = NSAttributedString(string: text, attributes: [.font: font])
        return CGFloat(CTLineGetTypographicBounds(
            CTLineCreateWithAttributedString(attributed), nil, nil, nil
        ))
    }
}
