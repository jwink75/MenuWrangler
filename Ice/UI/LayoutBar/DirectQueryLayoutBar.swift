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

    private let minimumRefreshInterval: TimeInterval = 0.5

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(spacing: 8) {
                if items.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No items")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                }
                ForEach(items) { item in
                    LayoutItemView(item: item, onReorder: { draggedID, targetItem in
                        reorderItem(draggedID: draggedID, targetItem: targetItem)
                    })
                    .opacity(draggedItem?.id == item.id ? 0.5 : 1.0)
                    .onDrag {
                        self.draggedItem = item
                        return NSItemProvider(object: String(item.windowID) as NSString)
                    }
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let hiddenSection = appState.menuBarManager.section(withName: .hidden), hiddenSection.isHidden {
                    hiddenSection.show()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        _ = WindowQuery.getMenuBarWindows()
                        hiddenSection.hide()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            refreshItems()
                        }
                    }
                } else {
                    refreshItems()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshItems()
        }
        .onDrop(of: [.text], isTargeted: nil) { providers in
            handleDrop(providers: providers)
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
        items = filterWindowsForSection(allWindows)
        isRefreshing = false
    }

    private func filterWindowsForSection(_ windows: [LayoutItemInfo]) -> [LayoutItemInfo] {
        let sortedWindows = windows.sorted { $0.frame.origin.x < $1.frame.origin.x }

        let delimiter = sortedWindows.first { $0.isDelimiter }
        let delimiterX = delimiter?.frame.origin.x ?? ((NSScreen.main?.frame.width ?? 1200) * 0.75)

        let result: [LayoutItemInfo]
        switch section.name {
        case .visible:
            result = sortedWindows.filter { window in
                window.frame.origin.x >= delimiterX && !window.isDelimiter
            }
        case .hidden:
            result = sortedWindows.filter { window in
                window.frame.origin.x < delimiterX && !window.isDelimiter
            }
        case .alwaysHidden:
            result = []
        }

        // Debug info
        UserDefaults.standard.set(delimiterX, forKey: "LayoutBar_delimiterX_\(section.name.displayString)")
        UserDefaults.standard.set(result.count, forKey: "LayoutBar_resultCount_\(section.name.displayString)")
        UserDefaults.standard.set(result.map { "\($0.ownerName):\($0.frame.origin.x):\($0.title)" }.joined(separator: "|"), forKey: "LayoutBar_resultItems_\(section.name.displayString)")

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
        guard let item = MenuBarItem(windowID: windowID) else {
            draggedItem = nil
            return
        }

        guard let hiddenSection = appState.menuBarManager.section(withName: .hidden),
              let hiddenWinID = hiddenSection.controlItem.windowID,
              let hiddenControlItem = MenuBarItem(windowID: hiddenWinID) else {
            draggedItem = nil
            return
        }

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
                }

                await MainActor.run {
                    self.draggedItem = nil
                    WindowQuery.clearIconCache()
                    self.refreshItems()
                }
            } catch {
                print("[DirectQueryLayoutBar] Failed to move item: \(error)")
                await MainActor.run {
                    self.draggedItem = nil
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

        Task {
            do {
                if let draggedFrame = Bridging.getWindowFrame(for: draggedID),
                   draggedFrame.origin.x < targetItem.frame.origin.x {
                    try await appState.itemManager.move(item: draggedMenuBarItem, to: .rightOfItem(targetMenuBarItem))
                } else {
                    try await appState.itemManager.move(item: draggedMenuBarItem, to: .leftOfItem(targetMenuBarItem))
                }

                await MainActor.run {
                    self.draggedItem = nil
                    WindowQuery.clearIconCache()
                    self.refreshItems()
                }
            } catch {
                print("[DirectQueryLayoutBar] Failed to reorder item: \(error)")
                await MainActor.run {
                    self.draggedItem = nil
                    self.refreshItems()
                }
            }
        }
    }
}
