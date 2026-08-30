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

## 2. Root Causes Identified

### Issue 1: Window Discovery Method
**Problem**: Initial implementation used `CGWindowListCopyWindowInfo` which was unreliable for menu bar items.
- Windows at layer 25 were found, but the filtering was inconsistent
- Results varied between calls, causing items to appear/disappear

**Solution**: Switched to `Bridging.getWindowList(option: [.menuBarItems])` which uses `CGSGetProcessMenuBarWindowList` - the same approach as the original Ice code. This is more reliable and returns consistent results.

### Issue 2: Y Coordinate Direction
**Problem**: Initial code assumed Y coordinate was measured from the bottom of the screen.
```swift
// WRONG - Y is from the TOP for menu bar items
let isAtMenuBar = windowY >= (screenHeight - menuBarHeight * 3)
```

**Solution**: Y coordinate is measured from the TOP for menu bar windows:
```swift
// CORRECT - Menu bar is at top, so Y should be small
let isAtMenuBar = windowY <= menuBarHeight * 3
```

### Issue 3: Delimiter Detection
**Problem**: Initial code looked for delimiter by owner name (`ownerName == "MenuWrangler"`), but on macOS all menu bar items show as "Control Center" owner.

**Solution**: Identify delimiter by window title instead:
```swift
// "HItem" is the MenuWrangler hidden section delimiter
let isDelimiter = (windowTitle == "HItem" || ownerName == "MenuWrangler" || ownerName == "Ice")
```

### Issue 4: Icon Capture Failures
**Problem**: Screen capture fails for off-screen items (negative X coordinates), causing fallback to generic icons.

**Current Status**: 
- Screen capture works for visible items (positive X)
- Hidden items (negative X) fall back to SF Symbols or generic icons
- "Item-0" items are generic Control Center items with no specific title

---

## 3. Current Implementation

### WindowQuery.swift
```swift
static func getMenuBarWindows() -> [LayoutItemInfo] {
    // Use Bridging.getWindowList - same as original Ice code
    let windowIDs = Bridging.getWindowList(option: [.menuBarItems])
    
    return windowIDs.compactMap { windowID -> LayoutItemInfo? in
        guard let windowInfo = WindowInfo(windowID: windowID),
              windowInfo.isMenuBarItem else { return nil }
        
        // Identify delimiter by title
        let isDelimiter = (windowInfo.title == "HItem" || 
                           windowInfo.ownerName == "MenuWrangler" || 
                           windowInfo.ownerName == "Ice")
        
        let image = createFallbackImage(for: windowID, ...)
        
        return LayoutItemInfo(
            windowID: windowID,
            image: image,
            ownerPID: windowInfo.ownerPID,
            ownerName: windowInfo.ownerName ?? "Unknown",
            frame: windowInfo.frame,
            title: windowInfo.title ?? "",
            isDelimiter: isDelimiter
        )
    }
}
```

### DirectQueryLayoutBar.swift - Filtering
```swift
private func filterWindowsForSection(_ windows: [LayoutItemInfo]) -> [LayoutItemInfo] {
    let sortedWindows = windows.sorted { $0.frame.origin.x < $1.frame.origin.x }
    let delimiter = sortedWindows.first { $0.isDelimiter }
    let delimiterX = delimiter?.frame.origin.x ?? 0

    switch section.name {
    case .visible:
        return sortedWindows.filter { $0.frame.origin.x >= delimiterX && !$0.isDelimiter }
    case .hidden:
        return sortedWindows.filter { $0.frame.origin.x < delimiterX && !$0.isDelimiter }
    case .alwaysHidden:
        return []
    }
}
```

### Debug Info Available
The following UserDefaults keys are populated for debugging:
- `WindowQuery_totalWindows` - Total menu bar windows found
- `WindowQuery_windowsAtLayer25` - Windows at layer 25
- `WindowQuery_allOwners` - Unique owner names
- `WindowQuery_allTitles` - Unique window titles
- `LayoutBar_delimiterX_Visible/Hidden` - Delimiter X position
- `LayoutBar_resultCount_Visible/Hidden` - Items in each section
- `LayoutBar_resultItems_Visible/Hidden` - Detailed item info

---

## 4. Remaining Issues

### Issue: "Item-0" Generic Items
**Symptom**: Many items show as "Item-0" with generic icons.
**Cause**: These are Control Center items with generic titles. They don't have a specific app or title that matches SF Symbol lookup.
**Status**: This is expected behavior for generic Control Center items. The original Ice code uses `displayName` property which has special handling for known titles.

### Issue: Icon Capture for Hidden Items
**Symptom**: Hidden items (negative X coordinates) show generic icons.
**Cause**: Screen capture fails for off-screen windows.
**Status**: Expected limitation. SF Symbols are used as fallback for known titles (WiFi, Battery, Bluetooth, Clock).

### Issue: Drag and Drop
**Symptom**: Items are not draggable.
**Status**: Not yet implemented. The `onDrag` and `onDrop` modifiers are in place but may need refinement.

### Issue: Tooltips
**Symptom**: Tooltips don't appear.
**Status**: The `.help()` modifier is applied but may not work due to view hierarchy issues.

---

## 5. Tried Solutions

| Approach | Result |
|----------|--------|
| `CGWindowListCopyWindowInfo` with layer 25 filter | Unreliable, inconsistent results |
| Y coordinate from bottom | Failed - filtered out all items |
| Y coordinate from top | **Fixed** - correctly identifies menu bar items |
| Delimiter by owner name | Failed - all items show as "Control Center" |
| Delimiter by title "HItem" | **Fixed** - correctly identifies delimiter |
| `Bridging.getWindowList(option: [.menuBarItems])` | **Fixed** - reliable window discovery |
| Cached app icon for Control Center items | Caused all items to show same icon |
| SF Symbols based on title | **Partial** - works for known titles |

---

## 6. Recommended Next Steps

1. **Improve Icon Display**: Use the `MenuBarItem.displayName` approach from original code for better item names
2. **Fix Drag and Drop**: Debug the `onDrag`/`onDrop` implementation
3. **Fix Tooltips**: Ensure `.help()` modifier works correctly
4. **Consider Caching**: Cache icons to avoid repeated screen capture attempts

---

## 7. Key Learnings

1. **macOS Menu Bar Items**: All menu bar items report "Control Center" as owner name. Identification must be done by window title.
2. **Y Coordinate**: Menu bar window Y coordinates are measured from the TOP of the screen, not the bottom.
3. **Window Discovery**: `CGSGetProcessMenuBarWindowList` (via `Bridging.getWindowList`) is more reliable than `CGWindowListCopyWindowInfo` for menu bar items.
4. **Delimiter**: The MenuWrangler delimiter has window title "HItem" and is used to separate visible/hidden sections.
5. **Screen Capture**: Only works for on-screen items (positive X). Off-screen items need fallback icons.
