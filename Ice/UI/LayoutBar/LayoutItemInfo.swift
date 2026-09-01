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

        // 3. Check persistent title cache
        if let cached = LayoutItemInfo.cachedTitle(for: windowID) {
            return cached
        }

        // 4. Try Accessibility query (direct point or full Control Center AX tree)
        if let axName = LayoutItemInfo.queryAccessibilityName(for: frame, windowID: windowID),
           !axName.isEmpty && !genericTitles.contains(axName) && axName != "Control Center" && axName != "ControlCenter" {
            LayoutItemInfo.recordTitle(axName, for: windowID)
            return axName
        }

        // 5. Check MenuBarItem displayName from legacy introspection
        if let legacyDisplayName = MenuBarItem(windowID: windowID)?.displayName,
           legacyDisplayName != "Unknown" && legacyDisplayName != "ControlCenter" && legacyDisplayName != "Control Center" && !genericTitles.contains(legacyDisplayName) {
            LayoutItemInfo.recordTitle(legacyDisplayName, for: windowID)
            return legacyDisplayName
        }

        // 6. Resolve via NSRunningApplication localizedName
        if let app = NSRunningApplication(processIdentifier: ownerPID),
           let localizedName = app.localizedName,
           !localizedName.isEmpty,
           localizedName != "ControlCenter" && localizedName != "Control Center" && localizedName != "Window Server" {
            LayoutItemInfo.recordTitle(localizedName, for: windowID)
            return localizedName
        }

        // 7. Fall back to owner name if valid and not a system host
        if !ownerName.isEmpty && ownerName != "Unknown" && ownerName != "ControlCenter" && ownerName != "Control Center" && ownerName != "Window Server" {
            LayoutItemInfo.recordTitle(ownerName, for: windowID)
            return ownerName
        }

        if title.hasPrefix("BentoBox") || titleLower == "bentobox" {
            return "Control Center"
        }

        return "Item #\(windowID % 1000)"
    }

    private static var titleCache: [CGWindowID: String] = [:]
    private static let titleCacheLock = NSLock()

    static func recordTitle(_ title: String, for windowID: CGWindowID) {
        guard !title.isEmpty, !title.hasPrefix("Item-"), !title.hasPrefix("BentoBox"), title != "Control Center" else { return }
        titleCacheLock.lock()
        titleCache[windowID] = title
        titleCacheLock.unlock()
    }

    static func cachedTitle(for windowID: CGWindowID) -> String? {
        titleCacheLock.lock()
        defer { titleCacheLock.unlock() }
        return titleCache[windowID]
    }

    private static func queryAccessibilityName(for frame: CGRect, windowID: CGWindowID) -> String? {
        let genericTitles: Set<String> = [
            "Item-0", "Item-1", "Item-2", "Item-3", "Item-4", "Item-5", "Item-6", "Item-7", "Item-8", "Item-9",
            "BentoBox-0", "BentoBox", "Window Server", "Main Status Menu", "StatusItem", "Control Center", "ControlCenter"
        ]

        // Check ALL points in the frame at multiple rows/columns
        let menuBarHeight = NSStatusBar.system.thickness
        let rows = max(1, Int(frame.height / 4))
        let cols = max(1, min(10, Int(frame.width / max(4, frame.width / 20))))

        for row in 0..<rows {
            for col in 0..<cols {
                let point = CGPoint(
                    x: frame.origin.x + CGFloat(col) * (frame.width / CGFloat(cols)),
                    y: frame.origin.y + CGFloat(row) * (frame.height / CGFloat(rows)) + menuBarHeight
                )

                if point.x > 0 && point.y > 0 {
                    var element: AXUIElement?
                    if AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &element) == .success,
                       let element {
                        // Try multiple attributes
                        for attr: String in [kAXDescriptionAttribute, kAXTitleAttribute, kAXValueAttribute, kAXRoleAttribute] {
                            var value: CFTypeRef?
                            if AXUIElementCopyAttributeValue(element, attr as CFString, &value) == .success,
                               let str = value as? String, !str.isEmpty && !genericTitles.contains(str) {
                                return str
                            }
                        }
                    }
                }
            }
        }

        // Query Control Center AX application hierarchy
        guard let controlCenter = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first else {
            return nil
        }
        let appAX = AXUIElementCreateApplication(controlCenter.processIdentifier)
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appAX, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return nil
        }

        // Recursive search through children
        func searchChildren(_ elements: [AXUIElement], depth: Int) -> String? {
            guard depth < 5 else { return nil }
            for child in elements {
                var subChildrenRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(child, kAXChildrenAttribute as CFString, &subChildrenRef) == .success,
                   let subChildren = subChildrenRef as? [AXUIElement], !subChildren.isEmpty {

                    // Check this element's position
                    var posRef: CFTypeRef?
                    if AXUIElementCopyAttributeValue(child, kAXPositionAttribute as CFString, &posRef) == .success,
                       let posRef {
                        var axPoint = CGPoint.zero
                        if AXValueGetValue(posRef as! AXValue, .cgPoint, &axPoint) {
                            if abs(axPoint.x - frame.midX) < 20 {
                                for attr: String in [kAXDescriptionAttribute, kAXTitleAttribute] {
                                    var descRef: CFTypeRef?
                                    if AXUIElementCopyAttributeValue(child, attr as CFString, &descRef) == .success,
                                       let desc = descRef as? String, !desc.isEmpty && !genericTitles.contains(desc) {
                                        return desc
                                    }
                                }
                            }
                        }
                    }

                    // Recurse into children
                    if let found = searchChildren(subChildren, depth: depth + 1) {
                        return found
                    }
                }
            }
            return nil
        }

        return searchChildren(children, depth: 0)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(windowID)
    }

    static func == (lhs: LayoutItemInfo, rhs: LayoutItemInfo) -> Bool {
        lhs.windowID == rhs.windowID
    }
}
