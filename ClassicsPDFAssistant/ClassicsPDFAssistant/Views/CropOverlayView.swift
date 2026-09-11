import SwiftUI

/// Page preview with a draggable/resizable crop rectangle overlaid on top.
/// The rectangle is stored (via `cropBox`) in image-pixel space, matching
/// the backend's coordinate convention; this view only handles the
/// image-space <-> view-space conversion for hit testing and drawing.
struct CropOverlayView: View {
    let page: PageAnalysis
    @Binding var cropBox: BoundingBox

    @State private var imageFrame: CGRect = .zero
    @State private var dragStart: BoundingBox?

    private let handleSize: CGFloat = 10

    var body: some View {
        ZStack(alignment: .topLeading) {
            PagePreviewView(
                imagePath: page.previewImage,
                imagePixelSize: CGSize(width: page.imageWidth, height: page.imageHeight)
            ) { frame in
                imageFrame = frame
            }

            if imageFrame != .zero {
                let rect = viewRect(for: cropBox, in: imageFrame)
                Rectangle()
                    .stroke(Color.accentColor, lineWidth: 2)
                    .background(Color.accentColor.opacity(0.08))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .gesture(moveGesture(in: imageFrame))

                ForEach(HandlePosition.allCases, id: \.self) { handle in
                    handleView(handle, rect: rect, in: imageFrame)
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Button("Reset to Detected") {
                cropBox = page.detectedCropBox
            }
            .padding(8)
        }
    }

    // MARK: - Coordinate conversion

    private func viewRect(for box: BoundingBox, in frame: CGRect) -> CGRect {
        let scaleX = frame.width / CGFloat(max(page.imageWidth, 1))
        let scaleY = frame.height / CGFloat(max(page.imageHeight, 1))
        return CGRect(
            x: frame.minX + CGFloat(box.x) * scaleX,
            y: frame.minY + CGFloat(box.y) * scaleY,
            width: CGFloat(box.width) * scaleX,
            height: CGFloat(box.height) * scaleY
        )
    }

    private func imageBox(for rect: CGRect, in frame: CGRect) -> BoundingBox {
        let scaleX = CGFloat(page.imageWidth) / max(frame.width, 1)
        let scaleY = CGFloat(page.imageHeight) / max(frame.height, 1)
        let x = (rect.minX - frame.minX) * scaleX
        let y = (rect.minY - frame.minY) * scaleY
        let width = rect.width * scaleX
        let height = rect.height * scaleY
        return BoundingBox(
            x: Int(x.rounded()).clamped(to: 0...page.imageWidth),
            y: Int(y.rounded()).clamped(to: 0...page.imageHeight),
            width: Int(width.rounded()).clamped(to: 0...page.imageWidth),
            height: Int(height.rounded()).clamped(to: 0...page.imageHeight)
        )
    }

    // MARK: - Gestures

    private func moveGesture(in frame: CGRect) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if dragStart == nil { dragStart = cropBox }
                guard let start = dragStart else { return }
                let scaleX = CGFloat(page.imageWidth) / max(frame.width, 1)
                let scaleY = CGFloat(page.imageHeight) / max(frame.height, 1)
                let dx = Int((value.translation.width * scaleX).rounded())
                let dy = Int((value.translation.height * scaleY).rounded())
                cropBox = BoundingBox(
                    x: (start.x + dx).clamped(to: 0...(page.imageWidth - start.width)),
                    y: (start.y + dy).clamped(to: 0...(page.imageHeight - start.height)),
                    width: start.width,
                    height: start.height
                )
            }
            .onEnded { _ in dragStart = nil }
    }

    private enum HandlePosition: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    @ViewBuilder
    private func handleView(_ handle: HandlePosition, rect: CGRect, in frame: CGRect) -> some View {
        let point = anchor(handle, of: rect)
        Circle()
            .fill(Color.accentColor)
            .frame(width: handleSize, height: handleSize)
            .position(point)
            .gesture(resizeGesture(handle, in: frame))
    }

    private func anchor(_ handle: HandlePosition, of rect: CGRect) -> CGPoint {
        switch handle {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    private func resizeGesture(_ handle: HandlePosition, in frame: CGRect) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if dragStart == nil { dragStart = cropBox }
                guard let start = dragStart else { return }
                let scaleX = CGFloat(page.imageWidth) / max(frame.width, 1)
                let scaleY = CGFloat(page.imageHeight) / max(frame.height, 1)
                let dx = Int((value.translation.width * scaleX).rounded())
                let dy = Int((value.translation.height * scaleY).rounded())

                var x = start.x, y = start.y, width = start.width, height = start.height
                switch handle {
                case .topLeft:
                    x = start.x + dx; y = start.y + dy
                    width = start.width - dx; height = start.height - dy
                case .topRight:
                    y = start.y + dy
                    width = start.width + dx; height = start.height - dy
                case .bottomLeft:
                    x = start.x + dx
                    width = start.width - dx; height = start.height + dy
                case .bottomRight:
                    width = start.width + dx; height = start.height + dy
                }
                let minSize = 20
                cropBox = BoundingBox(
                    x: x.clamped(to: 0...page.imageWidth),
                    y: y.clamped(to: 0...page.imageHeight),
                    width: max(minSize, width).clamped(to: minSize...page.imageWidth),
                    height: max(minSize, height).clamped(to: minSize...page.imageHeight)
                )
            }
            .onEnded { _ in dragStart = nil }
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
