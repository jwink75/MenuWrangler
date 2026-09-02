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
        ("ellipsis.vertical", "Ellipsis Vertical"),
        ("circle.dotted", "Circle Dotted"),
        ("dot.circle", "Dot Circle"),
        ("dot.circle.fill", "Dot Circle Filled"),
        ("circle.circle", "Circle"),
        ("circle.circle.fill", "Circle Filled"),
        // Arrow shapes (matching existing icon sets)
        ("arrowshape.left.fill", "Arrow Left"),
        ("arrowshape.right.fill", "Arrow Right"),
        ("chevron.left", "Chevron Left"),
        ("chevron.right", "Chevron Right"),
        // Door (matching existing icon sets)
        ("door.left.hand.closed", "Door Closed"),
        ("door.left.hand.open", "Door Open"),
        // Dot styles
        ("circle.fill", "Dot Fill"),
        ("circle", "Dot Stroke"),
        // Sunglasses
        ("sunglasses.fill", "Sunglasses"),
        ("sunglasses", "Sunglasses Outline"),
        // Cloud services
        ("cloud", "Cloud"),
        ("cloud.fill", "Cloud Filled"),
        ("cloud.rain", "Rain Cloud"),
        ("cloud.hail", "Hail Cloud"),
        ("cloud.snow", "Snow Cloud"),
        ("cloud.bolt", "Lightning Cloud"),
        ("icloud", "iCloud"),
        ("icloud.fill", "iCloud Filled"),
        ("icloud.and.arrow.up", "Upload"),
        ("icloud.and.arrow.down", "Download"),
        ("server.rack", "Server"),
        ("server.rack.fill", "Server Filled"),
        // Network/Cloud services
        ("network.badge.person.crop", "Network"),
        ("antenna.function", "Antenna"),
        ("radiowaves.forward", "Signal"),
        // Computers
        ("desktopcomputer", "Desktop"),
        ("laptopcomputer", "Laptop"),
        // Menu bar icons
        ("menubar", "Menu Bar"),
        ("menubar.rectangle", "Menu Bar Rectangle"),
        ("square.masonry", "Masonry"),
        ("sidebar.left", "Sidebar Left"),
        ("sidebar.right", "Sidebar Right"),
        ("square.grid.2x2", "Grid 2x2"),
        ("rectangle.stack", "Stack"),
        ("rectangle.3.group", "Group"),
        ("circle.group", "Circle Group"),
        ("sparkles", "Sparkles"),
        ("star", "Star"),
        ("star.fill", "Star Filled"),
        ("play.circle", "Play"),
        ("play.circle.fill", "Play Filled"),
        ("pause.circle", "Pause"),
        ("pause.circle.fill", "Pause Filled"),
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
        ("tag", "Tag"),
        ("tag.fill", "Tag Filled"),
        ("bookmark", "Bookmark"),
        ("bookmark.fill", "Bookmark Filled"),
        ("list.bullet", "List"),
        ("checklist", "Checklist"),
        ("flame", "Flame"),
        ("flame.fill", "Flame Filled"),
        ("bolt", "Bolt"),
        ("bolt.fill", "Bolt Filled"),
        ("heart", "Heart"),
        ("heart.fill", "Heart Filled"),
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
