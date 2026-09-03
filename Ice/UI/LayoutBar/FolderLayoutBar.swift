//
//  FolderLayoutBar.swift
//  Ice
//

import SwiftUI

struct FolderLayoutBar: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var folderManager = LayoutFolderManager.shared
    let folder: FolderInfo
    let isFirstFolder: Bool
    @State private var liveItems: [LayoutItemInfo] = []
    @State private var isEditingName = false
    @State private var editedName = ""
    @State private var showIconPicker = false
    @State private var lastRefreshTime: Date = .distantPast
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

                if !isFirstFolder {
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
            }

            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 8) {
                    if displayedItems.isEmpty {
                        Text("No items")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                    }
                    ForEach(displayedItems, id: \.windowID) { item in
                        FolderItemView(item: item)
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
            refreshLiveItems()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MenuBarsNeedRefresh"))) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                refreshLiveItems()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshLiveItems()
        }
        .onDrop(of: [.text], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
        .sheet(isPresented: $showIconPicker) {
            IconPickerView { newIcon in
                let index = folderManager.folders.firstIndex(where: { $0.id == folder.id })
                if let index {
                    folderManager.setIcon(forFolderAt: index, iconName: newIcon)
                }
            }
        }
    }

    private var displayedItems: [LayoutItemInfo] {
        if isFirstFolder {
            return liveItems
        } else {
            return folder.items.map { folderItem in
                LayoutItemInfo(
                    windowID: folderItem.windowID,
                    image: folderItem.image ?? NSImage(),
                    ownerPID: 0,
                    ownerName: folderItem.ownerName,
                    bundleIdentifier: folderItem.bundleIdentifier,
                    frame: .zero,
                    title: folderItem.resolvedTitle,
                    isDelimiter: false
                )
            }
        }
    }

    private func refreshLiveItems() {
        let now = Date()
        guard now.timeIntervalSince(lastRefreshTime) >= minimumRefreshInterval else {
            return
        }
        lastRefreshTime = now

        guard isFirstFolder else { return }

        let allWindows = WindowQuery.getMenuBarWindows()
        let sortedWindows = allWindows.sorted { $0.frame.origin.x < $1.frame.origin.x }
        let delimiter = sortedWindows.first { $0.isDelimiter }
        let delimiterX = delimiter?.frame.origin.x ?? ((NSScreen.main?.frame.width ?? 1200) * 0.75)

        let folderManager = LayoutFolderManager.shared
        let otherFolderItems = Set(folderManager.folders.dropFirst().flatMap { $0.items.map { $0.windowID } })

        liveItems = sortedWindows.filter { window in
            window.frame.origin.x < delimiterX && !window.isDelimiter && !otherFolderItems.contains(window.windowID)
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
    let item: LayoutItemInfo

    var body: some View {
        FolderItemContent(item: item)
    }
}

private struct FolderItemContent: View {
    let item: LayoutItemInfo
    @AppStorage("MenuBarLayout_showItemLabels") private var showLabels: Bool = true

    var body: some View {
        HStack(spacing: 2) {
            Image(nsImage: item.image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)

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
