import SwiftUI

struct HeatmapCanvas: View {
    let image: CGImage?
    let displayRect: CGRect
    var opacity: Double = 0.6

    var body: some View {
        Canvas { ctx, _ in
            guard let img = image else { return }
            ctx.opacity = opacity
            ctx.draw(Image(img, scale: 1, label: Text("")), in: displayRect)
        }
        .allowsHitTesting(false)
    }
}
