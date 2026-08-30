//
//  LayoutItemInfo.swift
//  Ice
//

import Cocoa

struct LayoutItemInfo: Identifiable, Hashable {
    let id = UUID()
    let windowID: CGWindowID
    let image: NSImage
    let ownerPID: pid_t
    let ownerName: String
    let bundleIdentifier: String?
    let frame: CGRect
    let title: String
    let isDelimiter: Bool

    var isMovable: Bool { !isDelimiter }

    var resolvedTitle: String {
        let genericTitles: Set<String> = [
            "Item-0", "Item-1", "Item-2", "Item-3", "Item-4", "Item-5", "Item-6", "Item-7", "Item-8", "Item-9",
            "BentoBox-0", "BentoBox", "Window Server", "Main Status Menu", "StatusItem"
        ]

        if !title.isEmpty && !genericTitles.contains(title) && !title.hasPrefix("Item-") && !title.hasPrefix("BentoBox-") {
            return title
        }

        if let app = NSRunningApplication(processIdentifier: ownerPID),
           let localizedName = app.localizedName,
           !localizedName.isEmpty,
           localizedName != "ControlCenter" && localizedName != "Window Server" {
            return localizedName
        }

        if !ownerName.isEmpty && ownerName != "Unknown" && ownerName != "ControlCenter" && ownerName != "Window Server" {
            return ownerName
        }

        // Check title-based system keywords
        let titleLower = title.lowercased()
        if titleLower.contains("wifi") || titleLower.contains("wi-fi") {
            return "Wi-Fi"
        } else if titleLower.contains("battery") || titleLower.contains("power") {
            return "Battery"
        } else if titleLower.contains("bluetooth") {
            return "Bluetooth"
        } else if titleLower.contains("sound") || titleLower.contains("volume") || titleLower.contains("audio") {
            return "Sound"
        } else if titleLower.contains("display") || titleLower.contains("brightness") {
            return "Display"
        } else if titleLower.contains("clock") || titleLower.contains("time") || titleLower.contains("date") {
            return "Clock"
        } else if titleLower.contains("focus") || titleLower.contains("dnd") {
            return "Focus"
        } else if titleLower.contains("music") || titleLower.contains("now playing") || titleLower.contains("media") {
            return "Now Playing"
        } else if titleLower.contains("airdrop") {
            return "AirDrop"
        }

        if ownerName == "ControlCenter" {
            return "Control Center"
        }

        return "Status Item"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(windowID)
    }

    static func == (lhs: LayoutItemInfo, rhs: LayoutItemInfo) -> Bool {
        lhs.windowID == rhs.windowID
    }
}
