import Combine
import Foundation
import Sparkle

@MainActor
final class AppUpdater: ObservableObject {
    @Published private(set) var canCheckForUpdates = false

    private let updaterController: SPUStandardUpdaterController?
    private var canCheckCancellable: AnyCancellable?

    init(bundle: Bundle = .main) {
        guard Self.hasSparkleConfiguration(bundle: bundle) else {
            updaterController = nil
            return
        }

        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        updaterController = controller

        canCheckCancellable = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] canCheck in
                self?.canCheckForUpdates = canCheck
            }
    }

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }

    private static func hasSparkleConfiguration(bundle: Bundle) -> Bool {
        guard
            let feedURL = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            let publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        else {
            return false
        }

        let normalizedFeedURL = feedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPublicKey = publicKey.trimmingCharacters(in: .whitespacesAndNewlines)

        return !normalizedFeedURL.isEmpty &&
            !normalizedPublicKey.isEmpty &&
            !normalizedPublicKey.contains("CHANGE_ME")
    }
}
