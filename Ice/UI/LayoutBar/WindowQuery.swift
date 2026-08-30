//
//  WindowQuery.swift
//  Ice
//

import Cocoa

enum WindowQuery {
    /// Cache for application icons to avoid repeated LaunchServices queries
    private static var iconCache: [pid_t: NSImage] = [:]
    private static let iconCacheLock = NSLock()

    static func getMenuBarWindows() -> [LayoutItemInfo] {
        // Use the same approach as the original Ice code - more reliable than CGWindowListCopyWindowInfo
        let windowIDs = Bridging.getWindowList(option: [.menuBarItems])

        var allOwnerNames: Set<String> = []
        var allTitles: Set<String> = []

        let result = windowIDs.compactMap { windowID -> LayoutItemInfo? in
            guard let windowInfo = WindowInfo(windowID: windowID) else {
                return nil
            }

            // Only include items at the status window layer (layer 25)
            guard windowInfo.isMenuBarItem else {
                return nil
            }

            let ownerName = windowInfo.ownerName ?? "Unknown"
            let windowTitle = windowInfo.title ?? ""
            let ownerPID = windowInfo.ownerPID
            let frame = windowInfo.frame

            // Collect debug info
            allOwnerNames.insert(ownerName)
            if !windowTitle.isEmpty {
                allTitles.insert(windowTitle)
            }

            // Identify delimiter by title: "HItem" is the hidden section delimiter
            let isDelimiter = (windowTitle == "HItem" || ownerName == "MenuWrangler" || ownerName == "Ice")

            let image = createFallbackImage(for: windowID, ownerPID: ownerPID, ownerName: ownerName, title: windowTitle, frame: frame)

            return LayoutItemInfo(
                windowID: windowID,
                image: image,
                ownerPID: ownerPID,
                ownerName: ownerName,
                frame: frame,
                title: windowTitle,
                isDelimiter: isDelimiter
            )
        }

        // Debug info
        UserDefaults.standard.set(windowIDs.count, forKey: "WindowQuery_totalWindows")
        UserDefaults.standard.set(result.count, forKey: "WindowQuery_windowsAtLayer25")
        UserDefaults.standard.set(allOwnerNames.sorted().joined(separator: ","), forKey: "WindowQuery_allOwners")
        UserDefaults.standard.set(allTitles.sorted().joined(separator: ","), forKey: "WindowQuery_allTitles")

        return result
    }

    private static func createFallbackImage(for windowID: CGWindowID, ownerPID: pid_t, ownerName: String, title: String, frame: CGRect) -> NSImage {
        // Try screen capture first
        if let cgImage = ScreenCapture.captureWindow(windowID, screenBounds: frame, option: .boundsIgnoreFraming),
           cgImage.width > 0 && cgImage.height > 0,
           cgImage.hasVisiblePixels {
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            let img = NSImage(cgImage: cgImage, size: NSSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale))
            return img
        }

        // Try CGWindowListCreateImage as fallback
        if let cgImage = CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, .boundsIgnoreFraming),
           cgImage.width > 0 && cgImage.height > 0,
           cgImage.hasVisiblePixels {
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            let img = NSImage(cgImage: cgImage, size: NSSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale))
            return img
        }

        let titleLower = title.lowercased()
        let ownerLower = ownerName.lowercased()

        // Try to find a matching SF Symbol based on title
        let symbolName: String?
        if titleLower.contains("wifi") || titleLower.contains("wi-fi") {
            symbolName = "wifi"
        } else if titleLower.contains("battery") || titleLower.contains("power") {
            symbolName = "battery.100"
        } else if titleLower.contains("bluetooth") {
            symbolName = "bolt"
        } else if titleLower.contains("sound") || titleLower.contains("volume") || titleLower.contains("audio") {
            symbolName = "speaker.wave.2"
        } else if titleLower.contains("airdrop") {
            symbolName = "airdrop"
        } else if titleLower.contains("display") || titleLower.contains("monitor") {
            symbolName = "display"
        } else if titleLower.contains("focus") || titleLower.contains("dnd") || titleLower.contains("do not disturb") {
            symbolName = "moon.fill"
        } else if titleLower.contains("now playing") || titleLower.contains("music") {
            symbolName = "play.circle"
        } else if titleLower.contains("spotlight") || titleLower.contains("search") {
            symbolName = "magnifyingglass"
        } else if titleLower.contains("siri") || titleLower.contains("voice") {
            symbolName = "waveform"
        } else if titleLower.contains("textinput") || titleLower.contains("input") {
            symbolName = "character.cursor.ibeam"
        } else if titleLower.contains("warp") || titleLower.contains("terminal") || titleLower.contains("shell") {
            symbolName = "terminal"
        } else if titleLower.contains("rectangle") || titleLower.contains("window manager") {
            symbolName = "rectangle.on.rectangle"
        } else if titleLower.contains("launcher") || titleLower.contains("grid") {
            symbolName = "square.grid.3x3"
        } else if titleLower.contains("dropbox") || ownerLower.contains("dropbox") {
            symbolName = "shippingbox"
        } else if titleLower.contains("keyboard") || titleLower.contains("maestro") || titleLower.contains("macro") {
            symbolName = "command"
        } else if titleLower.contains("media") || titleLower.contains("play") {
            symbolName = "play.circle"
        } else if titleLower.contains("clock") || titleLower.contains("time") || titleLower.contains("date") {
            symbolName = "clock"
        } else if titleLower.contains("controlcenter") || titleLower.contains("control center") {
            symbolName = "switch.2"
        } else {
            symbolName = nil
        }

        if let symbolName, let symbolImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: ownerName) {
            symbolImage.isTemplate = true
            return symbolImage
        }

        // Try to get the application icon
        let appIcon = cachedIcon(for: ownerPID, ownerName: ownerName)
        if appIcon.size != NSSize(width: 24, height: 24) {
            return appIcon
        }

        // Final fallback: generic menubar icon
        if let generic = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: ownerName) {
            generic.isTemplate = true
            return generic
        }

        return NSImage(size: NSSize(width: 24, height: 24))
    }

    /// Returns a cached icon for the given PID, or fetches and caches it
    private static func cachedIcon(for ownerPID: pid_t, ownerName: String) -> NSImage {
        iconCacheLock.lock()
        defer { iconCacheLock.unlock() }

        if let cached = iconCache[ownerPID] {
            return cached
        }

        var icon: NSImage?
        if let app = NSRunningApplication(processIdentifier: ownerPID) {
            icon = app.icon
        }

        if let icon {
            iconCache[ownerPID] = icon
            return icon
        }

        if let generic = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: ownerName) {
            generic.isTemplate = true
            return generic
        }

        return NSImage(size: NSSize(width: 24, height: 24))
    }

    /// Clears the icon cache (useful for testing or when apps change)
    static func clearIconCache() {
        iconCacheLock.lock()
        defer { iconCacheLock.unlock() }
        iconCache.removeAll()
    }
}
