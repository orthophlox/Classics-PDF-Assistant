import Foundation

/// One row in the watched-folder activity log (Settings UI) — app-local
/// state, not part of the wire protocol. Mirrors the outcome of a single
/// `batch` command run against one auto-discovered file.
struct WatchedFolderActivityItem: Identifiable {
    let id: UUID
    let fileName: String
    let date: Date
    var status: Status

    enum Status {
        case processing
        case done(meanConfidence: Double?)
        case failed(String)
    }
}
