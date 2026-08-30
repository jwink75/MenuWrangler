//
//  LayoutItemView.swift
//  Ice
//

import SwiftUI

struct LayoutItemView: View {
    let item: LayoutItemInfo

    var body: some View {
        Image(nsImage: item.image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 24, height: 24)
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
            )
            .help(item.ownerName.isEmpty ? "Menu Bar Item" : item.ownerName)
    }
}
