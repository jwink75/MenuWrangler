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
        print("[WindowQuery] Window list count: \(windowIDs.count)")

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
            print("[WindowQuery] windowID=\(windowID) owner='\(ownerName)' pid=\(ownerPID) title='\(windowTitle)' bundleID='\(bundleIdentifier ?? "nil")' frame=\(frame) alpha=\(windowInfo.alpha)")

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
        let scale = NSScreen.main?.backingScaleFactor ?? 2

        // 1. Try live screen capture with nil bounds (.null - derives minimal enclosing rectangle)
        if let cgImage = ScreenCapture.captureWindow(windowID, screenBounds: nil, option: .boundsIgnoreFraming),
           cgImage.width > 0 && cgImage.height > 0,
           cgImage.hasVisiblePixels {
            return NSImage(cgImage: cgImage, size: NSSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale))
        }

        // 2. Try live screen capture with explicit frame bounds
        if let cgImage = ScreenCapture.captureWindow(windowID, screenBounds: frame, option: .boundsIgnoreFraming),
           cgImage.width > 0 && cgImage.height > 0,
           cgImage.hasVisiblePixels {
            return NSImage(cgImage: cgImage, size: NSSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale))
        }

        // 3. Try CGWindowListCreateImage as fallback
        if let cgImage = CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, .boundsIgnoreFraming),
           cgImage.width > 0 && cgImage.height > 0,
           cgImage.hasVisiblePixels {
            return NSImage(cgImage: cgImage, size: NSSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale))
        }

        let titleLower = title.lowercased()
        let ownerLower = ownerName.lowercased()
        let bundleLower = bundleIdentifier?.lowercased() ?? ""
        let isControlCenter = (ownerName == "ControlCenter" || bundleIdentifier == "com.apple.controlcenter" || bundleLower.contains("controlcenter") || bundleLower.contains("control-center") || bundleLower.contains("bento"))

        // 3. For third-party apps, fetch the real application icon before falling back to generic symbols
        if !isControlCenter && ownerName != "SystemUIServer" && ownerName != "Window Server" {
            if let app = NSRunningApplication(processIdentifier: ownerPID), let icon = app.icon {
                return icon
            }
        }

        // 4. Try to find a matching SF Symbol based on title or keywords
        let symbolName: String?
        if titleLower.contains("wifi") || titleLower.contains("wi-fi") || bundleLower.contains("wifi") || bundleLower.contains("airport") {
            symbolName = "wifi"
        } else if titleLower.contains("battery") || titleLower.contains("power") || bundleLower.contains("battery") || bundleLower.contains("power") {
            symbolName = "battery.100"
        } else if titleLower.contains("bluetooth") || bundleLower.contains("bluetooth") || bundleLower.contains("bt") {
            symbolName = "bolt"
        } else if titleLower.contains("sound") || titleLower.contains("volume") || titleLower.contains("audio") || bundleLower.contains("sound") || bundleLower.contains("audio") {
            symbolName = "speaker.wave.2"
        } else if titleLower.contains("airdrop") || bundleLower.contains("airdrop") {
            symbolName = "airdrop"
        } else if titleLower.contains("display") || titleLower.contains("monitor") || titleLower.contains("brightness") || bundleLower.contains("display") || bundleLower.contains("brightness") || bundleLower.contains("monitor") {
            symbolName = "display"
        } else if titleLower.contains("focus") || titleLower.contains("dnd") || titleLower.contains("do not disturb") || bundleLower.contains("focus") || bundleLower.contains("dnd") || bundleLower.contains("do-not-disturb") {
            symbolName = "moon.fill"
        } else if titleLower.contains("now playing") || titleLower.contains("music") || titleLower.contains("media") || bundleLower.contains("nowplaying") || bundleLower.contains("now-playing") || bundleLower.contains("media") {
            symbolName = "play.circle"
        } else if titleLower.contains("spotlight") || titleLower.contains("search") || bundleLower.contains("spotlight") {
            symbolName = "magnifyingglass"
        } else if titleLower.contains("siri") || titleLower.contains("voice") || bundleLower.contains("siri") {
            symbolName = "waveform"
        } else if titleLower.contains("textinput") || titleLower.contains("input") || bundleLower.contains("textinput") || bundleLower.contains("input") {
            symbolName = "character.cursor.ibeam"
        } else if titleLower.contains("warp") || titleLower.contains("terminal") || titleLower.contains("shell") || bundleLower.contains("terminal") || bundleLower.contains("shell") {
            symbolName = "terminal"
        } else if titleLower.contains("rectangle") || titleLower.contains("window manager") || bundleLower.contains("rectangle") {
            symbolName = "rectangle.on.rectangle"
        } else if titleLower.contains("launcher") || titleLower.contains("grid") || bundleLower.contains("launcher") || bundleLower.contains("grid") {
            symbolName = "square.grid.3x3"
        } else if titleLower.contains("dropbox") || ownerLower.contains("dropbox") || bundleLower.contains("dropbox") {
            symbolName = "shippingbox"
        } else if titleLower.contains("keyboard") || titleLower.contains("maestro") || titleLower.contains("macro") || bundleLower.contains("keyboard") || bundleLower.contains("input") {
            symbolName = "command"
        } else if titleLower.contains("clock") || titleLower.contains("time") || titleLower.contains("date") || bundleLower.contains("clock") || bundleLower.contains("time") {
            symbolName = "clock"
        } else if isControlCenter {
            symbolName = "switch.2"
        } else if bundleLower.contains("calendar") {
            symbolName = "calendar"
        } else if bundleLower.contains("home") {
            symbolName = "house"
        } else if bundleLower.contains("airplay") {
            symbolName = "airplayvideo"
        } else if bundleLower.contains("shortcuts") || bundleLower.contains("script") {
            symbolName = "square.on.square.on.text.badge.checkmark"
        } else if bundleLower.contains("accessibility") || bundleLower.contains("a11y") {
            symbolName = "person.crop.circle.badge.checkmark"
        } else if bundleLower.contains("character") || bundleLower.contains("emoji") {
            symbolName = "number"
        } else if bundleLower.contains("trackpad") || bundleLower.contains("mouse") {
            symbolName = "cursor.rays"
        } else if bundleLower.contains("dictation") {
            symbolName = "microphone"
        } else if bundleLower.contains("timemachine") || bundleLower.contains("time-machine") {
            symbolName = "timer"
        } else if bundleLower.contains("gamecenter") || bundleLower.contains("game-center") {
            symbolName = "gamecontroller"
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
