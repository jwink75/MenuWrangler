//
//  MenuBarLayoutSettingsPane.swift
//  Ice
//

import SwiftUI

struct MenuBarLayoutSettingsPane: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var folderManager = LayoutFolderManager.shared
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

        HStack {
            Text("Add new folders by dragging items to the \"New Folder\" section below.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: {
                folderManager.addFolder(named: "Folder \(folderManager.folders.count)", iconName: "folder")
            }) {
                Label("New Folder", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
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
    private var layoutBars: some View {
        VStack(spacing: 25) {
            // Visible section
            sectionBar(for: .visible)
            
            // Folder sections
            ForEach(Array(folderManager.folders.enumerated()), id: \.element.id) { index, folder in
                FolderLayoutBar(folder: folder, isFirstFolder: index == 0)
            }
            .onDelete(perform: deleteFolders)
            
            // Hidden section (if more than one folder, Hidden is just the first one)
            // Always show after folders
            sectionBar(for: .alwaysHidden)
        }
    }

    private func deleteFolders(at offsets: IndexSet) {
        // Delete in reverse order to maintain correct indices
        for index in offsets.sorted(by: >) {
            folderManager.deleteFolder(at: index)
        }
    }

    @ViewBuilder
    private func sectionBar(for name: MenuBarSection.Name) -> some View {
        if let section = appState.menuBarManager.section(withName: name) {
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
            Text("\(name.displayString) Section (not found)")
                .font(.system(size: 14))
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var cannotArrange: some View {
        Text("MenuWrangler cannot arrange menu bar items in automatically hidden menu bars")
            .font(.title3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
