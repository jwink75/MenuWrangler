//
//  MenuBarLayoutSettingsPane.swift
//  Ice
//

import SwiftUI

struct MenuBarLayoutSettingsPane: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var folderManager = LayoutFolderManager.shared
    @State private var showNewFolderDialog = false
    @State private var newFolderName = ""

    var body: some View {
        if appState.menuBarManager.isMenuBarHiddenBySystemUserDefaults {
            cannotArrange
        } else {
            IceForm(alignment: .leading, spacing: 20) {
                header
                if !ScreenCapture.cachedCheckPermissions() {
                    permissionWarning
                }
                folderManagement
                layoutBars
            }
            .sheet(isPresented: $showNewFolderDialog) {
                VStack(spacing: 16) {
                    Text("New Folder")
                        .font(.headline)
                    TextField("Folder name", text: $newFolderName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 250)
                    HStack {
                        Button("Cancel") {
                            showNewFolderDialog = false
                            newFolderName = ""
                        }
                        Button("Create") {
                            folderManager.createFolder(named: newFolderName)
                            showNewFolderDialog = false
                            newFolderName = ""
                        }
                        .disabled(newFolderName.isEmpty)
                    }
                }
                .padding()
                .frame(minWidth: 300, minHeight: 150)
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack {
            Text("Drag to arrange your menu bar items")
                .font(.title2)

            Spacer()

            Button(action: {
                WindowQuery.clearIconCache()
                NotificationCenter.default.post(name: NSNotification.Name("MenuBarsNeedRefresh"), object: nil)
            }) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }

        IceGroupBox {
            AnnotationView(
                alignment: .center,
                font: .callout.bold()
            ) {
                Label {
                    Text("Tip: you can also arrange menu bar items by Command + dragging them in the menu bar")
                } icon: {
                    Image(systemName: "lightbulb")
                }
            }
        }

        HStack {
            Toggle("Show item labels", isOn: Binding(
                get: { UserDefaults.standard.bool(forKey: "MenuBarLayout_showItemLabels") },
                set: { newValue in
                    UserDefaults.standard.set(newValue, forKey: "MenuBarLayout_showItemLabels")
                }
            ))
        }
        .toggleStyle(.switch)
        .font(.caption)
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private var permissionWarning: some View {
        IceGroupBox {
            AnnotationView(
                alignment: .center,
                font: .callout.bold()
            ) {
                Label {
                    Text("Screen recording permission is required to capture menu bar item icons. Items will display with fallback icons until granted.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
            }
        }
        .onTapGesture {
            appState.navigationState.settingsNavigationIdentifier = .advanced
        }
    }

    @ViewBuilder
    private var folderManagement: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Folders")
                    .font(.system(size: 14))
                    .padding(.leading, 2)

                Spacer()

                Button(action: {
                    showNewFolderDialog = true
                }) {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(folderManager.folderNames.isEmpty)
            }

            if folderManager.folderNames.isEmpty {
                Text("Create folders to group related items together.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)
            } else {
                ForEach(Array(folderManager.folderNames.sorted()), id: \.self) { name in
                    FolderLayoutBar(folderName: name)
                }
                .onDelete(perform: deleteFolders)
            }
        }
    }

    private func deleteFolders(at offsets: IndexSet) {
        let sortedNames = Array(folderManager.folderNames.sorted())
        for index in offsets {
            folderManager.deleteFolder(named: sortedNames[index])
        }
    }

    @ViewBuilder
    private var layoutBars: some View {
        VStack(spacing: 25) {
            ForEach(MenuBarSection.Name.allCases, id: \.self) { section in
                layoutBar(for: section)
            }
        }
    }

    @ViewBuilder
    private var cannotArrange: some View {
        Text("MenuWrangler cannot arrange menu bar items in automatically hidden menu bars")
            .font(.title3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func layoutBar(for section: MenuBarSection.Name) -> some View {
        if let section = appState.menuBarManager.section(withName: section) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(section.name.displayString) Section (enabled=\(section.isEnabled))")
                    .font(.system(size: 14))
                    .padding(.leading, 2)

                if section.isEnabled {
                    DirectQueryLayoutBar(section: section)
                } else {
                    Text("Section not enabled")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                }
            }
        } else {
            Text("\(section.displayString) Section (not found)")
                .font(.system(size: 14))
                .foregroundStyle(.red)
        }
    }
}
