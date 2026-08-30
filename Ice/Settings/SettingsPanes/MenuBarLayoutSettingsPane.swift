//
//  MenuBarLayoutSettingsPane.swift
//  Ice
//

import SwiftUI

struct MenuBarLayoutSettingsPane: View {
    @EnvironmentObject var appState: AppState

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
            Button("Refresh") {
                WindowQuery.clearIconCache()
                NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
            }
            .buttonStyle(.borderless)
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
