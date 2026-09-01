//
//  LayoutFolderManager.swift
//  Ice
//

import Foundation
import Cocoa
import Combine

struct FolderInfo: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var iconName: String
    var itemWindowIDs: Set<CGWindowID>
    
    init(name: String = "", iconName: String = "folder", itemWindowIDs: Set<CGWindowID> = []) {
        self.name = name
        self.iconName = iconName
        self.itemWindowIDs = itemWindowIDs
    }
}

final class LayoutFolderManager: ObservableObject {
    static let shared = LayoutFolderManager()
    
    @Published var folders: [FolderInfo] = []
    
    private let userDefaultsKey = "MenuBarLayout_folders_v2"

    init() {
        loadFromUserDefaults()
        
        // Default: just the hidden folder
        let hiddenSection = UserDefaults.standard.dictionary(forKey: "MenuBarLayout_hiddenSection") as? [String: Any]
        
        if folders.isEmpty {
            // Create default folders if none exist
            folders = [
                FolderInfo(name: "Hidden", iconName: "chevron.left.2", itemWindowIDs: [])
            ]
            saveToUserDefaults()
        }
    }
    
    func addFolder(named name: String = "Folder", iconName: String = "folder") {
        objectWillChange.send()
        folders.append(FolderInfo(name: name, iconName: iconName, itemWindowIDs: []))
        saveToUserDefaults()
    }
    
    func deleteFolder(at index: Int) {
        guard index < folders.count else { return }
        objectWillChange.send()
        if index == 0 {
            let deletedFolder = folders.remove(at: 0)
            if folders.indices.contains(0) {
                folders[0].itemWindowIDs.formUnion(deletedFolder.itemWindowIDs)
            }
        } else {
            let deletedFolder = folders.remove(at: index)
            // Items in deleted folder - redistribute to previous folder
            let prevIndex = index - 1
            if folders.indices.contains(prevIndex) {
                folders[prevIndex].itemWindowIDs.formUnion(deletedFolder.itemWindowIDs)
            }
        }
        saveToUserDefaults()
    }
    
    func renameFolder(at index: Int, to newName: String) {
        guard index < folders.count, !newName.isEmpty else { return }
        objectWillChange.send()
        folders[index].name = newName
        saveToUserDefaults()
    }
    
    func setIcon(forFolderAt index: Int, iconName: String) {
        guard index < folders.count else { return }
        objectWillChange.send()
        folders[index].iconName = iconName
        saveToUserDefaults()
    }
    
    func updateFolder(at index: Int, name: String, iconName: String) {
        guard index < folders.count else { return }
        objectWillChange.send()
        folders[index].name = name
        folders[index].iconName = iconName
        saveToUserDefaults()
    }
    
    func assignItem(windowID: CGWindowID, toFolderAt index: Int?) {
        objectWillChange.send()
        // Remove from all folders
        for i in folders.indices {
            folders[i].itemWindowIDs.remove(windowID)
        }
        // Add to target folder
        if let index, index < folders.count {
            folders[index].itemWindowIDs.insert(windowID)
        }
        saveToUserDefaults()
    }
    
    func folderIndex(for windowID: CGWindowID) -> Int? {
        folders.firstIndex { $0.itemWindowIDs.contains(windowID) }
    }
    
    func items(for windowID: CGWindowID) -> Set<CGWindowID> {
        folders.first { $0.itemWindowIDs.contains(windowID) }?.itemWindowIDs ?? []
    }
    
    private func saveToUserDefaults() {
        let dictArray = folders.map { folder -> [String: Any] in
            [
                "name": folder.name,
                "iconName": folder.iconName,
                "itemWindowIDs": Array(folder.itemWindowIDs).map { String($0) }
            ]
        }
        UserDefaults.standard.set(dictArray, forKey: userDefaultsKey)
    }
    
    private func loadFromUserDefaults() {
        guard let dictArray = UserDefaults.standard.array(forKey: userDefaultsKey) as? [[String: Any]] else {
            return
        }
        folders = dictArray.compactMap { dict in
            guard let name = dict["name"] as? String,
                  let iconName = dict["iconName"] as? String,
                  let idStrings = dict["itemWindowIDs"] as? [String] else {
                return nil
            }
            let windowIDs = Set(idStrings.compactMap { CGWindowID($0) })
            return FolderInfo(name: name, iconName: iconName, itemWindowIDs: windowIDs)
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
