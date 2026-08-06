import SwiftUI

struct HeatmapCanvas: View {
    let image: CGImage?

    var body: some View {
        Canvas { ctx, size in
            guard let img = image else { return }
            ctx.opacity = 0.6
            ctx.draw(Image(img, scale: 1, label: Text("")),
                     in: CGRect(origin: .zero, size: size))
        }
        .allowsHitTesting(false)
    }
}
