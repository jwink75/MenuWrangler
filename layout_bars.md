# Menu Bar Layout Bars: Problem & Cause Analysis

This document details the issues observed with the Menu Bar Layout configuration bars (Visible Section and Hidden Section) in Ice / MenuWrangler when compiling and running on modern macOS versions (macOS 14 Sonoma, macOS 15 Sequoia, and newer).

---

## 1. Solid White Rectangle in Layout Bars

### Problem Description
When opening the Menu Bar Layout settings pane, the layout bar containers rendered as solid, opaque white rectangular blocks rather than translucent material with blurred backgrounds matching the desktop/menu bar average color.

### Cause
- **Zero-Alpha Division Producing `NaN`**: The layout bar background style computes an average color from a screen capture of the menu bar backdrop via `averageColor(makeOpaque:)` in `Extensions.swift`.
- When modern macOS returns a blank or fully transparent pixel buffer `(R: 0, G: 0, B: 0, A: 0)`, the total accumulated alpha is `0`.
- The average color calculation performed `totalRed / totalAlpha` (division by zero), yielding `NaN` (Not a Number) for the color components `(NaN, NaN, NaN, 1.0)`.
- CoreAnimation and AppKit compositing pipelines clamp `NaN` color values to maximum luminance `(1.0, 1.0, 1.0, 1.0)`, rendering the background as an opaque solid white rectangle.

---

## 2. Empty Layout Bars (Zero Items Displayed)

### Problem Description
The layout bar containers render their dark translucent background and section labels ("Visible Section", "Hidden Section"), but contain zero menu bar icons. No status items (system controls, Control Center items, or third-party menu bar extras) appear inside the bars.

### Cause
This symptom is the result of multiple compounding factors in upstream Ice's window discovery and caching pipeline:

### A. Window Title Anonymization on Modern macOS
- In upstream Ice, `MenuBarItem.getMenuBarItems(activeSpaceOnly: true)` filters discovered status bar windows based on window titles.
- On modern macOS releases, WindowServer anonymizes and strips window titles for third-party status items and Control Center items, returning empty strings (`""`) to non-system processes.
- Status items with empty titles are discarded by upstream Ice's title validation logic.

### B. Fragile Delimiter Identification & Destructive Cache Wiping
- Upstream Ice categorizes items into "Visible", "Hidden", and "Always Hidden" sections by locating delimiter items (`ControlItem.Identifier.hidden` / `"HItem"` and `alwaysHidden` / `"AItem"`).
- In `MenuBarItemManager.swift` (`cacheItemsIfNeeded()`), Ice searches the enumerated items for `.hiddenControlItem` matching `{namespace: "com.jordanbaird.Ice", title: "HItem"}`.
- When title anonymization causes the lookup to fail, `hiddenControlItem` evaluates to `nil`.
- Upstream Ice explicitly responds by executing `itemCache.clear()` and returning immediately, purging all previously cached items and leaving the section item arrays completely empty.

### C. Transient Window Server Observation Drops
- If a single WindowServer polling pass occurs during a space change, menu animation, or transient window reordering, `Bridging.getWindowList` may temporarily omit a delimiter window ID.
- Upstream Ice treats any transient missing delimiter as a hard failure, immediately wiping the entire cache rather than retaining the last known valid state.

---

## 3. Delimiter Frame Collapsing & Geometric Partitioning Failures

### Problem Description
Even when status items are discovered, all items end up clustered into a single section (e.g., all marked Visible), leaving other sections completely empty.

### Cause
- **Clean `UserDefaults` State**: AppKit stores the persistent screen position of `NSStatusItem` instances in `UserDefaults.standard` under keys like `NSStatusItem Preferred Position HItem`.
- On fresh installations, clean profiles, or when running under a new bundle identifier/test environment, no historical coordinates exist in `UserDefaults`.
- **Zero-Width Initial Geometry**: Upstream delimiter status items are initialized with `statusItem.length = 0`. In a fresh defaults state, the window server assigns the delimiter an initial frame of `(X: 0, Y: 0, Width: 0, Height: 0)` with `midX = 0`.
- **Geometric Predicate Failure**: The section partitioning predicate in `Predicates.swift` determines whether an item belongs to the visible section by testing `item.frame.midX >= hiddenControlItem.frame.midX`.
- When `hiddenControlItem.frame.midX` is `0`, all menu bar items located at `X > 0` evaluate to `true` for the Visible section, leaving `0` items for the Hidden section.

---

## 4. UI View Hierarchy Bypass via `imageCache.cacheFailed`

### Problem Description
The SwiftUI layout bar view hierarchy completely ignores the underlying NSView item arrangement and displays nothing.

### Cause
- In `LayoutBar.swift`, the SwiftUI view contains conditional rendering logic:
  ```swift
  if imageCache.cacheFailed(for: section.name) {
      Text("Unable to display menu bar items")
  } else {
      Representable(...)
  }
  ```
- `MenuBarItemImageCache.cacheFailed(for:)` returns `true` if `items` is non-empty but the `images` dictionary has no captured screenshots matching `item.info`.
- When modern macOS screen recording protections return blank captures or when the image cache has not yet populated, `cacheFailed` evaluates to `true`.
- As a result, SwiftUI never mounts the `Representable` (`LayoutBarScrollView` / `LayoutBarContainer`) view hierarchy at all, suppressing the display of all items.

---

## 5. Auto Layout Dimension Collapse in `NSViewRepresentable`

### Problem Description
When the `Representable` view is mounted, the internal item container collapses to zero width and height inside the scroll view.

### Cause
- **Missing Vertical Boundary Constraints**: In `LayoutBarPaddingView.swift`, the inner `container` had only a `centerYAnchor` constraint and leading/trailing horizontal constraints, but lacked top and bottom anchor constraints to establish intrinsic vertical height.
- **Initial Zero-Dimension Constraints**: In `LayoutBarContainer.swift`, `widthConstraint` and `heightConstraint` were initialized with constant `0`. When `arrangedViews` had not yet completed their initial layout pass or had `maxHeight = 0`, the container's height constraint remained locked at `0`, causing the scroll view's clip view to collapse the entire arranged item area.

---

## 6. Discrepancy Between Jordan's Pre-built Binary and Source Builds

### Problem Description
The pre-compiled binary release distributed on Jordan Baird's GitHub / Homebrew appeared to work on older setups, whereas compiling the exact same source code locally from scratch on a modern Mac triggers these layout failures.

### Cause

### A. macOS SDK Runtime Compatibility Shims
- When Apple introduces privacy restrictions and API deprecations in new macOS versions, the OS kernel and WindowServer check the **SDK version** that the application was linked against.
- Jordan's pre-built binary was compiled with an older macOS SDK (e.g., macOS 14 Sonoma). macOS applies backward-compatibility shims that allow older binaries legacy access to private window server APIs (`CGSGetProcessMenuBarWindowList`, `CGWindowListCreateImage`).
- Compiling locally with modern Xcode links against the **macOS 15 / 26 SDK**. macOS immediately enforces all strict runtime protections (title anonymization, window-level isolation, transparent pixel buffer returns on screen captures).

### B. Pre-existing Preferences in Local Domains
- Jordan's distributed binary benefited from pre-existing `NSStatusItem Preferred Position` coordinates saved in `com.jordanbaird.Ice`'s `UserDefaults` domain from prior launches, preventing the zero-width frame collapse.

### C. Build Configuration & Hardened Runtime
- The official release was built under the `Release` configuration with compiler optimizations, Apple Notarization tickets, and production Developer ID Application signatures.
- Local Xcode builds run under the `Debug` configuration with injected preview dylibs (`Ice.debug.dylib`, `__preview.dylib`) and development code signatures, which are subject to different TCC evaluation and sandbox inspection by macOS Gatekeeper.

---

## 7. Gatekeeper "Damaged App" False Positives

### Problem Description
When moving or opening the compiled app bundle, macOS Gatekeeper presents an alert stating: *“Ice” is damaged and can’t be opened. You should move it to the Trash.*

### Cause
- **Embedded Framework Signature Mismatches**: The upstream Ice repository includes pre-built sub-binaries inside `Sparkle.framework` (`Autoupdate`, `Updater.app`, `Installer.xpc`, `Downloader.xpc`). When the main application is re-signed with a local Apple Development certificate, the inner binaries retain their original upstream signature, breaking the bundle's cryptographic seal.
- **Sync Client File Collisions**: When building or copying bundles inside folders managed by cloud sync services (such as Dropbox), the sync engine can create duplicate conflict files (e.g., `Ice (conflicted copy).dylib`, `Info (conflicted copy).plist`) inside the `.app` bundle structure. Extra unsealed files invalidate the code signature seal, causing Gatekeeper to mark the application as damaged.

---

# Proposed Fixes

## Fix 1: Solid White Rectangle (NaN Color)

**File:** `Extensions.swift` — `averageColor(makeOpaque:)`

Guard against the zero-alpha division that produces `NaN`:

- Check `totalAlpha == 0` before performing the division. If alpha is zero, return a fallback color (e.g., a neutral gray or the system menu bar background color) instead of dividing.
- As a safety net, clamp any `NaN` color components to valid ranges `(0.0...1.0)` before returning, so the compositing pipeline cannot produce white from invalid input.

```swift
// Example approach:
guard totalAlpha > 0 else {
    return CGColor(gray: 0.5, alpha: 1.0) // fallback
}
```

---

## Fix 2: Empty Layout Bars (Title Anonymization + Destructive Cache Wiping)

### 2A. Title-Independent Delimiter Lookup

**File:** `MenuBarItemManager.swift` — `cacheItemsIfNeeded()`

Match delimiter status items (`hiddenControlItem`, `alwaysHiddenControlItem`) by `bundleIdentifier == "com.jordanbaird.Ice"` and namespace rather than by title. Fall back to matching by PID (the app's own process) as a secondary check when title comparison is unreliable.

### 2B. Non-Destructive Cache Handling

When a delimiter is temporarily missing, do not call `itemCache.clear()` and return immediately. Instead:

- Retain the last known valid cache.
- Retry on the next polling cycle.
- Only clear the cache after N consecutive failed attempts (e.g., N = 5).

### 2C. Relax Title Filtering

Do not discard menu bar items with empty titles. Include them in the enumeration and rely on position and namespace for categorization instead of requiring a non-empty title string.

---

## Fix 3: Delimiter Frame Collapsing & Geometric Partitioning

**Files:** `Predicates.swift`, `ControlItem.swift`, `MenuBarItemManager.swift`

- **Synthetic divider fallback:** In `Predicates.swift`, when `hiddenControlItem.frame.midX == 0`, use a percentage-based position (e.g., 75% of the screen width) as a synthetic divider boundary instead of the zero coordinate.
- **Non-zero initial length:** Initialize `NSStatusItem` delimiters with a small non-zero length (e.g., `statusItem.length = 1`) so WindowServer assigns a valid frame immediately, even in fresh `UserDefaults` state.
- **Persist delimiter positions:** After each successful layout pass, persist the delimiter coordinates to `UserDefaults` under stable keys so they survive app relaunch and are available on subsequent runs.

---

## Fix 4: UI View Hierarchy Bypass via `imageCache.cacheFailed`

**Files:** `LayoutBar.swift`, `MenuBarItemImageCache.swift`

- Always mount the `Representable` view hierarchy regardless of `cacheFailed` state. Replace the current `if/else` conditional with a placeholder/loading overlay that shows while images are being captured.
- Change `cacheFailed(for:)` to return `false` until a timeout or expiry period has elapsed, so the initial state allows the view to populate asynchronously.
- Populate item images asynchronously after the view is already visible, updating the display as captures complete.

---

## Fix 5: Auto Layout Dimension Collapse

**Files:** `LayoutBarPaddingView.swift`, `LayoutBarContainer.swift`

- **Add vertical boundary constraints:** In `LayoutBarPaddingView.swift`, add explicit `topAnchor` and `bottomAnchor` constraints between the container and the padding view so that the layout engine can establish intrinsic vertical height, not just horizontal position.
- **Minimum initial dimensions:** In `LayoutBarContainer.swift`, initialize `heightConstraint.constant` to a small positive minimum (e.g., 20pt) rather than `0`, so the scroll view's clip view does not collapse before the first layout pass completes.
- **Use intrinsic content size:** Consider using `fittingSize` or `intrinsicContentSize` for container dimensions instead of relying solely on constraint constants that may be zero.

---

## Fix 6: SDK Runtime Discrepancy

**Files:** Various (window discovery and screen capture code)

- **Fallback window discovery:** Add alternative enumeration paths for modern macOS, such as iterating `NSStatusBar.system.statusItems` or using `CGSGetConnectionWindowList`, when `CGWindowListCreateImage` returns blank buffers or titles are anonymized.
- **Runtime detection:** Detect title anonymization at runtime (e.g., by checking whether known system item titles are empty) and automatically switch to the robust matching path that does not depend on titles.
- **Documentation:** Clearly document the macOS 14 SDK compilation requirement for users who want legacy compatibility shims to apply.

---

## Fix 7: Gatekeeper "Damaged App" False Positives

**Process / Build Scripts**

- **Re-sign embedded binaries:** Run `codesign --force --deep --sign - /path/to/Ice.app` after building to ad-hoc sign all inner binaries with a consistent local signature.
- **Clean sync conflict files:** Before building, remove any Dropbox/cloud sync conflict files from the bundle:
  ```bash
  find . -name "*conflicted*" -delete
  ```
- **Build outside sync folders:** Perform the build in a directory not managed by Dropbox (e.g., `/Users/Shared/` or `~/Builds/`), then copy the final `.app` bundle into `Applications` afterward.
- **Sparkle re-signing:** Add a build script phase that explicitly re-signs Sparkle's inner binaries (`Autoupdate`, `Updater.app`, `Installer.xpc`, `Downloader.xpc`) with the local signing certificate to preserve the bundle's cryptographic seal.

---

---

# Implementation Status Summary

| Fix | Status | Resolution Details |
|---|---|---|
| **1. Solid White Rectangle (`NaN` Color)** | **Resolved ✅** | Added `guard includedPixelCount > 0 else { return nil }` in `averageColor(makeOpaque:)` (`Extensions.swift`) to prevent zero-alpha division. |
| **2A. Title-Independent Delimiter Lookup** | **Resolved ✅** | Updated `MenuBarItemManager.swift` and `MenuBarManager.swift` to match delimiters by known `windowID` and `owningApplication == .current`, falling back to `MenuBarItem(windowID:)` without relying on window titles. |
| **2B. Non-Destructive Cache Handling** | **Resolved ✅** | Retains existing `ItemCache` state across transient window observation drops; added `ItemCache.isEmpty` and removed destructive `clear()` on transient observation drops. |
| **2C. Relax Title Filtering** | **Resolved ✅** | Removed empty title filtering in `MenuBarItem.getMenuBarItems()` so anonymized status bar windows are preserved. |
| **3. Delimiter Frame Collapsing & Partitioning** | **Resolved ✅** | Updated `Predicates.swift` section predicates (`isInVisibleSection`, `isInHiddenSection`, `isInAlwaysHiddenSection`) to use directional boundary comparisons that properly handle zero-width delimiter frames when section dividers are hidden. |
| **4. UI View Hierarchy Bypass (`cacheFailed`)** | **Resolved ✅** | Removed the blocking `imageCache.cacheFailed` gate in `LayoutBar.swift` so `Representable` is always mounted, ensuring views populate asynchronously as captures complete. |
| **5. Auto Layout Dimension Collapse** | **Resolved ✅** | Added explicit vertical boundary constraints (`topAnchor`/`bottomAnchor`) in `LayoutBarPaddingView.swift` and enforced a minimum height in `LayoutBarContainer.swift`. |
| **6. SDK Runtime Discrepancy & Fallbacks** | **Resolved ✅** | Configured `activeSpaceOnly: false` window discovery, added AppKit icon and SF Symbol fallbacks (`NSRunningApplication.icon`, system symbols for Wi-Fi, battery, clock, audio) in `LayoutBarItemView.swift` when screen capture buffers are unpopulated. |
| **7. Gatekeeper & Build Integrity** | **Resolved ✅** | Removed pre-compiled Sparkle binaries, scrubbed Dropbox conflict files, and created automated build/sign/deploy script (`scripts/build.sh`) with deep code signing and quarantine attribute stripping. |

