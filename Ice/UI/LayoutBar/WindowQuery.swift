//
//  WindowQuery.swift
//  Ice
//

import Cocoa

enum WindowQuery {
    static func getMenuBarWindows() -> [LayoutItemInfo] {
        guard let windowList = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return windowList.compactMap { info in
            guard
                let layer = info[kCGWindowLayer as String] as? Int,
                layer == 25,
                let windowNumber = info[kCGWindowNumber as String] as? Int,
                let windowID = CGWindowID(exactly: windowNumber),
                let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t
            else {
                return nil
            }

            let ownerName = info[kCGWindowOwnerName as String] as? String ?? "Unknown"
            let windowTitle = info[kCGWindowName as String] as? String ?? ""

            let frame = CGRect(
                x: bounds["X"] ?? 0,
                y: bounds["Y"] ?? 0,
                width: bounds["Width"] ?? 0,
                height: bounds["Height"] ?? 0
            )

            let image = createFallbackImage(for: windowID, ownerPID: ownerPID, ownerName: ownerName, title: windowTitle, frame: frame)

            return LayoutItemInfo(
                windowID: windowID,
                image: image,
                ownerPID: ownerPID,
                ownerName: ownerName,
                frame: frame,
                title: windowTitle
            )
        }
    }

    private static func createFallbackImage(for windowID: CGWindowID, ownerPID: pid_t, ownerName: String, title: String, frame: CGRect) -> NSImage {
        if let cgImage = ScreenCapture.captureWindow(windowID, screenBounds: frame, option: .boundsIgnoreFraming),
           cgImage.width > 0 && cgImage.height > 0,
           cgImage.hasVisiblePixels {
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            let img = NSImage(cgImage: cgImage, size: NSSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale))
            return img
        }

        if let cgImage = CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, .boundsIgnoreFraming),
           cgImage.width > 0 && cgImage.height > 0,
           cgImage.hasVisiblePixels {
            let scale = NSScreen.main?.backingScaleFactor ?? 2
            let img = NSImage(cgImage: cgImage, size: NSSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale))
            return img
        }

        let titleLower = title.lowercased()
        let ownerLower = ownerName.lowercased()

        let symbolName: String?
        if titleLower.contains("warp") || titleLower.contains("terminal") || titleLower.contains("shell") {
            symbolName = "terminal"
        } else if titleLower.contains("rectangle") || titleLower.contains("window") {
            symbolName = "rectangle.on.rectangle"
        } else if titleLower.contains("launcher") || titleLower.contains("grid") {
            symbolName = "square.grid.3x3"
        } else if titleLower.contains("dropbox") || ownerLower.contains("dropbox") {
            symbolName = "shippingbox"
        } else if titleLower.contains("keyboard") || titleLower.contains("maestro") || titleLower.contains("macro") {
            symbolName = "command"
        } else if titleLower.contains("display") || titleLower.contains("monitor") {
            symbolName = "display"
        } else if titleLower.contains("media") || titleLower.contains("music") || titleLower.contains("play") {
            symbolName = "play.circle"
        } else if titleLower.contains("bluetooth") || ownerLower.contains("bluetooth") {
            symbolName = "bolt"
        } else if titleLower.contains("wifi") || titleLower.contains("wi-fi") {
            symbolName = "wifi"
        } else if titleLower.contains("battery") || titleLower.contains("power") {
            symbolName = "battery.100"
        } else if titleLower.contains("control") || titleLower.contains("center") {
            symbolName = "switch.2"
        } else if titleLower.contains("clock") || titleLower.contains("time") || titleLower.contains("date") {
            symbolName = "clock"
        } else if titleLower.contains("speaker") || titleLower.contains("volume") || titleLower.contains("sound") {
            symbolName = "speaker.wave.2"
        } else {
            symbolName = nil
        }

        if let symbolName, let symbolImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: ownerName) {
            symbolImage.isTemplate = true
            return symbolImage
        }

        if let app = NSRunningApplication(processIdentifier: ownerPID), let icon = app.icon {
            return icon
        }

        if let generic = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: ownerName) {
            generic.isTemplate = true
            return generic
        }

        return NSImage(size: NSSize(width: 24, height: 24))
    }
}
