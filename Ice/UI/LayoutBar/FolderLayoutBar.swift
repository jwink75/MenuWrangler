//
//  FolderLayoutBar.swift
//  Ice
//

import SwiftUI

struct FolderLayoutBar: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var folderManager = LayoutFolderManager.shared
    let folderName: String
    @State private var items: [LayoutItemInfo] = []
    @State private var isRefreshing = false
    @State private var lastRefreshTime: Date = .distantPast

    private let minimumRefreshInterval: TimeInterval = 0.3

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(folderName)
                    .font(.system(size: 14, weight: .medium))
                    .padding(.leading, 2)

                Spacer()

                Button(action: {
                    folderManager.deleteFolder(named: folderName)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }

            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 8) {
                    if items.isEmpty {
                        Text("No items")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                    }
                    ForEach(items) { item in
                        LayoutItemView(item: item, onReorder: { _, _ in
                            // Reorder within folder - no OS operation needed
                        })
                        .onDrag({
                            return NSItemProvider(object: String(item.windowID) as NSString)
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
            refreshItems()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MenuBarsNeedRefresh"))) { _ in
            refreshItems()
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
        let nonFoldered = allWindows.filter { !folderManager.folderAssignments.keys.contains($0.windowID) }
        items = folderManager.items(in: folderName, from: allWindows)

        isRefreshing = false
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadObject(ofClass: NSString.self) { (object, error) in
            guard let windowIDString = object as? String,
                  let windowID = UInt32(windowIDString) else {
                return
            }

            DispatchQueue.main.async {
                folderManager.assign(LayoutItemInfo.dummy(windowID: windowID), to: folderName)
                refreshItems()
            }
        }

        return true
    }
}

private extension LayoutItemInfo {
    static func dummy(windowID: CGWindowID) -> LayoutItemInfo {
        LayoutItemInfo(
            windowID: windowID,
            image: NSImage(),
            ownerPID: 0,
            ownerName: "",
            bundleIdentifier: nil,
            frame: .zero,
            title: "",
            isDelimiter: false
        )
    }
}
