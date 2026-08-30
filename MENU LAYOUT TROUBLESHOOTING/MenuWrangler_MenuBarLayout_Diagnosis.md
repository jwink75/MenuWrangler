# MenuWrangler — "Menu Bar Layout" Icon/Label Bug: Diagnosis & Fixes

**Symptom:** In the Menu Bar Layout pane, most items render as a duplicated Control
Center icon (two stacked, inverted-color toggle switches) labeled `Item-0`,
instead of each item's real icon and name.

This was diagnosed directly from the `MenuWrangler-step-by-step-development`
source (not guesswork) — specifically `WindowQuery.swift`,
`DirectQueryLayoutBar.swift`, `LayoutItemView.swift`, `MenuBarItem.swift`, and
the project's own `layout_bars.md` / `new_menu_bar_layout.md` notes, which show
your two agents have already been circling this exact bug.

---

## Why this is happening

### 1. The pane in use bypasses the one place that already gets names right

There are **two separate, competing pipelines** in the codebase for reading
menu bar items:

| Pipeline | Files | Name resolution quality |
|---|---|---|
| **Legacy** (inherited from upstream Ice) | `MenuBarItemManager`, `MenuBarItem.swift`, `LayoutBar.swift` | Good — `MenuBarItem.displayName` maps Control Center sub-items by **bundle-identifier namespace + title** (`BentoBox` → "Control Center", `WiFi` → "Wi-Fi", `FocusModes` → "Focus", etc.) |
| **Direct Query** (the new bypass approach) | `WindowQuery.swift`, `DirectQueryLayoutBar.swift`, `LayoutItemView.swift` | Weak — matches only against the raw window `title` with crude substring checks |

`MenuBarLayoutSettingsPane.swift` wires the visible UI to `DirectQueryLayoutBar`
only. The legacy `LayoutBar` and its correct Control-Center-aware naming logic
are **dead code as far as this screen is concerned** — the good fallback logic
your project already wrote is simply never called from here.

### 2. The active pipeline keys its icon/name lookup off `title`, which macOS anonymizes

In `WindowQuery.createFallbackImage(...)`, the SF Symbol lookup is:

```swift
let titleLower = title.lowercased()
...
if titleLower.contains("wifi") { symbolName = "wifi" }
else if titleLower.contains("battery") { symbolName = "battery.100" }
...
```

On modern macOS, most Control Center sub-items (Wi-Fi, Bluetooth, Battery,
Focus, etc.) do **not** expose a normal, stable window title to third-party
processes — the title is empty or a generic placeholder assigned by
WindowServer. Your own `new_menu_bar_layout.md` already documented this
("`Item-0` items are generic Control Center items with no specific title").
Because none of the keyword branches can match an empty/placeholder title,
`symbolName` ends up `nil` for nearly every real system item.

### 3. The fallback-of-last-resort collapses many different items into one icon

When symbol matching fails, the code falls through to:

```swift
let appIcon = cachedIcon(for: ownerPID, ownerName: ownerName)
```

```swift
if let app = NSRunningApplication(processIdentifier: ownerPID) {
    icon = app.icon
}
```

Here's the key problem: **Wi-Fi, Bluetooth, Battery, Focus, and most other
Control Center modules are not separate processes** — they are all owned by
the single system **Control Center** process. So `ownerPID` is identical for
all of them, and this line returns **Control Center's own app icon** (the two
stacked toggle switches) for every single one. Worse, the result is memoized
in a per-PID cache:

```swift
private static var iconCache: [pid_t: NSImage] = [:]
...
if let cached = iconCache[ownerPID] { return cached }
```

Once one Control Center item resolves to Control Center's app icon, **every
other item sharing that PID is guaranteed to get the exact same cached
image** — which is exactly the "same icon repeated" behavior in your
screenshot.

### 4. Off-screen ("hidden") items can't be screen-captured at all

Your own `new_menu_bar_layout.md` already flagged this: `ScreenCapture` and
`CGWindowListCreateImage` only work for on-screen (positive-X) windows.
Items sitting in the hidden section are off-screen by design, so their real
icon can never be captured — they fall straight through to the broken
symbol/PID fallback above, which is why the **Hidden Section** in your
screenshot is uniformly bad while the **Visible Section** at least shows some
real-looking glyphs (`SItem`, `BentoBox-0`).

### 5. Screen Recording permission may not actually be attached to this exact build

`MenuBarLayoutSettingsPane` already checks
`ScreenCapture.cachedCheckPermissions()` and shows a warning banner when it's
false — but that banner isn't visible in your screenshot, so permission is
*probably* fine. Still worth ruling out, because it's a classic hidden cause
of "everything falls back" bugs: TCC (Privacy & Security → Screen Recording)
grants permission per code-signing identity. Every time Kilo Code/Antigravity
rebuild with Xcode's ad-hoc/dev signature, macOS can treat the binary as a
"new" app and silently drop previously granted access, making capture fail
for items that should otherwise work fine.

### 6. `Item-0` itself doesn't appear anywhere in this source snapshot

A full search of the provided zip for the literal string `"Item-0"` / `"Item-"`
turns up **nothing** — not in `WindowQuery.swift` (which falls back to
`"Unknown"`, not `"Item-0"`), not in `LayoutItemView.swift`, not in
`MenuBarItem.swift`. Two explanations are consistent with everything else
found:

- **Most likely:** the placeholder title `Item-0` is being assigned by
  **macOS itself** (WindowServer's anonymization for grouped/private status
  windows), not generated by your app code. In that case `title` isn't empty,
  it's literally the string `"Item-0"` — which also explains why it slips
  past the `titleLower.contains(...)` checks (none of them match `"item-0"`)
  and why several items can show the identical label if the OS assigns that
  placeholder to more than one grouped window.
- **Also possible:** the screenshot was taken from a build that predates the
  code in this zip. Since Kilo Code edits source while Antigravity handles
  builds, it's easy for the *running* `.app` to lag behind the *latest*
  source by a build-and-relaunch cycle — worth explicitly ruling out before
  chasing the code further.

---

## Recommended fixes, roughly in priority order

### Fix A — Stop maintaining two parallel item-introspection stacks
Retire the bespoke string-matching in `WindowQuery.swift` and have
`DirectQueryLayoutBar` construct/reuse `MenuBarItem`/`MenuBarItemInfo` (or at
minimum port over `MenuBarItem.displayName`'s bundle-namespace-aware switch
statement). Right now every naming fix has to be written twice, and the two
pipelines have already drifted — which is the direct cause of this bug.

### Fix B — Key name/icon resolution off bundle identifier + title namespace, not raw title substrings
Use `owningApplication.bundleIdentifier` to detect `com.apple.controlcenter`
specifically, then switch on `title` **within that namespace** the way
`MenuBarItem.displayName` already does. This is far more robust than
substring-matching an anonymized/placeholder title, and it already exists in
your codebase — it just needs to be reachable from the active pane.

### Fix C — Never fall back to "the owning process's app icon" for known multi-item hosts
For `com.apple.controlcenter` (and similarly, `SystemUIServer`), showing the
owning app's icon is actively misleading, since one process legitimately owns
many distinct, visually-different modules. When a specific module can't be
identified, prefer:
- a **generic, per-module SF Symbol** keyed off whatever partial identifying
  info is available (title, position, or accessibility identifier), or
- a **plain "?" / neutral placeholder glyph with the item's index or window
  ID as the label**, so at least it's visibly a "we don't know" state instead
  of silently rendering as if it were a duplicate of one real item.
Reserve the app-icon fallback for genuinely single-purpose third-party menu
extras, where `ownerPID` really does map 1:1 to one icon.

### Fix D — Fix the icon cache's key granularity
`iconCache: [pid_t: NSImage]` should not exist in its current form for
multi-item host processes — caching by PID guarantees every item under
Control Center converges on one image. If you keep a cache at all, key it by
`windowID` (or a stable per-module identifier if you can obtain one), never
by `ownerPID` alone.

### Fix E — Stop trying to live-screen-capture hidden/off-screen items on every refresh
This is a hard OS limitation, not a bug you can code around directly. Instead:
- Capture and cache each item's icon **the last time it was actually
  on-screen** (e.g., when the user reveals the hidden section, or right
  before an item transitions into it), and persist that cached image across
  refreshes/launches.
- This mirrors "Fix 8/9/10" already sketched in your own `layout_bars.md` —
  but note those fixes were written against `MenuBarItemImageCache` /
  `LayoutBar`, which `DirectQueryLayoutBar` doesn't use at all. They need to
  be re-targeted at whichever pipeline survives Fix A.

### Fix F — Verify Screen Recording permission is actually bound to the build you're testing
- `System Settings → Privacy & Security → Screen Recording`: remove any
  stale/duplicate MenuWrangler or Ice entries, then re-launch and re-grant.
- Build via `scripts/build.sh` consistently (it already exists in this repo)
  rather than raw Xcode runs, so the code-signing identity stays stable
  across iterations and TCC doesn't treat each build as a new app.
- `tccutil reset ScreenCapture <bundle-id>` if you suspect a stale grant, then
  re-test from a clean permission state.

### Fix G — Rule out a stale build before debugging further
Since two separate tools (Kilo Code for source, Antigravity for builds) are
touching this project, confirm the running binary actually reflects the
latest source before spending more time on the code:
- Fully quit MenuWrangler (check Activity Monitor for lingering helper
  processes, e.g. any Sparkle/updater remnants).
- `rm -rf ~/Library/Developer/Xcode/DerivedData/Ice-*` (or your project's
  DerivedData folder) to eliminate incremental-build staleness.
- Rebuild via `scripts/build.sh` and relaunch, then re-check whether
  `Item-0` still appears. If it's gone, the earlier screenshot was simply
  showing an older build — a workflow issue, not a code issue.

### Fix H — Surface the existing debug data in the UI itself
`WindowQuery.swift` and `DirectQueryLayoutBar.swift` already populate very
useful `UserDefaults` keys (`WindowQuery_allOwners`, `WindowQuery_allTitles`,
`LayoutBar_resultItems_*`, etc.) and `print()` statements. Add a small "Copy
Debug Info" button to `MenuBarLayoutSettingsPane` that dumps these into the
clipboard as text. That gives both agents (and you) ground truth about real
`title`/`ownerName`/`ownerPID` values per item on the exact machine and OS
version you're testing on, instead of inferring them from a screenshot.

---

## Suggested order of operations

1. **Fix G first** (rule out stale build) — costs nothing and eliminates a
   whole class of false leads.
2. **Fix H** (debug dump) — gives you real title/ownerName/PID data instead
   of guessing, and will confirm or refute the "OS assigns literal `Item-0`"
   theory in section 6 above.
3. **Fix A + B** (consolidate on the namespace-aware naming logic) — this is
   the structural fix; most of the visible symptoms trace back to the active
   pane using the weaker of your two existing implementations.
4. **Fix C + D** (stop collapsing distinct items into one icon).
5. **Fix E** (cache-on-last-visible for hidden items) and **Fix F**
   (permission hygiene) as the remaining polish items.
