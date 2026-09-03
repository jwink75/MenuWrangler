//
//  FolderLayoutBar.swift
//  Ice
//

import SwiftUI

struct FolderLayoutBar: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var folderManager = LayoutFolderManager.shared
    let folder: FolderInfo
    @State private var isEditingName = false
    @State private var editedName = ""
    @State private var showIconPicker = false
    @FocusState private var isNameFieldFocused: Bool

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
                    }
                }

                Spacer()

                Button(action: {
                    showIconPicker = true
                }) {
                    Image(systemName: "paintbrush")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Change Icon")

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
                .help("Delete Folder")
            }

            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 8) {
                    if folder.items.isEmpty {
                        Text("No items")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                    }
                    ForEach(folder.items) { item in
                        FolderItemView(item: item)
                        .onDrag({
                            NSItemProvider(object: String(item.windowID) as NSString)
                        }, preview: {
                            if let image = item.image {
                                Image(nsImage: image)
                                    .resizable()
                                    .frame(width: 20, height: 20)
                            } else {
                                Image(systemName: "circle")
                                    .frame(width: 20, height: 20)
                            }
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

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadObject(ofClass: NSString.self) { (object, error) in
            guard let windowIDString = object as? String,
                  let windowID = UInt32(windowIDString) else {
                return
            }

            DispatchQueue.main.async {
                guard let folderIndex = self.folderManager.folders.firstIndex(where: { $0.id == self.folder.id }) else {
                    return
                }
                
                // Try to find the item in menu bar (for live items)
                if let layoutItem = WindowQuery.getMenuBarWindows().first(where: { $0.windowID == windowID }) {
                    self.folderManager.addItemToFolderByWindowID(
                        windowID,
                        folderIndex: folderIndex,
                        resolvedTitle: layoutItem.resolvedTitle,
                        ownerName: layoutItem.ownerName,
                        bundleIdentifier: layoutItem.bundleIdentifier,
                        image: layoutItem.image
                    )
                } else {
                    // Item may be from another folder - find it
                    for sourceFolder in self.folderManager.folders {
                        if let item = sourceFolder.items.first(where: { $0.windowID == windowID }) {
                            self.folderManager.addItemToFolder(item: item, folderIndex: folderIndex)
                            return
                        }
                    }
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

struct FolderItemView: View {
    let item: FolderItemInfo
    
    var body: some View {
        HStack(spacing: 2) {
            if let image = item.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "circle")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .foregroundStyle(.secondary)
            }
            
            @AppStorage("MenuBarLayout_showItemLabels") var showLabels: Bool = true
            if showLabels {
                Text(item.resolvedTitle)
                    .font(.system(size: 8, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 54)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
        .help(item.resolvedTitle)
    }
}
