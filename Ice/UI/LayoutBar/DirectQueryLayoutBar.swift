//
//  DirectQueryLayoutBar.swift
//  Ice
//

import SwiftUI

struct DirectQueryLayoutBar: View {
    let section: MenuBarSection
    @State private var items: [LayoutItemInfo] = []

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    LayoutItemView(item: item)
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
            refreshItems()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshItems()
        }
    }

    private func refreshItems() {
        let allWindows = WindowQuery.getMenuBarWindows()
        items = filterWindowsForSection(allWindows)
    }

    private func filterWindowsForSection(_ windows: [LayoutItemInfo]) -> [LayoutItemInfo] {
        let currentPID = NSRunningApplication.current.processIdentifier
        let sortedWindows = windows.sorted { $0.frame.origin.x < $1.frame.origin.x }

        let delimiterX: CGFloat
        if let delimiter = sortedWindows.first(where: { window in
            window.ownerPID == currentPID || window.ownerName == "MenuWrangler" || window.ownerName == "Ice"
        }) {
            delimiterX = delimiter.frame.origin.x
        } else {
            delimiterX = (NSScreen.main?.frame.width ?? 1200) * 0.75
        }

        let nonSelfWindows = sortedWindows.filter { window in
            window.ownerPID != currentPID && window.ownerName != "MenuWrangler" && window.ownerName != "Ice"
        }

        switch section.name {
        case .visible:
            return nonSelfWindows.filter { $0.frame.origin.x >= delimiterX }
        case .hidden:
            return nonSelfWindows.filter { $0.frame.origin.x < delimiterX }
        case .alwaysHidden:
            return []
        }
    }
}
