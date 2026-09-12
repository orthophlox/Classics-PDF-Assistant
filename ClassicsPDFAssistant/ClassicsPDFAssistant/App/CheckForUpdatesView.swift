import Combine
import Sparkle
import SwiftUI

/// The "Check for Updates…" menu item, following Sparkle's own documented
/// SwiftUI recipe: observe `canCheckForUpdates` via Combine so the item
/// disables itself while a check is already running, without needing any
/// AppKit-only SPUUpdater bindings. See README.md "자동 업데이트 설정하기"
/// for what has to be configured (signing keys, appcast hosting) before
/// this actually finds and installs updates rather than just failing
/// quietly against the placeholder feed URL in Info.plist.
final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false
    private var cancellable: AnyCancellable?

    init(updater: SPUUpdater) {
        cancellable = updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
    }
}

struct CheckForUpdatesView: View {
    private let updater: SPUUpdater
    @ObservedObject private var viewModel: CheckForUpdatesViewModel

    init(updater: SPUUpdater) {
        self.updater = updater
        viewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
        .disabled(!viewModel.canCheckForUpdates)
    }
}
