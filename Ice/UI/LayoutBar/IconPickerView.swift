//
//  IconPickerView.swift
//  Ice
//

import SwiftUI

struct IconPickerView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var selectedIcon: String
    
    let commonIcons: [(name: String, label: String)] = [
        ("folder", "Folder"),
        ("folder.fill", "Folder Filled"),
        ("chevron.left.2", "Chevron Left"),
        ("chevron.right.2", "Chevron Right"),
        ("ellipsis", "Ellipsis"),
        ("ellipsis.circle", "Ellipsis Circle"),
        ("circle.dotted", "Circle Dotted"),
        ("dot.circle", "Dot Circle"),
        ("dot.circle.fill", "Dot Circle Filled"),
        ("cloud", "Cloud"),
        ("cloud.fill", "Cloud Filled"),
        ("cloud.rain", "Rain Cloud"),
        ("square.grid.2x2", "Grid"),
        ("rectangle.stack", "Stack"),
        ("rectangle.3.group", "Group"),
        ("circle.group", "Circle Group"),
        ("sparkles", "Sparkles"),
        ("star", "Star"),
        ("star.fill", "Star Filled"),
        ("heart", "Heart"),
        ("heart.fill", "Heart Filled"),
        ("flame", "Flame"),
        ("flame.fill", "Flame Filled"),
        ("bolt", "Bolt"),
        ("bolt.fill", "Bolt Filled"),
        ("paintbrush", "Paintbrush"),
        ("paintbrush.pointed", "Paintbrush Pointed"),
        ("scissors", "Scissors"),
        ("scissors.crop", "Scissors Crop"),
        ("opticaldisc", "Optical Disc"),
        ("opticaldiscdrive", "Optical Drive"),
        ("menubar", "Menu Bar"),
        ("menubar.rectangle", "Menu Bar Rectangle"),
        ("square.masonry", "Masonry"),
        ("sidebar.left", "Sidebar Left"),
        ("sidebar.right", "Sidebar Right"),
        ("bookmark", "Bookmark"),
        ("bookmark.fill", "Bookmark Filled"),
        ("tag", "Tag"),
        ("tag.fill", "Tag Filled"),
        ("list.bullet", "List"),
        ("checklist", "Checklist"),
        ("exclamationmark.circle", "Alert"),
        ("exclamationmark.circle.fill", "Alert Filled"),
        ("questionmark.circle", "Question"),
        ("questionmark.circle.fill", "Question Filled"),
        ("info.circle", "Info"),
        ("info.circle.fill", "Info Filled"),
        ("shield", "Shield"),
        ("shield.fill", "Shield Filled"),
        ("lock", "Lock"),
        ("lock.fill", "Lock Filled"),
        ("key", "Key"),
        ("key.fill", "Key Filled"),
    ]
    
    var body: some View {
        VStack {
            Text("Choose Folder Icon")
                .font(.headline)
                .padding()
            
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 16) {
                    ForEach(commonIcons, id: \.name) { icon in
                        Button(action: {
                            selectedIcon = icon.name
                            dismiss()
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: icon.name)
                                    .font(.title2)
                                Text(icon.label)
                                    .font(.caption)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(width: 60)
                        }
                        .buttonStyle(.plain)
                        .background(icon.name == selectedIcon ? Color.accentColor.opacity(0.2) : Color.clear)
                        .cornerRadius(8)
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 350, minHeight: 400)
    }
}
