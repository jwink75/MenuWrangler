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
            "BentoBox-0", "BentoBox", "Window Server", "Main Status Menu", "StatusItem",
            "AXMenuBar", "AXMenu", "AXPopup", "AXButton", "AXGroup", "AXApplication",
            "AXScrollArea", "AXMainGroup"
        ]

        // 1. If explicit custom title exists (and is not generic), use it
        if !title.isEmpty && !genericTitles.contains(title) && !title.hasPrefix("Item-") && !title.hasPrefix("BentoBox-") && !genericTitles.contains(where: { title.localizedCaseInsensitiveContains($0) }) {
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
           !axName.isEmpty && !genericTitles.contains(axName) && !genericTitles.contains(where: { axName.localizedCaseInsensitiveContains($0) }) {
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

        // Control Center modules typically have bundle IDs like com.apple.controlcenter.wifi
        // Try to identify specific modules
        if let bundleID = bundleIdentifier {
            let bundleIDLower = bundleID.lowercased()
            
            // First check if this is a Control Center module
            if bundleIDLower.contains("controlcenter") || bundleIDLower.contains("control-center") || bundleIDLower.contains("bento") || ownerName == "ControlCenter" {
                if bundleIDLower.contains("wifi") || bundleIDLower.contains("network") || bundleIDLower.contains("airport") {
                    return "Wi-Fi"
                } else if bundleIDLower.contains("bluetooth") || bundleIDLower.contains("bt") {
                    return "Bluetooth"
                } else if bundleIDLower.contains("sound") || bundleIDLower.contains("audio") || bundleIDLower.contains("speaker") {
                    return "Sound"
                } else if bundleIDLower.contains("display") || bundleIDLower.contains("brightness") || bundleIDLower.contains("monitor") || bundleIDLower.contains("airdrop") {
                    return "Display & Brightness"
                } else if bundleIDLower.contains("battery") || bundleIDLower.contains("power") {
                    return "Battery"
                } else if bundleIDLower.contains("focus") || bundleIDLower.contains("dnd") || bundleIDLower.contains("do-not-disturb") || bundleIDLower.contains("donotdisturb") {
                    return "Focus"
                } else if bundleIDLower.contains("airplane") || bundleIDLower.contains("airplanemode") {
                    return "AirPlane Mode"
                } else if bundleIDLower.contains("screen") && bundleIDLower.contains("mirror") {
                    return "Screen Mirror"
                } else if bundleIDLower.contains("screen") && (bundleIDLower.contains("time") || bundleIDLower.contains("limits")) {
                    return "Screen Time"
                } else if bundleIDLower.contains("airplay") || bundleIDLower.contains("airplayvisual") {
                    return "AirPlay"
                } else if bundleIDLower.contains("home") {
                    return "Home"
                } else if bundleIDLower.contains("nowplaying") || bundleIDLower.contains("now-playing") || bundleIDLower.contains("media") || bundleIDLower.contains("music") {
                    return "Now Playing"
                } else if bundleIDLower.contains("siri") || bundleIDLower.contains("voice") {
                    return "Siri"
                } else if bundleIDLower.contains("clock") || bundleIDLower.contains("time") || bundleIDLower.contains("date") || bundleIDLower.contains("timer") {
                    return "Clock"
                } else if bundleIDLower.contains("keyboard") || bundleIDLower.contains("textinput") || bundleIDLower.contains("dictation") || bundleIDLower.contains("input") {
                    return "Keyboard"
                } else if bundleIDLower.contains("trackpad") || bundleIDLower.contains("mouse") || bundleIDLower.contains("mouse") {
                    return "Trackpad/Mouse"
                } else if bundleIDLower.contains("character") || bundleIDLower.contains("emoji") {
                    return "Character Viewer"
                } else if bundleIDLower.contains("shortcuts") || bundleIDLower.contains("script") {
                    return "Shortcuts"
                } else if bundleIDLower.contains("accessibility") || bundleIDLower.contains("a11y") {
                    return "Accessibility"
                } else if bundleIDLower.contains("calendar") {
                    return "Calendar"
                } else if bundleIDLower.contains("spotlight") || bundleIDLower.contains("search") {
                    return "Spotlight"
                } else if bundleIDLower.contains("timemachine") || bundleIDLower.contains("time-machine") {
                    return "Time Machine"
                } else {
                    return "Control Center"
                }
            }

            // Non-Control Center apps
            if bundleIDLower.contains("wifi") {
                return "Wi-Fi"
            } else if bundleIDLower.contains("bluetooth") {
                return "Bluetooth"
            } else if bundleIDLower.contains("sound") || bundleIDLower.contains("audio") {
                return "Sound"
            } else if bundleIDLower.contains("display") || bundleIDLower.contains("brightness") {
                return "Display"
            } else if bundleIDLower.contains("battery") || bundleIDLower.contains("power") {
                return "Battery"
            } else if bundleIDLower.contains("airdrop") {
                return "AirDrop"
            } else if bundleIDLower.contains("focus") || bundleIDLower.contains("dnd") || bundleIDLower.contains("do-not-disturb") {
                return "Focus"
            } else if bundleIDLower.contains("network") {
                return "Network"
            } else if bundleIDLower.contains("airport") {
                return "Wi-Fi"
            } else if bundleIDLower.contains("clock") || bundleIDLower.contains("time") {
                return "Clock"
            } else if bundleIDLower.contains("nowplaying") || bundleIDLower.contains("now-playing") || bundleIDLower.contains("media") {
                return "Now Playing"
            } else if bundleIDLower.contains("screen") && bundleIDLower.contains("mirror") {
                return "Screen Mirror"
            } else if bundleIDLower.contains("screen") {
                return "Screen Time"
            } else if bundleIDLower.contains("airplay") || bundleIDLower.contains("airplayvisual") {
                return "AirPlay"
            } else if bundleIDLower.contains("home") {
                return "Home"
            } else if bundleIDLower.contains("calendar") {
                return "Calendar"
            } else if bundleIDLower.contains("shortcuts") || bundleIDLower.contains("script") {
                return "Shortcuts"
            } else if bundleIDLower.contains("accessibility") {
                return "Accessibility"
            } else if bundleIDLower.contains("keyboard") {
                return "Keyboard"
            } else if bundleIDLower.contains("trackpad") || bundleIDLower.contains("mouse") {
                return "Trackpad/Mouse"
            } else if bundleIDLower.contains("dictation") {
                return "Dictation"
            } else if bundleIDLower.contains("siri") {
                return "Siri"
            } else if bundleIDLower.contains("emoji") || bundleIDLower.contains("character") {
                return "Character Viewer"
            } else if bundleIDLower.contains("controlcenter") || bundleIDLower.contains("control-center") || bundleIDLower.contains("bento") {
                return "Control Center"
            } else if bundleIDLower.contains("spotlight") {
                return "Spotlight"
            } else if bundleIDLower.contains("time-machine") || bundleIDLower.contains("timemachine") {
                return "Time Machine"
            }
        }

        return "Item #\(windowID % 1000)"
    }

    private static var titleCache: [CGWindowID: String] = [:]
    private static let titleCacheLock = NSLock()

    static func recordTitle(_ title: String, for windowID: CGWindowID) {
        let genericTitles: Set<String> = [
            "Item-0", "Item-1", "Item-2", "Item-3", "Item-4", "Item-5", "Item-6", "Item-7", "Item-8", "Item-9",
            "BentoBox-0", "BentoBox", "Window Server", "Main Status Menu", "StatusItem",
            "AXMenuBar", "AXMenu", "AXPopup", "AXButton", "AXGroup", "AXApplication",
            "AXScrollArea", "AXMainGroup"
        ]
        guard !title.isEmpty, !title.hasPrefix("Item-"), !title.hasPrefix("BentoBox"), title != "Control Center", !genericTitles.contains(title) else { return }
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
            "BentoBox-0", "BentoBox", "Window Server", "Main Status Menu", "StatusItem", "Control Center", "ControlCenter",
            "AXMenuBar", "AXMenu", "AXPopup", "AXButton", "AXGroup", "AXApplication",
            "AXScrollArea", "AXMainGroup"
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
