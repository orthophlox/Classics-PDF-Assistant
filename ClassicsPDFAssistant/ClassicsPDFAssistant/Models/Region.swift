import SwiftUI

/// A classified page region from the backend's multi-region crop detection
/// (critical editions: main text vs. apparatus vs. marginal line numbers).
/// Mirrors `Region` in `backend/pdf_backend/crop.py`.
enum RegionType: String, Codable {
    case mainText = "main_text"
    case apparatus
    case marginLeft = "margin_left"
    case marginRight = "margin_right"
    case other

    var displayName: String {
        switch self {
        case .mainText: return "Main Text"
        case .apparatus: return "Critical Apparatus"
        case .marginLeft: return "Margin (Left)"
        case .marginRight: return "Margin (Right)"
        case .other: return "Other"
        }
    }

    var color: Color {
        switch self {
        case .mainText: return .accentColor
        case .apparatus: return .orange
        case .marginLeft, .marginRight: return .purple
        case .other: return .gray
        }
    }
}

struct Region: Codable, Identifiable, Equatable {
    var id = UUID()
    var regionType: RegionType
    var bbox: BoundingBox

    private enum CodingKeys: String, CodingKey {
        case regionType, bbox
    }
}
