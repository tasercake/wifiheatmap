import SwiftUI

struct HeatmapCanvas: View {
    let image: CGImage?
    let displayRect: CGRect

    var body: some View {
        Canvas { ctx, _ in
            guard let img = image else { return }
            ctx.opacity = 0.6
            ctx.draw(Image(img, scale: 1, label: Text("")), in: displayRect)
        }
        .allowsHitTesting(false)
    }
}
