//
//  LayoutFolderManager.swift
//  Ice
//

import Foundation
import Cocoa
import Combine

final class LayoutFolderManager: ObservableObject {
    static let shared = LayoutFolderManager()

    @Published var folderAssignments: [CGWindowID: String] = [:]
    @Published var folderNames: Set<String> = []

    private let userDefaultsKey = "MenuBarLayout_folderAssignments"
    private let folderNamesKey = "MenuBarLayout_folderNames"

    private var cancellables = Set<AnyCancellable>()

    init() {
        loadFromUserDefaults()

        $folderNames
            .sink { [weak self] names in
                self?.saveFolderNames()
            }
            .store(in: &cancellables)
    }

    func items(in folder: String, from allItems: [LayoutItemInfo]) -> [LayoutItemInfo] {
        allItems.filter { folderAssignments[$0.windowID] == folder }
    }

    func assign(_ item: LayoutItemInfo, to folder: String?) {
        if let folder = folder {
            folderAssignments[item.windowID] = folder
            folderNames.insert(folder)
        } else {
            folderAssignments.removeValue(forKey: item.windowID)
        }
        saveToUserDefaults()
    }

    func createFolder(named name: String) {
        folderNames.insert(name)
    }

    func deleteFolder(named name: String) {
        folderNames.remove(name)
        folderAssignments = folderAssignments.filter { $0.value != name }
        saveToUserDefaults()
    }

    private func loadFromUserDefaults() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            var result: [CGWindowID: String] = [:]
            for (key, value) in decoded {
                if let windowID = CGWindowID(key) {
                    result[windowID] = value
                }
            }
            folderAssignments = result
        }
        if let names = UserDefaults.standard.stringArray(forKey: folderNamesKey) {
            folderNames = Set(names)
        }
    }

    private func saveToUserDefaults() {
        var stringDict: [String: String] = [:]
        for (windowID, folder) in folderAssignments {
            stringDict[String(windowID)] = folder
        }
        if let data = try? JSONEncoder().encode(stringDict) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    private func saveFolderNames() {
        UserDefaults.standard.set(Array(folderNames), forKey: folderNamesKey)
    }
}
