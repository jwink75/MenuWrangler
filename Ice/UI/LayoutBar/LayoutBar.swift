//
//  LayoutBar.swift
//  Ice
//

import SwiftUI

struct LayoutBar: View {
    private struct Representable: NSViewRepresentable {
        let appState: AppState
        let section: MenuBarSection
        let spacing: CGFloat

        func makeNSView(context: Context) -> LayoutBarScrollView {
            LayoutBarScrollView(appState: appState, section: section, spacing: spacing)
        }

        func updateNSView(_ nsView: LayoutBarScrollView, context: Context) {
            nsView.spacing = spacing
            let items = appState.itemManager.itemCache.managedItems(for: section.name)
            Logger.layoutBar.debug("updateNSView: \(items.count) items for section \(self.section.name.displayString)")
            nsView.setArrangedViews(items: items)
        }
    }

    @EnvironmentObject var appState: AppState
    @EnvironmentObject var imageCache: MenuBarItemImageCache
    @State private var cacheUpdateID = UUID()

    let section: MenuBarSection
    let spacing: CGFloat

    private var menuBarManager: MenuBarManager {
        appState.menuBarManager
    }

    private var backgroundShape: some InsettableShape {
        RoundedRectangle(cornerRadius: 9, style: .circular)
    }

    init(section: MenuBarSection, spacing: CGFloat = 0) {
        self.section = section
        self.spacing = spacing
    }

    var body: some View {
        conditionalBody
            .id(cacheUpdateID)
            .frame(height: 50)
            .frame(maxWidth: .infinity)
            .layoutBarStyle(appState: appState, averageColorInfo: menuBarManager.averageColorInfo)
            .clipShape(backgroundShape)
            .overlay {
                backgroundShape
                    .stroke(.quaternary)
            }
            .onReceive(appState.itemManager.$itemCache) { _ in
                cacheUpdateID = UUID()
            }
    }

    @ViewBuilder
    private var conditionalBody: some View {
        Representable(appState: appState, section: section, spacing: spacing)
    }
}
