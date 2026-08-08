import SwiftUI

struct SampleMarkersView: View {
    let samples: [WifiSample]
    let imageSize: CGSize
    let displayRect: CGRect
    var isDeleteMode: Bool = false

    var body: some View {
        Canvas { ctx, _ in
            for sample in samples {
                let sx = displayRect.origin.x + (sample.position.x / imageSize.width) * displayRect.size.width
                let sy = displayRect.origin.y + (sample.position.y / imageSize.height) * displayRect.size.height
                let rect = CGRect(x: sx - 5, y: sy - 5, width: 10, height: 10)
                ctx.fill(Circle().path(in: rect), with: .color(.white.opacity(0.8)))
                let strokeColor: Color = isDeleteMode ? .red : .black.opacity(0.6)
                ctx.stroke(Circle().path(in: rect), with: .color(strokeColor),
                           lineWidth: isDeleteMode ? 2 : 1)
            }
        }
        .allowsHitTesting(false)
    }
}
