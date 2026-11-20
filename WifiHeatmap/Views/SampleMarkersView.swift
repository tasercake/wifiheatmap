import AppKit
import SwiftUI

private enum PointMarkerLayout {
    static let visualScale: CGFloat = 0.7
}

struct PendingSurveyPoint: Equatable {
    var position: CGPoint
    var orientationDegrees: Double?
}

enum PointOrientation {
    static let minimumDragDistance: CGFloat = 8

    static func degrees(
        from start: CGPoint,
        to end: CGPoint,
        minimumDistance: CGFloat = minimumDragDistance
    ) -> Double? {
        let dx = end.x - start.x
        let dy = end.y - start.y
        guard hypot(dx, dy) >= minimumDistance else { return nil }
        return normalized(atan2(dy, dx) * 180 / .pi)
    }

    static func normalized(_ degrees: Double) -> Double {
        let remainder = degrees.truncatingRemainder(dividingBy: 360)
        return remainder >= 0 ? remainder : remainder + 360
    }
}

enum PointRotationPresentation {
    static let minimumDragDistance: CGFloat = 3

    static func displayedDegrees(stored: Double?, preview: Double?) -> Double? {
        preview ?? stored
    }

    static func committedDegrees(from start: CGPoint, to end: CGPoint) -> Double? {
        PointOrientation.degrees(
            from: start,
            to: end,
            minimumDistance: minimumDragDistance
        )
    }
}

enum PointRotationHandleLayout {
    static let ringRadius: CGFloat = 29 * PointMarkerLayout.visualScale
    static let hitTargetDiameter: CGFloat = 32
    static let containerSize: CGFloat = 76
}

struct SampleMarkersView: View {
    let points: [SurveyPoint]
    let imageSize: CGSize
    let displayRect: CGRect
    @Binding var selectedPointID: UUID?
    var isDeleteMode: Bool = false
    var isInteractionEnabled: Bool = true
    var onMovePoint: (UUID, CGPoint) -> Void = { _, _ in }
    var onSetPointOrientation: (UUID, Double?) -> Void = { _, _ in }
    var onDelete: (UUID) -> Void = { _ in }

    var body: some View {
        ZStack {
            ForEach(points) { point in
                CommittedPointMarker(
                    point: point,
                    displayPosition: displayPosition(for: point.position),
                    displayRect: displayRect,
                    imageSize: imageSize,
                    isSelected: selectedPointID == point.id,
                    isDeleteMode: isDeleteMode,
                    isInteractionEnabled: isInteractionEnabled,
                    onSelect: { selectedPointID = point.id },
                    onMove: { onMovePoint(point.id, $0) },
                    onSetOrientation: { onSetPointOrientation(point.id, $0) },
                    onDelete: { onDelete(point.id) }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(name: "floorPlanCanvas")
    }

    private func displayPosition(for imagePosition: CGPoint) -> CGPoint {
        CGPoint(
            x: displayRect.origin.x + (imagePosition.x / imageSize.width) * displayRect.size.width,
            y: displayRect.origin.y + (imagePosition.y / imageSize.height) * displayRect.size.height
        )
    }
}

struct PendingPointMarker: View {
    let pendingPoint: PendingSurveyPoint
    let imageSize: CGSize
    let displayRect: CGRect
    let isScanning: Bool

    var body: some View {
        ZStack {
            if let degrees = pendingPoint.orientationDegrees {
                PointOrientationVector(
                    degrees: degrees,
                    length: 26 * PointMarkerLayout.visualScale,
                    color: .orange
                )
            }

            Circle()
                .stroke(
                    Color.orange.opacity(0.9),
                    style: StrokeStyle(lineWidth: 2, dash: [4, 3])
                )
                .frame(
                    width: 28 * PointMarkerLayout.visualScale,
                    height: 28 * PointMarkerLayout.visualScale
                )

            Circle()
                .fill(Color.orange)
                .frame(
                    width: 12 * PointMarkerLayout.visualScale,
                    height: 12 * PointMarkerLayout.visualScale
                )
                .overlay {
                    Circle().stroke(Color.white.opacity(0.95), lineWidth: 2)
                }
                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)

            if isScanning {
                ProgressView()
                    .controlSize(.small)
                    .padding(5)
                    .background(.regularMaterial, in: Circle())
                    .scaleEffect(PointMarkerLayout.visualScale)
                    .offset(y: -27 * PointMarkerLayout.visualScale)
            }
        }
        .frame(
            width: 72 * PointMarkerLayout.visualScale,
            height: 72 * PointMarkerLayout.visualScale
        )
        .position(displayPosition)
        .allowsHitTesting(false)
        .accessibilityLabel(isScanning ? "Point scanning" : "Pending point")
    }

    private var displayPosition: CGPoint {
        CGPoint(
            x: displayRect.origin.x + (pendingPoint.position.x / imageSize.width) * displayRect.size.width,
            y: displayRect.origin.y + (pendingPoint.position.y / imageSize.height) * displayRect.size.height
        )
    }
}

private struct CommittedPointMarker: View {
    let point: SurveyPoint
    let displayPosition: CGPoint
    let displayRect: CGRect
    let imageSize: CGSize
    let isSelected: Bool
    let isDeleteMode: Bool
    let isInteractionEnabled: Bool
    let onSelect: () -> Void
    let onMove: (CGPoint) -> Void
    let onSetOrientation: (Double?) -> Void
    let onDelete: () -> Void

    @State private var dragPreviewPosition: CGPoint?
    @State private var isHovering = false

    var body: some View {
        ZStack {
            if isSelected {
                RotationHandle(
                    orientationDegrees: point.orientationDegrees,
                    isEnabled: isInteractionEnabled && !isDeleteMode,
                    onSetOrientation: onSetOrientation
                )
            } else if let degrees = point.orientationDegrees {
                PointOrientationVector(
                    degrees: degrees,
                    length: 20 * PointMarkerLayout.visualScale,
                    color: .primary.opacity(0.72)
                )
            }

            markerButton
        }
        .frame(
            width: PointRotationHandleLayout.containerSize,
            height: PointRotationHandleLayout.containerSize
        )
        .position(dragPreviewPosition ?? displayPosition)
        .animation(.snappy(duration: 0.18), value: isSelected)
        .zIndex(isSelected ? 2 : 1)
    }

    private var markerButton: some View {
        ZStack {
            if isSelected {
                Circle()
                    .fill(Color.accentColor.opacity(0.18))
                    .frame(
                        width: 30 * PointMarkerLayout.visualScale,
                        height: 30 * PointMarkerLayout.visualScale
                    )
            }

            Circle()
                .fill(isDeleteMode ? Color.red : (isSelected ? Color.accentColor : Color.white.opacity(0.92)))
                .frame(
                    width: 14 * PointMarkerLayout.visualScale,
                    height: 14 * PointMarkerLayout.visualScale
                )
                .overlay {
                    Circle().stroke(
                        isSelected || isDeleteMode ? Color.white : Color.black.opacity(0.58),
                        lineWidth: isSelected ? 2 : 1
                    )
                }
                .shadow(color: .black.opacity(0.32), radius: isHovering ? 4 : 2, y: 1)
        }
        .frame(width: 30, height: 30)
        .contentShape(Circle())
        .scaleEffect(isHovering && isInteractionEnabled ? 1.08 : 1)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .gesture(moveGesture)
        .onHover { hovering in
            isHovering = hovering
            guard isInteractionEnabled else {
                NSCursor.arrow.set()
                return
            }
            if hovering {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete Point", systemImage: "trash")
            }
            if point.orientationDegrees != nil {
                Button {
                    onSetOrientation(nil)
                } label: {
                    Label("Clear Orientation", systemImage: "arrow.uturn.backward.circle")
                }
            }
        }
        .accessibilityLabel("Survey point")
        .accessibilityHint("Click to select. Drag to reposition.")
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("floorPlanCanvas"))
            .onChanged { value in
                guard isInteractionEnabled else { return }
                onSelect()
                guard !isDeleteMode else { return }
                dragPreviewPosition = clampedDisplayPosition(value.location)
            }
            .onEnded { value in
                defer { dragPreviewPosition = nil }
                guard isInteractionEnabled else { return }
                if isDeleteMode {
                    onDelete()
                    return
                }
                let distance = hypot(
                    value.location.x - value.startLocation.x,
                    value.location.y - value.startLocation.y
                )
                guard distance >= 2 else { return }
                onMove(imagePosition(from: clampedDisplayPosition(value.location)))
            }
    }

    private func clampedDisplayPosition(_ position: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(position.x, displayRect.minX), displayRect.maxX),
            y: min(max(position.y, displayRect.minY), displayRect.maxY)
        )
    }

    private func imagePosition(from position: CGPoint) -> CGPoint {
        CGPoint(
            x: (position.x - displayRect.origin.x) / displayRect.size.width * imageSize.width,
            y: (position.y - displayRect.origin.y) / displayRect.size.height * imageSize.height
        )
    }
}

private struct RotationHandle: View {
    let orientationDegrees: Double?
    let isEnabled: Bool
    let onSetOrientation: (Double?) -> Void

    @State private var previewDegrees: Double?

    private let size = PointRotationHandleLayout.containerSize
    private let radius = PointRotationHandleLayout.ringRadius
    private let coordinateSpaceName = "pointRotationHandle"

    private var displayedDegrees: Double? {
        PointRotationPresentation.displayedDegrees(
            stored: orientationDegrees,
            preview: previewDegrees
        )
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    Color.accentColor.opacity(0.7),
                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                )
                .frame(width: radius * 2, height: radius * 2)
                .allowsHitTesting(false)

            if let displayedDegrees {
                PointOrientationVector(
                    degrees: displayedDegrees,
                    length: radius - 5 * PointMarkerLayout.visualScale,
                    color: .accentColor
                )
            }

            rotationKnob

            rotationHitTarget
        }
        .frame(width: size, height: size)
        .coordinateSpace(name: coordinateSpaceName)
        .allowsHitTesting(isEnabled)
    }

    private var rotationKnob: some View {
        Circle()
            .fill(Color.accentColor)
            .frame(
                width: 18 * PointMarkerLayout.visualScale,
                height: 18 * PointMarkerLayout.visualScale
            )
            .overlay {
                Image(systemName: "arrow.clockwise")
                    .font(.system(
                        size: 9 * PointMarkerLayout.visualScale,
                        weight: .bold
                    ))
                    .foregroundStyle(.white)
            }
            .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
            .offset(handleOffset)
            .allowsHitTesting(false)
    }

    private var rotationHitTarget: some View {
        Circle()
            // A real, generously sized view keeps hit testing inside the
            // marker's bounds. Expanding the tiny visible knob's content shape
            // allowed pointer events to fall through to the map gesture.
            .fill(Color.primary.opacity(0.001))
            .frame(
                width: PointRotationHandleLayout.hitTargetDiameter,
                height: PointRotationHandleLayout.hitTargetDiameter
            )
            .contentShape(Circle())
            .offset(handleOffset)
            .highPriorityGesture(rotationGesture)
            .help("Drag to set device orientation")
            .accessibilityLabel("Rotate point")
    }

    private var handleOffset: CGSize {
        guard let displayedDegrees else {
            return CGSize(width: 0, height: -radius)
        }
        let radians = displayedDegrees * .pi / 180
        return CGSize(width: cos(radians) * radius, height: sin(radians) * radius)
    }

    private var rotationGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpaceName))
            .onChanged { value in
                guard isEnabled else { return }
                guard PointRotationPresentation.committedDegrees(
                    from: value.startLocation,
                    to: value.location
                ) != nil else { return }
                previewDegrees = angle(for: value.location)
            }
            .onEnded { value in
                guard isEnabled else { return }
                defer { previewDegrees = nil }
                guard PointRotationPresentation.committedDegrees(
                    from: value.startLocation,
                    to: value.location
                ) != nil else { return }
                let degrees = angle(for: value.location)
                onSetOrientation(degrees)
            }
    }

    private func angle(for location: CGPoint) -> Double {
        PointOrientation.normalized(
            atan2(location.y - size / 2, location.x - size / 2) * 180 / .pi
        )
    }
}

private struct PointOrientationVector: View {
    let degrees: Double
    let length: CGFloat
    let color: Color

    var body: some View {
        ZStack {
            Capsule()
                .fill(color)
                .frame(width: length, height: 2)
                .offset(x: length / 2)
            Image(systemName: "arrowtriangle.right.fill")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(color)
                .offset(x: length)
        }
        .rotationEffect(.degrees(degrees))
        .allowsHitTesting(false)
    }
}
