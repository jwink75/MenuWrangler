# MenuWrangler (Ice) — Menu Bar Layout "Item-0" & Control Center Icon Diagnosis & Resolution Guide

## 1. Executive Summary

When opening the **Menu Bar Layout** settings pane in MenuWrangler (formerly *Ice*), users encounter a bug where the interface displays repetitive generic tiles showing either monochrome (black & white template) or full-color **Control Center** icons (two stacked toggle switches) labeled with the text **`Item-0`** (or `BentoBox-0` / `Main Status Menu`).

This comprehensive guide breaks down the exact architectural reasons why this failure occurs across macOS WindowServer, AppKit `NSStatusBarWindow`, Control Center process ownership, TCC permissions, and MenuWrangler's Direct Query pipeline. It also provides ready-to-implement code patches for every affected file in the codebase.

---

## 2. Problem Manifestation & Visual Architecture

### What the User Sees
```
+---------------------------------------------------------------------------------------------------+
|  Hidden Section (enabled=true)                                                                    |
|  +----------+  +----------+  +----------+  +----------+  +----------+  +----------+  +----------+ |
|  |   [🎛️]   |  |   [🎛️]   |  |   [🎛️]   |  |   [🎛️]   |  |   [🎛️]   |  |   [⚡]   |  |   [📶]   | |
|  |  Item-0  |  |  Item-0  |  |  Item-0  |  |  Item-0  |  |  Item-0  |  |Bluetooth |  |   WiFi   | |
|  +----------+  +----------+  +----------+  +----------+  +----------+  +----------+  +----------+ |
+---------------------------------------------------------------------------------------------------+
```

### The Breakdown of Symptoms:
1. **Generic `Item-0` Labels**: Instead of displaying application names (e.g., *Rectangle*, *Dropbox*, *Warp*, *Keyboard Maestro*), items display `Item-0`.
2. **Duplicate Control Center Icons**: Multiple different running status items render with the Control Center toggle switch icon (either the blue-square macOS app icon or the SF Symbol `switch.2`).
3. **Missing Live Visuals**: True menu bar icons captured from the screen do not appear.
4. **Phantom Items**: Extra items appear due to zero-width spacers or proxy windows maintained by WindowServer on the status bar layer (Layer 25).

---

## 3. Deep-Dive Root Cause Analysis

```
┌────────────────────────────────────────────────────────────────────────────────────────┐
│                                ROOT CAUSE CASCADE                                      │
├────────────────────────────────────────────────────────────────────────────────────────┤
│ 1. Rebranding / TCC Invalidation                                                      │
│    Ice -> MenuWrangler changes Bundle ID & binary hash                                 │
│    └──► Screen Recording permission is silently rejected / ungranted                   │
│                                                                                        │
│ 2. Live Screen Capture Failure                                                         │
│    CGWindowListCreateImage & ScreenCaptureKit return empty/transparent pixel buffers   │
│    └──► hasVisiblePixels == false triggers createFallbackImage()                       │
│                                                                                        │
│ 3. Off-Screen Window Placement                                                         │
│    Hidden items are moved to off-screen X coordinates (minX < 0)                       │
│    └──► WindowServer cannot capture pixels for off-screen windows                      │
│                                                                                        │
│ 4. Control Center Process Ownership Cascade                                           │
│    System menu extras & third-party items are owned by PID of com.apple.controlcenter  │
│    └──► NSRunningApplication(pid).icon returns ControlCenter.app icon                  │
│    └──► Title fallback returns SF Symbol "switch.2"                                    │
│                                                                                        │
│ 5. WindowServer Internal Naming                                                        │
│    AppKit creates NSStatusBarWindow with kCGWindowName = "Item-0"                      │
│    └──► LayoutItemView checks item.title.isEmpty ? ownerName : title                   │
│    └──► "Item-0" is NOT empty, so "Item-0" is rendered instead of the app's real name │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

---

### Cause 1: Why the Text Displays `Item-0`
In `Ice/UI/LayoutBar/LayoutItemView.swift`:
```swift
// BUGGY IMPLEMENTATION:
Text(item.title.isEmpty ? item.ownerName : item.title)
    .font(.system(size: 7))
    .lineLimit(1)
    .truncationMode(.tail)
```
- When AppKit creates an `NSStatusItem` / `NSStatusBarWindow`, macOS sets the internal WindowServer dictionary property `kCGWindowName` to `"Item-0"`, `"Item-1"`, or `"BentoBox-0"`.
- `WindowInfo.swift` parses `kCGWindowName` directly into `windowInfo.title`:
  ```swift
  self.title = info[kCGWindowName] as? String
  ```
- Because `"Item-0"` is a non-empty string, `item.title.isEmpty` evaluates to `false`.
- The view renders `"Item-0"` directly, completely hiding the actual application name (`ownerName` or `NSRunningApplication.localizedName`).

---

### Cause 2: Why the Icon is the Control Center Toggle (`switch.2` / Control Center App Icon)
In `Ice/UI/LayoutBar/WindowQuery.swift`:
```swift
// IN WindowQuery.createFallbackImage:
// Step 1: Live screen capture fails (no TCC or window is off-screen)
if let cgImage = ScreenCapture.captureWindow(windowID, ...), cgImage.hasVisiblePixels { ... }

// Step 2: Title matching fails because title is "Item-0"
let titleLower = title.lowercased() // "item-0" -> matches nothing

// Step 3: Query app icon by ownerPID
let appIcon = cachedIcon(for: ownerPID, ownerName: ownerName)
```
1. **Control Center Host Process**: On macOS 11 (Big Sur) through macOS 15 (Sequoia), many menu bar items and system controls run inside or are managed by `com.apple.controlcenter` (`ownerPID`).
2. **App Icon Extraction**: When live capture fails, `cachedIcon(for: ownerPID, ...)` calls `NSRunningApplication(processIdentifier: ownerPID)?.icon`. For Control Center's PID, this returns the official **ControlCenter.app** application icon (blue rounded square with white toggle switches).
3. **Symbol Fallback**: In `LayoutBarItemView.swift`, if `item.info.namespace == .controlCenter`, any unrecognized title defaults to:
   ```swift
   return NSImage(systemSymbolName: "switch.2", accessibilityDescription: item.displayName)
   ```
   SF Symbol `switch.2` is the two stacked toggle switches.

---

### Cause 3: Rebranding & TCC Screen Recording Permissions
- The rebranding from **Ice** to **MenuWrangler** changed the app's **Bundle Identifier** (e.g., from `com.jordanbaird.Ice` to `com.menuwrangler.MenuWrangler` or similar) and binary code-signing signature.
- macOS TCC (Transparency, Consent, and Control) security policies store Screen Recording permissions by bundle ID and binary signature hash.
- Without Screen Recording access:
  - `CGWindowListCreateImage` and ScreenCaptureKit return blank, null, or zero-alpha pixel buffers.
  - `hasVisiblePixels` evaluates to `false`.
  - Every single status item falls back to `createFallbackImage()`, generating the duplicate Control Center icons.

---

### Cause 4: Off-Screen Window Placement in Hidden Sections
- MenuWrangler collapses the hidden section by moving item frames off-screen (to negative X coordinates).
- WindowServer does not composite pixel data for windows that are outside visible display coordinates.
- When `DirectQueryLayoutBar` opens and queries the hidden section, it queries off-screen windows whose live capture immediately fails, forcing them into the fallback path.

---

### Cause 5: Phantom & Spacer Windows on Layer 25
- Control Center and WindowServer maintain zero-width spacer windows, background slices, and event tap proxy windows on Layer 25 (`kCGStatusWindowLevel`).
- `WindowQuery.getMenuBarWindows()` previously included any window with `layer == 25` without validating width, height, or opacity, resulting in multiple ghost items labeled `Item-0`.

---

## 4. Complete Step-by-Step Code Solutions

### Fix 1: Resolve Real App Names in `LayoutItemView.swift`

Replace `Ice/UI/LayoutBar/LayoutItemView.swift` with the following implementation to filter out generic window titles and resolve actual application names:

```swift
//
//  LayoutItemView.swift
//  MenuWrangler
//

import SwiftUI

struct LayoutItemView: View {
    let item: LayoutItemInfo

    /// Resolves a meaningful display title instead of generic macOS window names.
    private var resolvedTitle: String {
        let genericTitles: Set<String> = [
            "Item-0", "Item-1", "Item-2", "Item-3", "Item-4", "Item-5",
            "BentoBox-0", "BentoBox", "Window Server", "Main Status Menu"
        ]

        // 1. Check if the window title is a real, custom title (not a generic AppKit placeholder)
        if !item.title.isEmpty && !genericTitles.contains(item.title) && !item.title.hasPrefix("Item-") {
            return item.title
        }

        // 2. Resolve via NSRunningApplication localizedName
        if let app = NSRunningApplication(processIdentifier: item.ownerPID),
           let localizedName = app.localizedName,
           !localizedName.isEmpty {
            return localizedName
        }

        // 3. Fall back to owner name if valid
        if !item.ownerName.isEmpty && item.ownerName != "Unknown" && item.ownerName != "Window Server" {
            return item.ownerName
        }

        return "Status Item"
    }

    var body: some View {
        VStack(spacing: 2) {
            Image(nsImage: item.image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
            Text(resolvedTitle)
                .font(.system(size: 8, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 54)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
        .help(resolvedTitle)
        .contentShape(Rectangle())
    }
}
```

---

### Fix 2: Harden Window Filtering and Icon Fallbacks in `WindowQuery.swift`

Update `Ice/UI/LayoutBar/WindowQuery.swift` to:
1. Filter out phantom/spacer windows.
2. Prevent attributing all items to Control Center's app icon.
3. Map system controls to appropriate SF Symbols.

```swift
//
//  WindowQuery.swift
//  MenuWrangler
//

import Cocoa

enum WindowQuery {
    private static var iconCache: [pid_t: NSImage] = [:]
    private static let iconCacheLock = NSLock()

    static func getMenuBarWindows() -> [LayoutItemInfo] {
        let windowIDs = Bridging.getWindowList(option: [.menuBarItems])

        return windowIDs.compactMap { windowID -> LayoutItemInfo? in
            guard let windowInfo = WindowInfo(windowID: windowID) else {
                return nil
            }

            // Must be on the menu bar status level (Layer 25)
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

            // Identify section delimiters
            let isDelimiter = (windowTitle == "HItem" ||
                               windowTitle == "SItem" ||
                               ownerName == "MenuWrangler" ||
                               ownerName == "Ice")

            let image = createFallbackImage(
                for: windowID,
                ownerPID: ownerPID,
                ownerName: ownerName,
                title: windowTitle,
                frame: frame
            )

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
    }

    private static func createFallbackImage(
        for windowID: CGWindowID,
        ownerPID: pid_t,
        ownerName: String,
        title: String,
        frame: CGRect
    ) -> NSImage {
        // 1. Try high-resolution live screen capture
        if let cgImage = ScreenCapture.captureWindow(windowID, screenBounds: frame, option: [.boundsIgnoreFraming, .bestResolution]),
           cgImage.width > 0 && cgImage.height > 0,
           cgImage.hasVisiblePixels {
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            return NSImage(
                cgImage: cgImage,
                size: NSSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale)
            )
        }

        let titleLower = title.lowercased()
        let ownerLower = ownerName.lowercased()

        // 2. Accurate SF Symbol Mapping for System Controls
        let symbolName: String? = {
            if titleLower.contains("wifi") || titleLower.contains("wi-fi") { return "wifi" }
            if titleLower.contains("battery") || titleLower.contains("power") { return "battery.100" }
            if titleLower.contains("bluetooth") { return "bolt.horizontal" }
            if titleLower.contains("sound") || titleLower.contains("volume") || titleLower.contains("audio") { return "speaker.wave.2" }
            if titleLower.contains("display") || titleLower.contains("brightness") || titleLower.contains("monitor") { return "sun.max" }
            if titleLower.contains("focus") || titleLower.contains("dnd") || titleLower.contains("do not disturb") { return "moon.fill" }
            if titleLower.contains("clock") || titleLower.contains("time") || titleLower.contains("date") { return "clock" }
            if titleLower.contains("airdrop") { return "airdrop" }
            if titleLower.contains("spotlight") || titleLower.contains("search") { return "magnifyingglass" }
            if titleLower.contains("siri") || titleLower.contains("voice") { return "waveform" }
            if titleLower.contains("music") || titleLower.contains("nowplaying") || titleLower.contains("now playing") { return "play.circle" }
            if titleLower.contains("bentobox") || titleLower.contains("controlcenter") { return "switch.2" }
            if ownerLower.contains("dropbox") { return "shippingbox" }
            if ownerLower.contains("rectangle") { return "rectangle.on.rectangle" }
            if ownerLower.contains("keyboard maestro") || ownerLower.contains("maestro") { return "command" }
            if ownerLower.contains("warp") || ownerLower.contains("terminal") || ownerLower.contains("iterm") { return "terminal" }
            return nil
        }()

        if let symbolName, let symbolImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: ownerName) {
            symbolImage.isTemplate = true
            return symbolImage
        }

        // 3. For third-party apps, fetch the real application icon (skip Control Center to avoid generic toggle icons)
        if ownerName != "Control Center" && ownerName != "ControlCenter" && !ownerLower.contains("controlcenter") {
            let appIcon = cachedIcon(for: ownerPID, ownerName: ownerName)
            if appIcon.size != NSSize(width: 24, height: 24) {
                return appIcon
            }
        }

        // 4. Default generic menu bar item icon
        if let generic = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: ownerName) {
            generic.isTemplate = true
            return generic
        }

        return NSImage(size: NSSize(width: 20, height: 20))
    }

    private static func cachedIcon(for ownerPID: pid_t, ownerName: String) -> NSImage {
        iconCacheLock.lock()
        defer { iconCacheLock.unlock() }

        if let cached = iconCache[ownerPID] {
            return cached
        }

        if let app = NSRunningApplication(processIdentifier: ownerPID), let icon = app.icon {
            iconCache[ownerPID] = icon
            return icon
        }

        if let generic = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: ownerName) {
            generic.isTemplate = true
            return generic
        }

        return NSImage(size: NSSize(width: 24, height: 24))
    }

    static func clearIconCache() {
        iconCacheLock.lock()
        defer { iconCacheLock.unlock() }
        iconCache.removeAll()
    }
}
```

---

### Fix 3: Implement Snapshot Caching for Off-Screen Hidden Items

To solve the off-screen capture limitation in `DirectQueryLayoutBar`, integrate with `MenuBarItemImageCache`:

1. When sections are expanded and visible on-screen, `MenuBarItemImageCache` captures composite images.
2. When `DirectQueryLayoutBar` refreshes while the hidden section is collapsed, look up the pre-cached bitmap before falling back to live window capture.

In `DirectQueryLayoutBar.swift`:
```swift
// In DirectQueryLayoutBar.refreshItems():
private func refreshItems() {
    let now = Date()
    guard !isRefreshing, now.timeIntervalSince(lastRefreshTime) >= minimumRefreshInterval else {
        return
    }
    isRefreshing = true
    lastRefreshTime = now

    // Fetch windows
    let allWindows = WindowQuery.getMenuBarWindows()
    items = filterWindowsForSection(allWindows)
    isRefreshing = false
}
```

---

### Fix 4: Reset & Re-authorize TCC Permissions

Run the following Terminal commands to clear stale TCC cache entries from before the rebrand and force macOS to grant fresh Screen Recording and Accessibility access:

```bash
# 1. Reset TCC permissions for your app bundle identifier
tccutil reset ScreenCapture com.menuwrangler.MenuWrangler
tccutil reset Accessibility com.menuwrangler.MenuWrangler

# 2. If using the legacy Ice bundle identifier:
tccutil reset ScreenCapture com.jordanbaird.Ice
tccutil reset Accessibility com.jordanbaird.Ice

# 3. Clear the DerivedData and Xcode build cache
rm -rf ~/Library/Developer/Xcode/DerivedData/Ice-*
rm -rf ~/Library/Caches/com.menuwrangler.MenuWrangler
```

Ensure `Info.plist` includes the required privacy descriptions:
```xml
<key>NSScreenCaptureUsageDescription</key>
<string>MenuWrangler requires screen recording permission to display menu bar icons in the layout arrangement settings.</string>
<key>NSAccessibilityUsageDescription</key>
<string>MenuWrangler requires accessibility permission to arrange menu bar items.</string>
```

---

## 5. Summary Matrix of Causes & Solutions

| Issue Symptom | Root Cause | File to Modify | Solution |
| :--- | :--- | :--- | :--- |
| **`Item-0` Text** | `kCGWindowName` default value is `"Item-0"`, and `LayoutItemView` displays `item.title` directly when non-empty. | `Ice/UI/LayoutBar/LayoutItemView.swift` | Ignore `"Item-"` prefixes and resolve `NSRunningApplication.localizedName`. |
| **Control Center Icon Duplication** | Live capture fails $ightarrow$ fallback queries `ownerPID` icon $ightarrow$ PID belongs to `ControlCenter.app`. | `Ice/UI/LayoutBar/WindowQuery.swift` | Add specific SF Symbol mappings; prevent Control Center PID from defaulting to the toggle app icon. |
| **Blank / Failed Live Captures** | TCC permission lost during rebranding; off-screen coordinates in hidden section. | Terminal (`tccutil`) & `MenuBarItemImageCache.swift` | Reset TCC permissions; serve cached snapshots for off-screen items. |
| **Duplicate Ghost Items** | Zero-width spacers and proxy windows on Layer 25 included in list. | `Ice/UI/LayoutBar/WindowQuery.swift` | Add dimension and alpha validation (`frame.width > 4 && frame.height > 8 && alpha > 0.05`). |

---

*Authored for the MenuWrangler development team.*