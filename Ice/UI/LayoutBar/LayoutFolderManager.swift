//
//  LayoutFolderManager.swift
//  Ice
//

import Foundation
import Cocoa
import Combine

struct FolderItemInfo: Identifiable, Hashable {
    let id = UUID()
    var windowID: CGWindowID
    var resolvedTitle: String
    var ownerName: String
    var bundleIdentifier: String?
    var image: NSImage?
}

struct FolderInfo: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var iconName: String
    var items: [FolderItemInfo]
    
    init(name: String = "", iconName: String = "folder", items: [FolderItemInfo] = []) {
        self.name = name
        self.iconName = iconName
        self.items = items
    }
    
    var itemWindowIDs: Set<CGWindowID> {
        Set(items.map { $0.windowID })
    }
}

final class LayoutFolderManager: ObservableObject {
    static let shared = LayoutFolderManager()
    
    @Published var folders: [FolderInfo] = []
    
    private let userDefaultsKey = "MenuBarLayout_folders_v3"

    init() {
        loadFromUserDefaults()
        
        if folders.isEmpty {
            // Create default folders if none exist
            folders = [
                FolderInfo(name: "Hidden", iconName: "chevron.left.2", items: [])
            ]
            saveToUserDefaults()
        }
    }
    
    func addFolder(named name: String = "Folder", iconName: String = "folder") {
        objectWillChange.send()
        folders.append(FolderInfo(name: name, iconName: iconName, items: []))
        saveToUserDefaults()
    }
    
    func deleteFolder(at index: Int) {
        guard index < folders.count else { return }
        objectWillChange.send()
        if index == 0 {
            let deletedFolder = folders.remove(at: 0)
            if folders.indices.contains(0) {
                folders[0].items.append(contentsOf: deletedFolder.items)
            }
        } else {
            let deletedFolder = folders.remove(at: index)
            let prevIndex = index - 1
            if folders.indices.contains(prevIndex) {
                folders[prevIndex].items.append(contentsOf: deletedFolder.items)
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
    
    func addItemToFolder(item: FolderItemInfo, folderIndex: Int) {
        guard folderIndex < folders.count else { return }
        objectWillChange.send()
        // Remove from all folders
        for i in folders.indices {
            folders[i].items.removeAll { $0.windowID == item.windowID }
        }
        // Add to target folder
        folders[folderIndex].items.append(item)
        saveToUserDefaults()
    }
    
    func addItemToFolderByWindowID(_ windowID: CGWindowID, folderIndex: Int, resolvedTitle: String, ownerName: String, bundleIdentifier: String?, image: NSImage?) {
        let item = FolderItemInfo(
            windowID: windowID,
            resolvedTitle: resolvedTitle,
            ownerName: ownerName,
            bundleIdentifier: bundleIdentifier,
            image: image
        )
        addItemToFolder(item: item, folderIndex: folderIndex)
    }
    
    func removeItem(windowID: CGWindowID) {
        objectWillChange.send()
        for i in folders.indices {
            folders[i].items.removeAll { $0.windowID == windowID }
        }
        saveToUserDefaults()
    }
    
    func folderIndex(for windowID: CGWindowID) -> Int? {
        folders.firstIndex { $0.items.contains { $0.windowID == windowID } }
    }
    
    private func saveToUserDefaults() {
        let dictArray = folders.map { folder -> [String: Any] in
            let items = folder.items.map { item -> [String: Any] in
                var dict: [String: Any] = [
                    "windowID": String(item.windowID),
                    "resolvedTitle": item.resolvedTitle,
                    "ownerName": item.ownerName
                ]
                if let bundleID = item.bundleIdentifier {
                    dict["bundleIdentifier"] = bundleID
                }
                if let image = item.image,
                   let tiffData = image.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmap.representation(using: .png, properties: [:]) {
                    dict["imagePNG"] = pngData
                }
                return dict
            }
            return [
                "name": folder.name,
                "iconName": folder.iconName,
                "items": items
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
                  let itemsArray = dict["items"] as? [[String: Any]] else {
                return nil
            }
            let items: [FolderItemInfo] = itemsArray.compactMap { itemDict in
                guard let windowIDString = itemDict["windowID"] as? String,
                      let windowID = CGWindowID(windowIDString),
                      let resolvedTitle = itemDict["resolvedTitle"] as? String,
                      let ownerName = itemDict["ownerName"] as? String else {
                    return nil
                }
                let bundleIdentifier = itemDict["bundleIdentifier"] as? String
                var image: NSImage? = nil
                if let pngData = itemDict["imagePNG"] as? Data {
                    image = NSImage(data: pngData)
                }
                return FolderItemInfo(
                    windowID: windowID,
                    resolvedTitle: resolvedTitle,
                    ownerName: ownerName,
                    bundleIdentifier: bundleIdentifier,
                    image: image
                )
            }
            return FolderInfo(name: name, iconName: iconName, items: items)
        }
    }
}
