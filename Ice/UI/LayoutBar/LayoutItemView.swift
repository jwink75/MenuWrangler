//
//  LayoutItemView.swift
//  Ice
//

import SwiftUI

struct LayoutItemView: View {
    let item: LayoutItemInfo

    var body: some View {
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
        .help(item.resolvedTitle)
        .contentShape(Rectangle())
        .onDrag {
            NSItemProvider(object: "\(item.windowID)" as NSString)
        }
    }
}
