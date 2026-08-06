import SwiftUI

struct CalibrationOverlayView: View {
    let imageSize: CGSize
    let onComplete: (Calibration) -> Void

    private enum State {
        case idle
        case firstPointSet(CGPoint)
        case awaitingDistance(CGPoint, CGPoint)
    }

    @SwiftUI.State private var state: State = .idle
    @SwiftUI.State private var distanceText = ""
    @SwiftUI.State private var showSheet = false
    @SwiftUI.State private var pendingPoints: (CGPoint, CGPoint)? = nil

    var body: some View {
        ZStack {
            // Tap-to-set crosshairs
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { location in
                    handleTap(at: location)
                }

            // Draw crosshairs at set points
            Canvas { ctx, size in
                if case .firstPointSet(let p) = state {
                    drawCrosshair(ctx: ctx, at: p, size: size)
                }
                if case .awaitingDistance(let p1, let p2) = state {
                    drawCrosshair(ctx: ctx, at: p1, size: size)
                    drawCrosshair(ctx: ctx, at: p2, size: size)
                }
            }
            .allowsHitTesting(false)
        }
        .sheet(isPresented: $showSheet) {
            distanceSheet
        }
    }

    private var distanceSheet: some View {
        VStack(spacing: 16) {
            Text("Enter the real-world distance between the two marked points.")
                .multilineTextAlignment(.center)
            HStack {
                TextField("Distance", text: $distanceText)
                    .frame(width: 100)
                    .textFieldStyle(.roundedBorder)
                Text("meters")
            }
            HStack {
                Button("Cancel") {
                    state = .idle
                    showSheet = false
                }
                Button("Set Calibration") {
                    guard let dist = Double(distanceText),
                          dist > 0,
                          let (p1, p2) = pendingPoints else { return }
                    let cal = Calibration(
                        pointA: p1,
                        pointB: p2,
                        realWorldDistanceMeters: dist
                    )
                    onComplete(cal)
                    state = .idle
                    showSheet = false
                    distanceText = ""
                    pendingPoints = nil
                }
                .buttonStyle(.borderedProminent)
                .disabled(Double(distanceText).flatMap { $0 > 0 ? $0 : nil } == nil)
            }
        }
        .padding(24)
        .frame(minWidth: 300)
    }

    private func handleTap(at location: CGPoint) {
        switch state {
        case .idle:
            state = .firstPointSet(location)
        case .firstPointSet(let first):
            pendingPoints = (first, location)
            state = .awaitingDistance(first, location)
            distanceText = ""
            showSheet = true
        case .awaitingDistance:
            break
        }
    }

    private func drawCrosshair(ctx: GraphicsContext, at point: CGPoint, size: CGSize) {
        let arm: CGFloat = 12
        var h = Path(); h.move(to: CGPoint(x: point.x - arm, y: point.y))
        h.addLine(to: CGPoint(x: point.x + arm, y: point.y))
        var v = Path(); v.move(to: CGPoint(x: point.x, y: point.y - arm))
        v.addLine(to: CGPoint(x: point.x, y: point.y + arm))
        ctx.stroke(h, with: .color(.yellow), lineWidth: 2)
        ctx.stroke(v, with: .color(.yellow), lineWidth: 2)
    }
}
