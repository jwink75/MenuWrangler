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

        // 3. Try Accessibility query (direct point or full Control Center AX tree)
        if let axName = LayoutItemInfo.queryAccessibilityName(for: frame, windowID: windowID),
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

    private static func queryAccessibilityName(for frame: CGRect, windowID: CGWindowID) -> String? {
        let genericTitles: Set<String> = [
            "Item-0", "Item-1", "Item-2", "Item-3", "Item-4", "Item-5", "Item-6", "Item-7", "Item-8", "Item-9",
            "BentoBox-0", "BentoBox", "Window Server", "Main Status Menu", "StatusItem", "Control Center", "ControlCenter"
        ]

        // 1. Direct point query for on-screen items
        let point = CGPoint(x: frame.midX, y: frame.midY)
        if point.x > 0 {
            var element: AXUIElement?
            if AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &element) == .success,
               let element {
                var value: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &value) == .success,
                   let desc = value as? String, !desc.isEmpty && !genericTitles.contains(desc) {
                    return desc
                }
                if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value) == .success,
                   let title = value as? String, !title.isEmpty && !genericTitles.contains(title) {
                    return title
                }
            }
        }

        // 2. Query Control Center AX application hierarchy
        guard let controlCenter = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first else {
            return nil
        }
        let appAX = AXUIElementCreateApplication(controlCenter.processIdentifier)
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appAX, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return nil
        }

        for child in children {
            var subChildrenRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(child, kAXChildrenAttribute as CFString, &subChildrenRef) == .success,
               let subChildren = subChildrenRef as? [AXUIElement] {
                for item in subChildren {
                    var descRef: CFTypeRef?
                    if AXUIElementCopyAttributeValue(item, kAXDescriptionAttribute as CFString, &descRef) == .success,
                       let desc = descRef as? String, !desc.isEmpty && !genericTitles.contains(desc) {
                        return desc
                    }
                    if AXUIElementCopyAttributeValue(item, kAXTitleAttribute as CFString, &descRef) == .success,
                       let title = descRef as? String, !title.isEmpty && !genericTitles.contains(title) {
                        return title
                    }
                    if AXUIElementCopyAttributeValue(item, kAXHelpAttribute as CFString, &descRef) == .success,
                       let help = descRef as? String, !help.isEmpty && !genericTitles.contains(help) {
                        return help
                    }
                }
            }
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
