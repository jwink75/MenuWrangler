//
//  FolderLayoutBar.swift
//  Ice
//

import SwiftUI

struct FolderLayoutBar: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var folderManager = LayoutFolderManager.shared
    let folder: FolderInfo
    @State private var items: [LayoutItemInfo] = []
    @State private var isRefreshing = false
    @State private var lastRefreshTime: Date = .distantPast
    @State private var isEditingName = false
    @State private var editedName = ""
    @State private var showIconPicker = false
    @FocusState private var isNameFieldFocused: Bool

    private let minimumRefreshInterval: TimeInterval = 0.5

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if isEditingName {
                    TextField("Folder name", text: $editedName, onCommit: {
                        saveFolderName()
                    })
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
                    .focused($isNameFieldFocused)
                    .onAppear {
                        isNameFieldFocused = true
                    }
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: folder.iconName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text(folder.name)
                            .font(.system(size: 14, weight: .medium))
                            .onTapGesture(count: 2) {
                                startEditingName()
                            }
                            .contextMenu {
                                Button("Rename") {
                                    startEditingName()
                                }
                                Button("Change Icon…") {
                                    showIconPicker = true
                                }
                            }
                    }
                }

                Spacer()

                Button(action: {
                    let index = folderManager.folders.firstIndex(where: { $0.id == folder.id })
                    if let index {
                        folderManager.deleteFolder(at: index)
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }

            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 8) {
                    if items.isEmpty {
                        Text("No items")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                    }
                    ForEach(items) { item in
                        LayoutItemView(item: item)
                        .onDrag({
                            NSItemProvider(object: String(item.windowID) as NSString)
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
        }
        .onAppear {
            refreshItems()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MenuBarsNeedRefresh"))) { _ in
            // Debounce: only refresh if not already refreshing
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
        .sheet(isPresented: $showIconPicker) {
            IconPickerView(selectedIcon: Binding(
                get: { folder.iconName },
                set: { newIcon in
                    let index = folderManager.folders.firstIndex(where: { $0.id == folder.id })
                    if let index {
                        folderManager.setIcon(forFolderAt: index, iconName: newIcon)
                    }
                }
            ))
        }
    }

    private func refreshItems() {
        // Skip if we're currently refreshing
        guard !isRefreshing else { return }
        
        let now = Date()
        // Time-based debounce
        guard now.timeIntervalSince(lastRefreshTime) >= minimumRefreshInterval else {
            return
        }
        
        isRefreshing = true
        lastRefreshTime = now

        let allWindows = WindowQuery.getMenuBarWindows()
        
        let folderIndex = folderManager.folders.firstIndex(where: { $0.id == folder.id })
        
        if folderIndex == 0 {
            // First folder (Hidden): show items left of delimiter that aren't in other folders
            let sortedWindows = allWindows.sorted { $0.frame.origin.x < $1.frame.origin.x }
            let delimiter = sortedWindows.first { $0.isDelimiter }
            let delimiterX = delimiter?.frame.origin.x ?? ((NSScreen.main?.frame.width ?? 1200) * 0.75)
            
            // Get items in other folders (not this first one)
            let otherFolderItems = Set(folderManager.folders.dropFirst().flatMap { $0.itemWindowIDs })
            
            items = sortedWindows.filter { window in
                window.frame.origin.x < delimiterX && !window.isDelimiter && !otherFolderItems.contains(window.windowID)
            }
        } else if let folderIndex {
            items = allWindows.filter { folderManager.folders[folderIndex].itemWindowIDs.contains($0.windowID) }
        }
        
        isRefreshing = false
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadObject(ofClass: NSString.self) { (object, error) in
            guard let windowIDString = object as? String,
                  let windowID = UInt32(windowIDString) else {
                return
            }

            DispatchQueue.main.async {
                let folderIndex = self.folderManager.folders.firstIndex(where: { $0.id == self.folder.id })
                if let folderIndex {
                    self.folderManager.assignItem(windowID: windowID, toFolderAt: folderIndex)
                }
                // Use a delayed refresh to avoid re-entrancy
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    NotificationCenter.default.post(name: NSNotification.Name("MenuBarsNeedRefresh"), object: nil)
                }
            }
        }

        return true
    }
    
    private func startEditingName() {
        editedName = folder.name
        isEditingName = true
    }
    
    private func saveFolderName() {
        let trimmedName = editedName.trimmingCharacters(in: .whitespaces)
        if !trimmedName.isEmpty && trimmedName != folder.name {
            let index = folderManager.folders.firstIndex(where: { $0.id == folder.id })
            if let index {
                folderManager.renameFolder(at: index, to: trimmedName)
            }
        }
        isEditingName = false
        isNameFieldFocused = false
    }
}
