import SwiftUI

struct ProcessingProgressView: View {
    let title: String
    let detail: String?
    /// nil renders an indeterminate spinner; 0...1 renders a determinate bar.
    let progress: Double?

    var body: some View {
        VStack(spacing: 12) {
            if let progress {
                ProgressView(value: progress)
                    .frame(width: 240)
            } else {
                ProgressView()
            }
            Text(title)
                .font(.headline)
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
