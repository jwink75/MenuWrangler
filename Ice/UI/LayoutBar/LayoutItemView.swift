//
//  LayoutItemView.swift
//  Ice
//

import SwiftUI

struct LayoutItemView: View {
    let item: LayoutItemInfo

    var body: some View {
        VStack(spacing: 1) {
            Image(nsImage: item.image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
            Text(item.title.isEmpty ? item.ownerName : item.title)
                .font(.system(size: 7))
                .lineLimit(1)
                .truncationMode(.tail)
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
        .help(item.title.isEmpty ? (item.ownerName.isEmpty ? "Menu Bar Item" : item.ownerName) : item.title)
        .contentShape(Rectangle())
    }
}
