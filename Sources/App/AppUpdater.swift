import Combine
import Foundation
import Sparkle
import SwiftUI

@MainActor
final class AppUpdater: ObservableObject {
    @Published private(set) var canCheckForUpdates = false

    private let updaterController: SPUStandardUpdaterController?
    private var canCheckCancellable: AnyCancellable?
    private var lastCheckDateCancellable: AnyCancellable?
    private var updaterPreferencesCancellable: AnyCancellable?

    /// Sparkle feed + signing are configured; updater is live.
    var isSparkleConfigured: Bool {
        updaterController != nil
    }

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

        lastCheckDateCancellable = controller.updater.publisher(for: \.lastUpdateCheckDate)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }

        let checksPub = controller.updater.publisher(for: \.automaticallyChecksForUpdates)
        let downloadsPub = controller.updater.publisher(for: \.automaticallyDownloadsUpdates)
        updaterPreferencesCancellable = checksPub.merge(with: downloadsPub)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
    }

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }

    var lastUpdateCheckDate: Date? {
        updaterController?.updater.lastUpdateCheckDate
    }

    /// Mirrors Sparkle’s scheduled update checks (`SPUUpdater.automaticallyChecksForUpdates`).
    var automaticallyChecksForUpdates: Bool {
        updaterController?.updater.automaticallyChecksForUpdates ?? false
    }

    var automaticallyChecksForUpdatesBinding: Binding<Bool> {
        Binding(
            get: { [weak self] in self?.automaticallyChecksForUpdates ?? false },
            set: { [weak self] newValue in
                guard let updater = self?.updaterController?.updater else { return }
                updater.automaticallyChecksForUpdates = newValue
                if !newValue {
                    // Background downloads only apply when scheduled checks are on.
                    updater.automaticallyDownloadsUpdates = false
                }
                self?.objectWillChange.send()
            }
        )
    }

    var automaticallyDownloadsUpdatesBinding: Binding<Bool> {
        Binding(
            get: { [weak self] in self?.updaterController?.updater.automaticallyDownloadsUpdates ?? false },
            set: { [weak self] newValue in
                guard let updater = self?.updaterController?.updater else { return }
                updater.automaticallyDownloadsUpdates = newValue
                self?.objectWillChange.send()
            }
        )
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
