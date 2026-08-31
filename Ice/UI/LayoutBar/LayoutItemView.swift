//
//  LayoutItemView.swift
//  Ice
//

import SwiftUI

struct LayoutItemView: View {
    let item: LayoutItemInfo
    var onReorder: ((CGWindowID, LayoutItemInfo) -> Void)? = nil
    @State private var isTargeted = false

    var body: some View {
        HStack(spacing: 2) {
            if isTargeted {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 3, height: 36)
                    .shadow(color: Color.accentColor.opacity(0.5), radius: 2, x: 0, y: 0)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }

            VStack(spacing: 2) {
                Image(nsImage: item.image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                Text(item.resolvedTitle)
                    .font(.system(size: 8, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 54)
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
        }
        .help(item.resolvedTitle)
        .contentShape(Rectangle())
        .onDrag {
            NSItemProvider(object: "\(item.windowID)" as NSString)
        }
        .onDrop(of: [.text], isTargeted: $isTargeted.animation(.easeInOut(duration: 0.15))) { providers in
            guard let provider = providers.first else { return false }
            provider.loadObject(ofClass: NSString.self) { (object, error) in
                guard let windowIDString = object as? String,
                      let draggedID = UInt32(windowIDString),
                      draggedID != item.windowID else {
                    return
                }
                DispatchQueue.main.async {
                    onReorder?(draggedID, item)
                }
            }
            return true
        }
    }
}
