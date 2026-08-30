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

            guard let cgImage = CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, .boundsIgnoreFraming) else {
                return nil
            }

            let ownerName = info[kCGWindowOwnerName as String] as? String ?? "Unknown"

            return LayoutItemInfo(
                windowID: windowID,
                image: NSImage(cgImage: cgImage, size: .zero),
                ownerPID: ownerPID,
                ownerName: ownerName,
                frame: CGRect(
                    x: bounds["X"] ?? 0,
                    y: bounds["Y"] ?? 0,
                    width: bounds["Width"] ?? 0,
                    height: bounds["Height"] ?? 0
                )
            )
        }
    }
}
