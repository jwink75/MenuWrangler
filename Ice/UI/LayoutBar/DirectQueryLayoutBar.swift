//
//  DirectQueryLayoutBar.swift
//  Ice
//

import SwiftUI

struct DirectQueryLayoutBar: View {
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
                        Text("delX=\(Int(UserDefaults.standard.double(forKey: "LayoutBar_delimiterX_\(section.name.displayString)")))")
                            .font(.system(size: 8))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                }
                ForEach(items) { item in
                    LayoutItemView(item: item)
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
            // Delay slightly to ensure windows are available for capture
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                refreshItems()
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
        print("[LayoutBar] Section: \(section.name.displayString)")
        print("[LayoutBar] Found \(allWindows.count) windows")
        for window in allWindows {
            print("[LayoutBar]   - \(window.ownerName) | \(window.title) | x=\(window.frame.origin.x) | isDelimiter=\(window.isDelimiter)")
        }
        items = filterWindowsForSection(allWindows)
        print("[LayoutBar] After filtering: \(items.count) items")
        isRefreshing = false
    }

    private func filterWindowsForSection(_ windows: [LayoutItemInfo]) -> [LayoutItemInfo] {
        let sortedWindows = windows.sorted { $0.frame.origin.x < $1.frame.origin.x }

        let delimiter = sortedWindows.first { $0.isDelimiter }
        let delimiterX = delimiter?.frame.origin.x ?? 0

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

    private func moveItem(windowID: CGWindowID, to section: MenuBarSection) {
        print("Moving window \(windowID) to section \(section.name.displayString)")
        draggedItem = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.refreshItems()
        }
    }
}
