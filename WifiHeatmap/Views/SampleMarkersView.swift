import SwiftUI

struct SampleMarkersView: View {
    let samples: [WifiSample]
    let imageSize: CGSize   // original floor plan pixel dimensions

    var body: some View {
        Canvas { ctx, size in
            for sample in samples {
                let sx = sample.position.x / imageSize.width  * size.width
                let sy = sample.position.y / imageSize.height * size.height
                let rect = CGRect(x: sx - 5, y: sy - 5, width: 10, height: 10)
                ctx.fill(Circle().path(in: rect), with: .color(.white.opacity(0.8)))
                ctx.stroke(Circle().path(in: rect), with: .color(.black.opacity(0.6)), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }
}
