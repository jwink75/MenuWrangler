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

        // 1. If explicit custom title exists (and is not generic), use it
        if !title.isEmpty && !genericTitles.contains(title) && !title.hasPrefix("Item-") && !title.hasPrefix("BentoBox-") {
            return title
        }

        // 2. Check title-based system keywords
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

        // 3. Try Accessibility query
        if let axName = LayoutItemInfo.queryAccessibilityName(for: frame),
           !axName.isEmpty && !genericTitles.contains(axName) && axName != "Control Center" && axName != "ControlCenter" {
            return axName
        }

        // 4. Check MenuBarItem displayName from legacy introspection
        if let legacyDisplayName = MenuBarItem(windowID: windowID)?.displayName,
           legacyDisplayName != "Unknown" && legacyDisplayName != "ControlCenter" && legacyDisplayName != "Control Center" && !genericTitles.contains(legacyDisplayName) {
            return legacyDisplayName
        }

        // 5. Resolve via NSRunningApplication localizedName
        if let app = NSRunningApplication(processIdentifier: ownerPID),
           let localizedName = app.localizedName,
           !localizedName.isEmpty,
           localizedName != "ControlCenter" && localizedName != "Control Center" && localizedName != "Window Server" {
            return localizedName
        }

        // 6. Fall back to owner name if valid and not a system host
        if !ownerName.isEmpty && ownerName != "Unknown" && ownerName != "ControlCenter" && ownerName != "Control Center" && ownerName != "Window Server" {
            return ownerName
        }

        if title.hasPrefix("BentoBox") || titleLower == "bentobox" {
            return "Control Center"
        }

        return "Item #\(windowID % 1000)"
    }

    private static func queryAccessibilityName(for frame: CGRect) -> String? {
        let point = CGPoint(x: frame.midX, y: frame.midY)
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &element) == .success,
              let element else {
            return nil
        }
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &value) == .success,
           let desc = value as? String, !desc.isEmpty {
            return desc
        }
        if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value) == .success,
           let title = value as? String, !title.isEmpty {
            return title
        }
        return nil
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(windowID)
    }

    static func == (lhs: LayoutItemInfo, rhs: LayoutItemInfo) -> Bool {
        lhs.windowID == rhs.windowID
    }
}
