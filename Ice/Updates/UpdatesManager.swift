//
//  UpdatesManager.swift
//  Ice
//

import SwiftUI

/// Manager for app updates.
@MainActor
final class UpdatesManager: NSObject, ObservableObject {
    /// A Boolean value that indicates whether the user can check for updates.
    @Published var canCheckForUpdates = false

    /// The date of the last update check.
    @Published var lastUpdateCheckDate: Date?

    /// The shared app state.
    private(set) weak var appState: AppState?

    /// A Boolean value that indicates whether to automatically check for updates.
    var automaticallyChecksForUpdates: Bool = false

    /// A Boolean value that indicates whether to automatically download updates.
    var automaticallyDownloadsUpdates: Bool = false

    /// Creates an updates manager with the given app state.
    init(appState: AppState) {
        self.appState = appState
        super.init()
    }

    /// Sets up the manager.
    func performSetup() {
    }

    /// Checks for app updates.
    @objc func checkForUpdates() {
    }
}

// MARK: UpdatesManager: BindingExposable
extension UpdatesManager: BindingExposable { }

