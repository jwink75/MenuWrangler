# DirectQueryLayoutBar Architecture & Gap Analysis

## Overview
`DirectQueryLayoutBar` was introduced to bypass legacy caching layers by querying WindowServer directly for status bar items (layer 25).

---

## 1. Visual Comparison (Physical Menu Bar vs. Dialog)

### Physical Menu Bar (14 Items Left-to-Right):
1. Warp / Shell (`^`)
2. Window Manager / Rectangle (`◧`)
3. App Launcher Grid (`⠿`)
4. Dropbox (`📦`)
5. Keyboard Maestro (`⌘`)
6. Macro / script runner (`⌘` in window)
7. Display Brightness / Monitor (`🖥️`)
8. Media Player (`▶️`)
9. Bluetooth (`ᛒ`)
10. Wi-Fi (`📶`)
11. Battery (`⚡🔋`)
12. MenuWrangler Delimiter (`...`)
13. Control Center (`switch.2`)
14. Date & Time / Clock (`Sun Aug 30 12:18 AM`)

### Current Dialog Output:
- Displays only **4 items** instead of 14.
- Displays the **identical 4 items in both Visible and Hidden sections**.

---

## 2. Root Causes

1. **`WindowQuery.swift` guard discard**:
   `guard let cgImage = CGWindowListCreateImage(...) else { return nil }` throws away all windows where a live image buffer is not immediately returned, dropping 10 out of 14 items.
2. **`DirectQueryLayoutBar.swift` filtering**:
   `filterWindowsForSection` only filters out MenuWrangler/Ice, without checking `section.name` (`.visible` vs `.hidden`).
3. **Missing spatial delimiter split**:
   Items are not split based on whether `item.frame.origin.x` is to the left or right of the delimiter (`...`).

---

## 3. Recommended Code Updates for Kilo Code

### 1. `WindowQuery.swift`: Resilient Icon Resolution
```swift
let image: NSImage = {
    if let cgImage = CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, .boundsIgnoreFraming) {
        return NSImage(cgImage: cgImage, size: .zero)
    }
    if let app = NSRunningApplication(processIdentifier: ownerPID), let icon = app.icon {
        return icon
    }
    return NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: ownerName) ?? NSImage()
}()
```

### 2. `DirectQueryLayoutBar.swift`: Spatial Section Partitioning
```swift
private func filterWindowsForSection(_ windows: [LayoutItemInfo]) -> [LayoutItemInfo] {
    let sorted = windows.sorted(by: { $0.frame.origin.x < $1.frame.origin.x })
    let delimiterX = sorted.first(where: { $0.ownerName == "MenuWrangler" || $0.ownerName == "Ice" })?.frame.origin.x ?? (NSScreen.main?.frame.width ?? 1200) * 0.75

    let nonSelf = sorted.filter { $0.ownerName != "MenuWrangler" && $0.ownerName != "Ice" }

    switch section.name {
    case .visible:
        return nonSelf.filter { $0.frame.origin.x >= delimiterX }
    case .hidden:
        return nonSelf.filter { $0.frame.origin.x < delimiterX }
    case .alwaysHidden:
        return []
    }
}
```
