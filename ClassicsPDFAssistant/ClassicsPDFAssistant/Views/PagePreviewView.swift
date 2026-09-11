import AppKit
import SwiftUI

/// Displays a page preview image (written by the backend's `analyze` step)
/// at a fixed aspect ratio, reporting the on-screen frame it ends up laid
/// out in so overlays (CropOverlayView's crop rectangle) can convert
/// between view space and image-pixel space.
struct PagePreviewView: View {
    let imagePath: String
    let imagePixelSize: CGSize
    var onLayout: ((CGRect) -> Void)? = nil

    var body: some View {
        GeometryReader { geometry in
            let fittedSize = Self.aspectFit(imagePixelSize, in: geometry.size)
            let origin = CGPoint(
                x: (geometry.size.width - fittedSize.width) / 2,
                y: (geometry.size.height - fittedSize.height) / 2
            )
            let frame = CGRect(origin: origin, size: fittedSize)

            ZStack {
                Color(nsColor: .textBackgroundColor)
                if let nsImage = NSImage(contentsOfFile: imagePath) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: fittedSize.width, height: fittedSize.height)
                        .position(x: frame.midX, y: frame.midY)
                } else {
                    Text("Preview unavailable")
                        .foregroundStyle(.secondary)
                }
            }
            .onAppear { onLayout?(frame) }
            .onChange(of: geometry.size) { _, _ in onLayout?(frame) }
        }
    }

    static func aspectFit(_ size: CGSize, in bounds: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return bounds }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}
