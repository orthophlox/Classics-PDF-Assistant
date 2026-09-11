import CoreGraphics
import Foundation

/// Pixel-space bounding box at whatever DPI a page was rasterized at.
/// Mirrors `BoundingBox` in `backend/pdf_backend/geometry.py`.
struct BoundingBox: Codable, Equatable, Hashable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int
}

extension BoundingBox {
    /// Image-pixel-space CGRect (origin top-left), for the crop overlay editor.
    var cgRect: CGRect {
        CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height))
    }

    init(cgRect: CGRect) {
        x = Int(cgRect.origin.x.rounded())
        y = Int(cgRect.origin.y.rounded())
        width = Int(cgRect.width.rounded())
        height = Int(cgRect.height.rounded())
    }
}
