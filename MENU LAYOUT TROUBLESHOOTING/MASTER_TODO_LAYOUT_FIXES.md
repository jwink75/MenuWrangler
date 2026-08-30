# Master To-Do List: Menu Bar Layout Architecture & Visual Fixes

**Consolidated from:**
1. `MenuWrangler_MenuBarLayout_Diagnosis.md`
2. `MenuWrangler_LayoutBar_Comprehensive_Guide.md`
3. `MenuWrangler_Menu_Bar_Layout_Diagnostic_Report.md`

---

## 1. Executive Summary & Diagnostic Matrix

When opening the **Menu Bar Layout** settings pane, items previously rendered with duplicate Control Center switch icons (`switch.2`), placeholder labels like `Item-0`, and phantom zero-width spacers. 

The investigation across the three diagnostic reports identified the following core root causes:

| Failure Point | Root Cause | Architectural Solution |
|---|---|---|
| **1. Generic `Item-0` Labels** | AppKit/WindowServer assigns `kCGWindowName = "Item-0"` to status windows. The UI displayed `item.title` verbatim without filtering placeholder strings. | Filter placeholder patterns (`Item-*`, `BentoBox-*`, `Main Status Menu`). Resolve actual application name using `NSRunningApplication(ownerPID).localizedName` or `ownerName`. |
| **2. Duplicate Control Center Icons** | Multiple status items run inside `com.apple.controlcenter` (`ownerPID`). `WindowQuery` fell back to `NSRunningApplication.icon` and cached it per-PID (`[pid_t: NSImage]`), assigning Control Center's app icon to every item sharing that PID. | Eliminate per-PID icon caching. Cache per `windowID`. Distinguish Control Center sub-items by title/type mapping to distinct SF Symbols. Reserve app-icon fallback for non-ControlCenter apps. |
| **3. Ghost / Phantom Items** | WindowServer creates zero-width spacer and proxy windows on Layer 25 (`kCGStatusWindowLevel`). | Filter out windows where `width <= 4`, `height <= 8`, or `alpha <= 0.05`. |
| **4. Off-Screen Hidden Items** | Items in the hidden section have negative/off-screen X coordinates. `CGWindowListCreateImage` returns transparent pixels (`hasVisiblePixels == false`). | Validate pixel opacity via `hasVisiblePixels`. For transparent/off-screen windows, fall back immediately to resolved app icons or SF symbols. |
| **5. Delimiter in Layout View** | MenuWrangler's own delimiter item (`...` / `SItem`) appeared inside the draggable section items. | Explicitly exclude MenuWrangler PID / delimiter window IDs from the section item lists. |
| **6. Drag & Drop Reordering** | Items were rendered in a static `ScrollView`/`HStack` without reordering capabilities. | Implement SwiftUI `.onDrag` and `.onDrop` calling `Bridging.setMenuBarItemPosition`. |

---

## 2. Structured Implementation To-Do List

### Phase 1: Robust Application Name Resolution (`LayoutItemView.swift` & `LayoutItemInfo.swift`)
- [ ] **Task 1.1**: Define a set of generic placeholder titles to reject (`Item-0` through `Item-9`, `Item-`, `BentoBox`, `BentoBox-0`, `Window Server`, `Main Status Menu`).
- [ ] **Task 1.2**: Implement `resolvedTitle` in `LayoutItemView.swift`:
  1. If `title` is non-empty and not a generic placeholder, use `title`.
  2. If `NSRunningApplication(processIdentifier: ownerPID)?.localizedName` is available, use `localizedName`.
  3. If `ownerName` is valid (not `"Unknown"` / `"Window Server"`), use `ownerName`.
  4. Default to `"Status Item"`.
- [ ] **Task 1.3**: Update `LayoutItemView` UI to display the icon with a clean, readable text label below it and hover tooltip.

### Phase 2: Phantom Window Pruning & Distinct Icon Resolution (`WindowQuery.swift`)
- [ ] **Task 2.1**: Prune ghost windows: enforce `frame.width > 4`, `frame.height > 8`, and `alpha > 0.05`.
- [ ] **Task 2.2**: Remove `[pid_t: NSImage]` global icon cache. Use `[CGWindowID: NSImage]` or per-item caching.
- [ ] **Task 2.3**: Differentiate Control Center sub-items (`ownerName == "ControlCenter"` or bundle ID `com.apple.controlcenter`):
  - Map specific sub-modules by keyword to appropriate SF Symbols (`wifi`, `battery.100`, `bolt`, `speaker.wave.2`, `display`, `play.circle`, `moon.fill`, `airdrop`, etc.).
  - Never assign Control Center's app icon to third-party or generic items.
- [ ] **Task 2.4**: For non-ControlCenter third-party items (Dropbox, Rectangle, Warp, Keyboard Maestro, etc.), resolve their real app icon from `NSRunningApplication(ownerPID)?.icon` when screen capture is transparent.
- [ ] **Task 2.5**: Set `.isTemplate = true` on SF Symbols and menu bar glyphs for clean native monochrome rendering.

### Phase 3: Delimiter-Based Spatial Partitioning (`DirectQueryLayoutBar.swift`)
- [ ] **Task 3.1**: Find the MenuWrangler delimiter window using `ownerPID == currentPID` or `ownerName == "MenuWrangler"`.
- [ ] **Task 3.2**: Filter out MenuWrangler's delimiter from the returned item array.
- [ ] **Task 3.3**: Partition items into Visible (`origin.x >= delimiterX`) and Hidden (`origin.x < delimiterX`) sections.

### Phase 4: Drag & Drop Reordering (`LayoutItemView.swift` & `DirectQueryLayoutBar.swift`)
- [ ] **Task 4.1**: Implement `.onDrag` provider on `LayoutItemView` carrying the `windowID` and source section name.
- [ ] **Task 4.2**: Implement `.onDrop` on `DirectQueryLayoutBar` to reorder items and reposition them across sections using `Bridging.setMenuBarItemPosition`.

### Phase 5: Verification, Deep Signing, & Deployment
- [ ] **Task 5.1**: Build with Xcode, deep code sign with Apple Development identity (`5K6TS92SYQ`), and strip quarantine attributes via `./scripts/build.sh`.
- [ ] **Task 5.2**: Test settings pane UI to verify distinct icons, accurate application names, and drag-and-drop movement.
