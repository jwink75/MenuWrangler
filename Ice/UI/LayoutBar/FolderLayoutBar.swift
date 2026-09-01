//
//  FolderLayoutBar.swift
//  Ice
//

import SwiftUI

struct FolderLayoutBar: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var folderManager = LayoutFolderManager.shared
    @Binding var folder: FolderInfo
    @State private var items: [LayoutItemInfo] = []
    @State private var isRefreshing = false
    @State private var lastRefreshTime: Date = .distantPast
    @State private var isEditingName = false
    @State private var editedName = ""
    @State private var showIconPicker = false
    @FocusState private var isNameFieldFocused: Bool

    private let minimumRefreshInterval: TimeInterval = 0.3

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
            refreshItems()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshItems()
        }
        .onChange(of: folder) { newValue in
            refreshItems()
            // Persist icon change
            let index = folderManager.folders.firstIndex(where: { $0.id == folder.id })
            if let index {
                folderManager.updateFolder(at: index, name: folder.name, iconName: folder.iconName)
            }
        }
        .onDrop(of: [.text], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
        .sheet(isPresented: $showIconPicker) {
            IconPickerView(selectedIcon: $folder.iconName)
        }
    }

    private func refreshItems() {
        let now = Date()
        guard !isRefreshing, now.timeIntervalSince(lastRefreshTime) >= minimumRefreshInterval else {
            return
        }
        isRefreshing = true
        lastRefreshTime = now

        let allWindows = WindowQuery.getMenuBarWindows()
        items = folderManager.items(in: folder)
        
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
                let index = folderManager.folders.firstIndex(where: { $0.id == self.folder.id })
                if let index {
                    folderManager.assignItem(windowID: windowID, toFolderAt: index)
                }
                NotificationCenter.default.post(name: NSNotification.Name("MenuBarsNeedRefresh"), object: nil)
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

extension LayoutFolderManager {
    func items(in folder: FolderInfo) -> [LayoutItemInfo] {
        let allWindows = WindowQuery.getMenuBarWindows()
        return allWindows.filter { folder.itemWindowIDs.contains($0.windowID) }
    }
}
