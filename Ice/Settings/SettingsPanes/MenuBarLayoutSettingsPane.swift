//
//  MenuBarLayoutSettingsPane.swift
//  Ice
//

import SwiftUI

struct MenuBarLayoutSettingsPane: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var folderManager = LayoutFolderManager.shared
    @State private var newFolderName = ""
    @AppStorage("MenuBarLayout_showItemLabels") private var showLabels: Bool = true

    init() {
        UserDefaults.standard.register(defaults: ["MenuBarLayout_showItemLabels": true])
    }

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

        Toggle("Show item labels", isOn: $showLabels)
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
                    folderManager.createFolder(named: "New Folder")
                }) {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }

            if folderManager.folderNames.isEmpty {
                Text("Create folders to group related items together. Drag items from Visible/Hidden sections into folders.")
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
            ForEach(MenuBarSection.Name.predefinedCases, id: \.self) { section in
                layoutBar(for: section)
            }
            
            // Folder sections
            ForEach(Array(folderManager.folderNames.sorted()), id: \.self) { folderName in
                folderLayoutBar(for: folderName)
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

    @ViewBuilder
    private func folderLayoutBar(for folderName: String) -> some View {
        FolderLayoutBar(folderName: folderName)
    }
}
