//
//  DirectQueryLayoutBar.swift
//  Ice
//

import SwiftUI

struct DirectQueryLayoutBar: View {
    @EnvironmentObject var appState: AppState
    let section: MenuBarSection
    @State private var items: [LayoutItemInfo] = []
    @State private var draggedItem: LayoutItemInfo?
    @State private var isRefreshing = false
    @State private var lastRefreshTime: Date = .distantPast
    @State private var pendingMoves: Set<CGWindowID> = []

    private let minimumRefreshInterval: TimeInterval = 0.3

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(spacing: 8) {
                if items.isEmpty {
                    Text("No items")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                }
                ForEach(items) { item in
                    LayoutItemView(item: item, onReorder: { draggedID, targetItem in
                        reorderItem(draggedID: draggedID, targetItem: targetItem)
                    })
                    .opacity(draggedItem?.id == item.id ? 0.5 : 1.0)
                    .onDrag({
                        self.draggedItem = item
                        return NSItemProvider(object: String(item.windowID) as NSString)
                    }, preview: {
                        Image(nsImage: item.image)
                            .resizable()
                            .frame(width: 20, height: 20)
                    })
                }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 32, alignment: .leading)
        }
        .frame(height: 50)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(.quaternary.opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(.quaternary, lineWidth: 0.5)
        )
        .onAppear {
            // Delay to ensure windows are available for capture
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                refreshItems()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshItems()
        }
        .onDrop(of: [.text], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
    }

    private func refreshItems(skipOS: Bool = false) {
        let now = Date()
        guard !isRefreshing, now.timeIntervalSince(lastRefreshTime) >= minimumRefreshInterval else {
            return
        }
        isRefreshing = true
        lastRefreshTime = now

        let allWindows = WindowQuery.getMenuBarWindows()
        items = filterWindowsForSection(allWindows)
        isRefreshing = false
    }

    private func optimisticUpdate(from sourceSection: MenuBarSection.Name, itemID: CGWindowID, to targetSection: MenuBarSection.Name) {
        // Move item in the displayed UI without querying the OS
        // The actual OS move happens asynchronously
        refreshItems()
    }

    private func filterWindowsForSection(_ windows: [LayoutItemInfo]) -> [LayoutItemInfo] {
        let sortedWindows = windows.sorted { $0.frame.origin.x < $1.frame.origin.x }

        let delimiter = sortedWindows.first { $0.isDelimiter }
        let delimiterX = delimiter?.frame.origin.x ?? ((NSScreen.main?.frame.width ?? 1200) * 0.75)

        // Exclude items that are in folders (except the first folder which represents Hidden)
        let folderManager = LayoutFolderManager.shared
        let itemsInFolders = Set(folderManager.folders.dropFirst().flatMap { $0.itemWindowIDs })
        let nonFolderedWindows = sortedWindows.filter { !itemsInFolders.contains($0.windowID) }
        
        let result: [LayoutItemInfo]
        switch section.name {
        case .visible:
            result = nonFolderedWindows.filter { window in
                window.frame.origin.x >= delimiterX && !window.isDelimiter
            }
        case .hidden:
            result = nonFolderedWindows.filter { window in
                window.frame.origin.x < delimiterX && !window.isDelimiter
            }
        case .alwaysHidden:
            result = []
        case .folder:
            result = [] // Folders are handled by FolderLayoutBar
        }

        return result
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadObject(ofClass: NSString.self) { (object, error) in
            guard let windowIDString = object as? String,
                  let windowID = UInt32(windowIDString) else {
                return
            }

            DispatchQueue.main.async {
                self.moveItem(windowID: windowID, to: self.section)
            }
        }

        return true
    }

    private func moveItem(windowID: CGWindowID, to targetSection: MenuBarSection) {
        let folderManager = LayoutFolderManager.shared

        // Handle folder targets - update folder assignment
        if case .folder(let folderName) = targetSection.name {
            if let folderIndex = folderManager.folders.firstIndex(where: { $0.name == folderName }) {
                // Try to get item info from menu bar
                if let layoutItem = WindowQuery.getMenuBarWindows().first(where: { $0.windowID == windowID }) {
                    folderManager.addItemToFolderByWindowID(
                        windowID,
                        folderIndex: folderIndex,
                        resolvedTitle: layoutItem.resolvedTitle,
                        ownerName: layoutItem.ownerName,
                        bundleIdentifier: layoutItem.bundleIdentifier,
                        image: layoutItem.image
                    )
                } else {
                    // Item may be from another folder
                    folderManager.removeItem(windowID: windowID)
                }
            }
            draggedItem = nil
            return
        }

        guard let item = MenuBarItem(windowID: windowID) else {
            draggedItem = nil
            return
        }

        // Handle moving from a folder back to a regular section
        if folderManager.folders.contains(where: { $0.itemWindowIDs.contains(windowID) }) {
            folderManager.removeItem(windowID: windowID)
        }

        guard let hiddenSection = appState.menuBarManager.section(withName: .hidden),
              let hiddenWinID = hiddenSection.controlItem.windowID,
              let hiddenControlItem = MenuBarItem(windowID: hiddenWinID) else {
            draggedItem = nil
            return
        }

        pendingMoves.insert(windowID)

        Task {
            do {
                switch targetSection.name {
                case .visible:
                    try await appState.itemManager.move(item: item, to: .rightOfItem(hiddenControlItem))
                case .hidden:
                    try await appState.itemManager.move(item: item, to: .leftOfItem(hiddenControlItem))
                case .alwaysHidden:
                    if let alwaysHiddenSection = appState.menuBarManager.section(withName: .alwaysHidden),
                       let alwaysHiddenWinID = alwaysHiddenSection.controlItem.windowID,
                       let alwaysHiddenControlItem = MenuBarItem(windowID: alwaysHiddenWinID) {
                        try await appState.itemManager.move(item: item, to: .leftOfItem(alwaysHiddenControlItem))
                    }
                case .folder:
                    break
                }

                await MainActor.run {
                    pendingMoves.remove(windowID)
                    draggedItem = nil
                    WindowQuery.clearIconCache()
                    NotificationCenter.default.post(name: NSNotification.Name("MenuBarsNeedRefresh"), object: nil)
                    self.refreshItems()
                }
            } catch {
                print("[DirectQueryLayoutBar] Failed to move item: \(error)")
                await MainActor.run {
                    pendingMoves.remove(windowID)
                    draggedItem = nil
                    NotificationCenter.default.post(name: NSNotification.Name("MenuBarsNeedRefresh"), object: nil)
                    self.refreshItems()
                }
            }
        }
    }

    private func reorderItem(draggedID: CGWindowID, targetItem: LayoutItemInfo) {
        guard let draggedMenuBarItem = MenuBarItem(windowID: draggedID),
              let targetMenuBarItem = MenuBarItem(windowID: targetItem.windowID) else {
            return
        }

        pendingMoves.insert(draggedID)

        Task {
            do {
                if let draggedFrame = Bridging.getWindowFrame(for: draggedID),
                   draggedFrame.origin.x < targetItem.frame.origin.x {
                    try await appState.itemManager.move(item: draggedMenuBarItem, to: .rightOfItem(targetMenuBarItem))
                } else {
                    try await appState.itemManager.move(item: draggedMenuBarItem, to: .leftOfItem(targetMenuBarItem))
                }

                await MainActor.run {
                    pendingMoves.remove(draggedID)
                    draggedItem = nil
                    WindowQuery.clearIconCache()
                    NotificationCenter.default.post(name: NSNotification.Name("MenuBarsNeedRefresh"), object: nil)
                    self.refreshItems()
                }
            } catch {
                print("[DirectQueryLayoutBar] Failed to reorder item: \(error)")
                await MainActor.run {
                    pendingMoves.remove(draggedID)
                    draggedItem = nil
                    NotificationCenter.default.post(name: NSNotification.Name("MenuBarsNeedRefresh"), object: nil)
                    self.refreshItems()
                }
            }
        }
    }
}

