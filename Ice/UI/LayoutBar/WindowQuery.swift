//
//  WindowQuery.swift
//  Ice
//

import Cocoa

enum WindowQuery {
    /// Cache for resolved window images to avoid repeated screen capture overhead
    private static var windowIconCache: [CGWindowID: NSImage] = [:]
    private static let cacheLock = NSLock()

    static func getMenuBarWindows() -> [LayoutItemInfo] {
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

            let frame = windowInfo.frame

            // Filter out phantom windows, spacers, and zero-dimension proxy windows
            guard frame.width > 4 && frame.height > 8 else {
                return nil
            }

            // Filter out fully transparent / hidden helper windows
            guard windowInfo.alpha > 0.05 else {
                return nil
            }

            let ownerName = windowInfo.ownerName ?? "Unknown"
            let windowTitle = windowInfo.title ?? ""
            let ownerPID = windowInfo.ownerPID
            let bundleIdentifier = NSRunningApplication(processIdentifier: ownerPID)?.bundleIdentifier

            // Collect debug info
            allOwnerNames.insert(ownerName)
            if !windowTitle.isEmpty {
                allTitles.insert(windowTitle)
            }

            // Identify delimiter: "HItem" / "SItem" / MenuWrangler process
            let isDelimiter = (windowTitle == "HItem" || windowTitle == "SItem" || ownerName == "MenuWrangler" || ownerName == "Ice" || ownerPID == NSRunningApplication.current.processIdentifier)

            let image = resolveImage(
                for: windowID,
                ownerPID: ownerPID,
                ownerName: ownerName,
                bundleIdentifier: bundleIdentifier,
                title: windowTitle,
                frame: frame
            )

            return LayoutItemInfo(
                windowID: windowID,
                image: image,
                ownerPID: ownerPID,
                ownerName: ownerName,
                bundleIdentifier: bundleIdentifier,
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

    private static func resolveImage(
        for windowID: CGWindowID,
        ownerPID: pid_t,
        ownerName: String,
        bundleIdentifier: String?,
        title: String,
        frame: CGRect
    ) -> NSImage {
        cacheLock.lock()
        if let cached = windowIconCache[windowID] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let image = createImage(
            for: windowID,
            ownerPID: ownerPID,
            ownerName: ownerName,
            bundleIdentifier: bundleIdentifier,
            title: title,
            frame: frame
        )

        cacheLock.lock()
        windowIconCache[windowID] = image
        cacheLock.unlock()

        return image
    }

    private static func createImage(
        for windowID: CGWindowID,
        ownerPID: pid_t,
        ownerName: String,
        bundleIdentifier: String?,
        title: String,
        frame: CGRect
    ) -> NSImage {
        // 1. Try live screen capture first
        if let cgImage = ScreenCapture.captureWindow(windowID, screenBounds: frame, option: .boundsIgnoreFraming),
           cgImage.width > 0 && cgImage.height > 0,
           cgImage.hasVisiblePixels {
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            return NSImage(cgImage: cgImage, size: NSSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale))
        }

        // 2. Try CGWindowListCreateImage as fallback
        if let cgImage = CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, .boundsIgnoreFraming),
           cgImage.width > 0 && cgImage.height > 0,
           cgImage.hasVisiblePixels {
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            return NSImage(cgImage: cgImage, size: NSSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale))
        }

        let titleLower = title.lowercased()
        let ownerLower = ownerName.lowercased()
        let isControlCenter = (ownerName == "ControlCenter" || bundleIdentifier == "com.apple.controlcenter")

        // 3. For third-party apps, fetch the real application icon before falling back to generic symbols
        if !isControlCenter && ownerName != "SystemUIServer" && ownerName != "Window Server" {
            if let app = NSRunningApplication(processIdentifier: ownerPID), let icon = app.icon {
                return icon
            }
        }

        // 4. Try to find a matching SF Symbol based on title or keywords
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
        } else if titleLower.contains("display") || titleLower.contains("monitor") || titleLower.contains("brightness") {
            symbolName = "display"
        } else if titleLower.contains("focus") || titleLower.contains("dnd") || titleLower.contains("do not disturb") {
            symbolName = "moon.fill"
        } else if titleLower.contains("now playing") || titleLower.contains("music") || titleLower.contains("media") {
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
        } else if titleLower.contains("clock") || titleLower.contains("time") || titleLower.contains("date") {
            symbolName = "clock"
        } else if isControlCenter && (titleLower.contains("bentobox") || titleLower.contains("controlcenter") || titleLower.contains("control center")) {
            symbolName = "switch.2"
        } else {
            symbolName = nil
        }

        if let symbolName, let symbolImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: ownerName) {
            symbolImage.isTemplate = true
            return symbolImage
        }

        // 5. Final fallback: generic menubar icon
        if let generic = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: ownerName) {
            generic.isTemplate = true
            return generic
        }

        return NSImage(size: NSSize(width: 24, height: 24))
    }

    /// Clears the window icon cache
    static func clearIconCache() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        windowIconCache.removeAll()
    }
}
