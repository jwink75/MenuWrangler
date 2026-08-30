# MenuWrangler “Menu Bar Layout” Failure Analysis

**Prepared:** August 30, 2026  
**Scope:** Uploaded MenuWrangler source snapshot, supplied Menu Bar Layout screenshot, and current upstream Ice/macOS 26 compatibility work.

---

## Executive conclusion

The screenshot is actually encouraging: **MenuWrangler is finding menu-bar windows and partitioning at least some of them into Visible and Hidden sections. The primary failure is no longer basic enumeration. It is item identity plus image acquisition.**

The repeated two-toggle **Control Center** icon and repeated **`Item-0`** label have a very specific explanation in the code you uploaded:

1. On macOS 26, many or all status-item windows are re-parented to **Control Center**, so `kCGWindowOwnerPID` / `NSRunningApplication(processIdentifier:)` no longer tells you which application actually created a third-party item.
2. Many re-parented windows have generic or missing titles such as `Item-0`.
3. `WindowQuery.createFallbackImage(...)` first tries to capture pixels from each window.
4. When capture fails, an `Item-0` title does not match any of your title-to-SF-Symbol rules.
5. The next fallback calls `cachedIcon(for: ownerPID, ...)`.
6. Because the reported owner PID is Control Center for these windows, the code fetches **Control Center.app’s application icon** and caches it under the Control Center PID.
7. Every unidentified item with that same owner PID therefore gets the exact same Control Center icon.
8. `LayoutItemView` displays the window title directly, so a WindowServer title of `Item-0` is shown verbatim.

That chain matches the screenshot almost perfectly. In other words, the repeated Control Center icon is not merely a mysterious macOS rendering failure. **It is the expected output of the current fallback logic after capture and real-source identification have both failed.**

There is a second architectural problem waiting behind it. The older Ice model identifies an item with `MenuBarItemInfo(namespace:title)`. On Tahoe, if multiple items become `com.apple.controlcenter:Item-0`, they are the **same dictionary key** as far as `MenuBarItemImageCache` is concerned. Even if you repair capture, different items can overwrite one another unless the identity model is also updated.

My strongest recommendation is therefore **not** to keep adding more title heuristics to `WindowQuery`. Port the newer macOS 26 item-identification architecture from Ice’s current compatibility work, especially the separation of **owner PID** from **source PID**, and then let MenuWrangler’s layout UI consume that authoritative item model.

---

# 1. What the screenshot tells us

The supplied screenshot contains several useful diagnostic clues.

### What is working

- The settings pane loads normally.
- The Visible and Hidden section containers are populated.
- MenuWrangler’s own `SItem` is found.
- `BentoBox-0` / Control Center and `Clock` are found.
- Bluetooth, Wi-Fi, and Battery are found in the Hidden section.
- The layout is not simply returning zero windows.
- Section filtering is doing enough work to place different items in different rows.

### What is failing

- A number of distinct status windows are all displayed with the same Control Center application icon.
- Those same windows carry the generic title `Item-0`.
- Known system items fare better because their titles trigger explicit SF Symbol fallbacks.
- Third-party identity is effectively lost.
- Actual status-item glyph capture appears to be failing for the problematic items.

This distinction matters. A large amount of debugging effort can be wasted trying additional enumeration APIs when **enumeration is already returning distinct window IDs**. The key questions now are:

> “Who really created window ID X?” and “Can I obtain a useful visual representation for window ID X?”

Those should be treated as separate problems.

---

# 2. The strongest concrete bug in the current code

## `WindowQuery.swift` guarantees the repeated Control Center fallback under Tahoe conditions

Relevant local file:

`Ice/UI/LayoutBar/WindowQuery.swift`

The current sequence is:

```swift
let ownerName = windowInfo.ownerName ?? "Unknown"
let windowTitle = windowInfo.title ?? ""
let ownerPID = windowInfo.ownerPID
...
let image = createFallbackImage(
    for: windowID,
    ownerPID: ownerPID,
    ownerName: ownerName,
    title: windowTitle,
    frame: frame
)
```

Then `createFallbackImage` does roughly this:

```text
1. ScreenCapture.captureWindow
2. CGWindowListCreateImage
3. SF Symbol inferred from title
4. NSRunningApplication icon for ownerPID
5. generic menu-bar symbol
```

The application-icon fallback is the crucial part:

```swift
if let app = NSRunningApplication(processIdentifier: ownerPID) {
    icon = app.icon
}
```

And that icon is cached by PID:

```swift
private static var iconCache: [pid_t: NSImage] = [:]
```

On macOS 26, upstream Ice maintainers explicitly discovered that status-item windows are re-parented to Control Center. That means:

```text
third-party menu item A -> reported ownerPID = Control Center PID
third-party menu item B -> reported ownerPID = Control Center PID
third-party menu item C -> reported ownerPID = Control Center PID
```

If image capture fails for A, B, and C, they all resolve to:

```text
iconCache[controlCenterPID] = Control Center.app icon
```

This is almost certainly the origin of the identical stacked-toggle icons in your screenshot.

### Immediate diagnostic proof to add

Before changing anything else, log the following for every card in the screenshot:

```text
windowID
ownerPID
ownerName
owner bundle ID
window title
frame
capture attempt 1 result
capture attempt 2 result
fallback selected
```

I expect most `Item-0` entries will show the same `ownerPID` and the bundle identifier `com.apple.controlcenter`, despite representing distinct menu-bar items.

---

# 3. `Item-0` is not coming from your SwiftUI label code

Relevant local file:

`Ice/UI/LayoutBar/LayoutItemView.swift`

The label is:

```swift
Text(item.title.isEmpty ? item.ownerName : item.title)
```

There is no hard-coded `Item-0` label in this path. If `Item-0` is visible, it is being supplied through the window metadata as `item.title`.

This is another reason not to build identity around window titles on Tahoe. A title such as `Item-0` is best treated as a **non-semantic system placeholder**, not as a stable item identifier or a useful display name.

I would explicitly classify titles matching patterns such as these as unusable for identity:

```text
empty string
Item-<integer>
possibly BentoBox-<integer> variants where the suffix is implementation detail
```

Do not throw the item away, however. Preserve the window and obtain identity from another source.

---

# 4. The older `MenuBarItemInfo(namespace:title)` identity model breaks on Tahoe

Relevant files:

- `Ice/MenuBar/MenuBarItems/MenuBarItem.swift`
- `Ice/MenuBar/MenuBarItems/MenuBarItemInfo.swift`
- `Ice/MenuBar/MenuBarItems/MenuBarItemImageCache.swift`

`MenuBarItemInfo` is hashable and consists of only:

```swift
let namespace: Namespace
let title: String
```

The namespace is constructed from the **owning application’s bundle identifier**:

```swift
if let bundleIdentifier = itemWindow.owningApplication?.bundleIdentifier {
    self.namespace = Namespace(bundleIdentifier)
}
```

The image cache is then keyed by this object:

```swift
@Published private(set) var images = [MenuBarItemInfo: CGImage]()
```

On pre-Tahoe systems this was often sufficient because a third-party item window belonged to the third-party process. On Tahoe, consider ten windows that all report:

```text
namespace = com.apple.controlcenter
title     = Item-0
```

All ten produce the same `MenuBarItemInfo` hash/equality key.

Then this assignment:

```swift
images[itemInfo] = itemImage
```

repeatedly overwrites the previous image.

### Important nuance

Your new `DirectQueryLayoutBar` currently bypasses this legacy image dictionary and stores an `NSImage` directly in each `LayoutItemInfo`, so **this dictionary collision is probably not the immediate cause of the cards in the screenshot**.

But if you return to the original `LayoutBar` architecture without replacing the identity model, the collision remains a fundamental Tahoe bug.

### Correct direction

Identity should include the **actual source application**, not the WindowServer owner. A model closer to this is needed:

```swift
struct MenuBarItemIdentity: Hashable {
    let sourcePID: pid_t?
    let sourceBundleID: String?
    let stableSystemTag: String?
    let windowID: CGWindowID
}
```

The exact persistent identity strategy can be refined, but `owner bundle + window title` is no longer sufficient on macOS 26.

---

# 5. Upstream Ice has already reached the same architectural conclusion

This is one of the most valuable findings from comparing your snapshot with Ice’s later macOS 26 work.

## Upstream macOS 26 compatibility work

Ice PR **#940**, “fix: merge macOS 26 compatibility fixes,” bundles the newer Tahoe architecture. Its summary specifically includes:

- a new `MenuBarItemService` XPC service;
- a `SourcePIDCache`;
- updated private API wrappers;
- menu-bar item handling and cache changes;
- multiple macOS 26 layout/UI fixes.

An earlier commit in that work, **`ad86802`**, states the underlying discovery explicitly: on macOS 26, items are owned by Control Center and the old identifier mechanism is no longer adequate.

The newer design separates the process that **owns the WindowServer window** from the process that **originated the status item**. That distinction is exactly what MenuWrangler is currently missing.

Ice PR **#903** likewise describes Tahoe behavior where menu-bar items appear owned by Control Center and titles may be nil, and adds Tahoe-specific control-item mapping plus source-PID handling.

### Recommendation

Treat the newer upstream Tahoe branch as an architectural migration, not a source of isolated one-line fixes. The safest direction is:

1. obtain a clean snapshot of the newer upstream macOS 26 implementation;
2. identify all menu-bar discovery/model/cache changes as a coherent set;
3. port those into MenuWrangler;
4. reapply your MenuWrangler branding/custom work after the underlying item model is modernized.

Trying to reproduce that architecture piecemeal with more `if title.contains(...)` rules is likely to consume much more time.

---

# 6. A second very plausible capture failure exists in your exact `ScreenCapture.swift`

Relevant local file:

`Ice/Utilities/ScreenCapture.swift`

Your current code avoids a deprecation warning by putting the `CGImage` initializer behind a protocol:

```swift
private protocol WindowListImage {
    init?(
        windowListFromArrayScreenBounds: CGRect,
        windowArray: CFArray,
        imageOption: CGWindowImageOption
    )
}

private extension WindowListImage {
    static func windowListImage(...) -> Self? {
        Self(windowListFromArrayScreenBounds: ...)
    }
}

extension CGImage: WindowListImage { }
```

and then calls:

```swift
return .windowListImage(...)
```

This is particularly notable because upstream Ice commit **`38d344f`** later reverted this exact indirection. The upstream commit notes that calling the initializer through the static protocol method appeared to make screen capture fail for some users, and returned to a direct `CGImage(...)` initializer call.

### This should be one of your first experiments

Replace the protocol-dispatched call with a direct call equivalent to:

```swift
return CGImage(
    windowListFromArrayScreenBounds: screenBounds ?? .null,
    windowArray: windowArray,
    imageOption: option
)
```

Accept/suppress the deprecation warning locally rather than changing how the initializer is invoked.

This is unusually high-value because:

- your current source still contains the older pattern;
- upstream later identified that exact pattern as a capture reliability problem;
- your screenshot shows the fallback path being selected for many items.

It may not solve identity, but it could immediately restore many actual menu glyphs.

---

# 7. `CGWindowListCreateImage` is not a robust Tahoe rescue path

`WindowQuery.createFallbackImage` next tries:

```swift
CGWindowListCreateImage(
    .null,
    .optionIncludingWindow,
    windowID,
    .boundsIgnoreFraming
)
```

This API family is deprecated and has become increasingly awkward under modern screen-capture privacy behavior. It remains useful to Ice largely because ScreenCaptureKit does not solve every offscreen menu-item capture case, but you should not assume that “call the second deprecated capture API” provides an independent, reliable fallback.

Both attempts can fail for the same underlying reason:

- the window is offscreen/hidden;
- privacy authorization is absent or stale;
- the status item is now represented differently by Control Center;
- supplied bounds are wrong;
- the backing surface is not available as expected;
- the system call itself is unreliable on that OS build.

Therefore log **why** each capture failed instead of treating capture as a Boolean.

At minimum record:

```text
returned nil?
image width / height
average alpha
number or percentage of nontransparent pixels
requested bounds
current CGS bounds
isOnScreen
space IDs
display ID
```

---

# 8. Passing each window’s frame as `screenBounds` deserves an A/B test

Current code:

```swift
ScreenCapture.captureWindow(
    windowID,
    screenBounds: frame,
    option: .boundsIgnoreFraming
)
```

For a one-window capture, I would test `screenBounds: nil` first and let the window-list image initializer derive the minimum rectangle itself.

Why this can matter:

- hidden items can use unusual/negative coordinates;
- multiple-display coordinate spaces complicate assumptions;
- the bounds in `WindowInfo` come from `CGWindowListCreateDescriptionFromArray`, while another private API can return a fresher frame;
- Tahoe/Control Center may move or reparent status windows between the metadata query and capture call.

A stale or mismatched crop rectangle can turn a valid backing image into a blank result.

Suggested test matrix for one known failing `Item-0` window:

```text
A. screenBounds = metadata frame
B. screenBounds = nil
C. bounds from Bridging.getWindowFrame(for:)
D. no explicit bounds + .bestResolution
E. explicit bounds + .bestResolution
```

Save each result as a diagnostic PNG by window ID during development. Do not guess from the SwiftUI card.

---

# 9. Screen-recording permission detection can return a false positive

Relevant local code:

```swift
if CGPreflightScreenCaptureAccess() {
    return true
}

for item in MenuBarItem.getMenuBarItems(...) {
    ...
    if let title = item.title, !title.isEmpty {
        return true
    }
}
```

The fallback assumption appears to be:

> “If I can see a nonempty title from another process, screen capture access is effectively available.”

That inference is weak on Tahoe. A generic title such as `Item-0` may be available even when the app cannot capture usable pixels.

That gives you a particularly confusing state:

```text
permission check says YES
settings pane does not show warning
pixel capture repeatedly fails
fallback icons are used
```

### Better approach

Treat these as separate capabilities:

```text
window metadata available
pixel capture authorized
pixel capture operational
```

A real capture probe is more useful than relying on a title.

For example, after permission is supposedly granted, attempt to capture one known on-screen, non-MenuWrangler menu item and verify that the result contains visible pixels. Cache that result briefly.

---

# 10. The rebrand matters for TCC even if it is not the main Tahoe identity bug

Your target now uses:

```text
com.jwink75.MenuWrangler
```

The old Ice grant would have belonged to a different code identity/bundle identifier. Screen Recording and Accessibility permissions do not simply transfer because the source code is the same.

### After the bundle-ID change, explicitly test from a clean permission state

For development, remove/reset MenuWrangler’s entries for:

- Screen & System Audio Recording;
- Accessibility.

Then relaunch the current signed build and grant them again.

If you use Terminal during development, the standard TCC reset commands can target the new bundle ID, for example:

```bash
tccutil reset ScreenCapture com.jwink75.MenuWrangler
tccutil reset Accessibility com.jwink75.MenuWrangler
```

Then relaunch and grant permissions normally in System Settings.

### Keep signing identity stable while debugging

TCC does not only care about the text of a bundle identifier. Code-signing identity/designated requirement also matters. Switching among:

- Xcode-signed builds;
- manually Developer-signed builds;
- ad-hoc builds;
- copies rebuilt/re-signed by scripts

can make permission behavior difficult to reason about.

During this investigation, choose one build/sign/install path and keep it stable.

---

# 11. Your build script will need reconsideration if you port the Tahoe XPC service

The current `scripts/build.sh`:

1. builds with an Apple Development team;
2. copies the app to `/Applications`;
3. runs a blanket `codesign --force --deep` over the installed application.

That may be tolerable for the current single-app bundle, but it becomes riskier if you adopt upstream’s `MenuBarItemService.xpc`.

With an XPC service, the relationship between:

- host app signature;
- XPC service signature;
- Team Identifier;
- peer requirements;
- service entitlements

becomes part of the item-discovery architecture.

Ice PR **#950** documents a concrete failure mode in community/ad-hoc builds: `.isFromSameTeam()` can reject the XPC connection when there is no Team Identifier, leaving `sourcePID` unavailable and the layout empty.

Your current script appears to have a real Apple Development team configured, so you may not hit the exact ad-hoc case **provided the host and XPC service are both signed correctly by the same team**. Nevertheless:

- let Xcode sign nested code correctly where possible;
- avoid treating `codesign --deep` as a universal repair tool;
- verify the host and XPC service Team IDs after building;
- if you support ad-hoc community builds, port the upstream conditional peer-requirement fix as well.

A future MenuWrangler build should have an explicit “signed nested components, then host” strategy rather than a generic post-build deep-sign pass.

---

# 12. The new `DirectQueryLayoutBar` has several architectural regressions

Relevant local file:

`Ice/UI/LayoutBar/DirectQueryLayoutBar.swift`

This view was added as an escape hatch around the older cache pipeline. It is useful diagnostically, but I would not keep evolving it as the permanent architecture in its current form.

## A. Always-Hidden can never work

The code literally does:

```swift
case .alwaysHidden:
    result = []
```

So the current settings pane is incapable of rendering Always-Hidden items even if the discovery layer finds them correctly.

## B. Drag and drop does not move anything

`moveItem` currently only prints:

```swift
print("Moving window ...")
```

and refreshes after half a second.

So the pane currently advertises “Drag to arrange” while its direct-query implementation has no actual movement operation.

## C. The direct implementation discards the robust section predicates already in the project

The older manager uses `Predicates.sectionPredicates(...)`, which knows about both HItem and AHItem and includes special handling for zero-width control-item frames.

The direct view instead calculates one boundary:

```swift
let delimiter = sortedWindows.first { $0.isDelimiter }
let delimiterX = delimiter?.frame.origin.x ?? 0
```

and splits everything into only two sides.

That loses previously implemented handling for:

- always-hidden boundaries;
- hidden control-item geometry;
- zero-width delimiters;
- item frames crossing a boundary.

## D. Delimiter recognition remains heuristic

`WindowQuery` says:

```swift
let isDelimiter = (
    windowTitle == "HItem" ||
    ownerName == "MenuWrangler" ||
    ownerName == "Ice"
)
```

The owner-name branches are unsafe on Tahoe because your own item can be re-parented as well.

You already possess the actual `NSStatusItem` objects and their `ControlItem.windowID`/window frames. Use those as the source of truth, with Tahoe-specific frame matching when direct window IDs no longer correspond.

## E. Refresh does capture work synchronously

`refreshItems()` calls `WindowQuery.getMenuBarWindows()`, which loops over every discovered window and attempts one or two synchronous image captures for each.

That work is initiated from SwiftUI interaction / lifecycle code. It is an easy path to UI stalls, particularly because there are upstream reports of synchronous menu-window capture calls blocking on Tahoe.

Discovery should be quick and image capture should be asynchronous/best-effort.

## F. `id = UUID()` makes every refresh look like an entirely new list

`LayoutItemInfo` currently has:

```swift
let id = UUID()
```

Although equality/hashing use `windowID`, SwiftUI’s `Identifiable` behavior uses the UUID. Every refresh assigns every item a new identity, forcing SwiftUI to tear down and recreate cards.

Use a stable ID, at minimum:

```swift
var id: CGWindowID { windowID }
```

or a stable source-aware tag.

This is not the cause of `Item-0`, but it creates needless UI churn and makes debugging updates harder.

---

# 13. The current delimiter should be identified from MenuWrangler’s actual control item, not from owner/title guesses

You already have a stronger path in `MenuBarItemManager.cacheItemsIfNeeded()`:

```swift
let hiddenWindowID = ...controlItem.windowID
...
items.firstIndex(where: { $0.windowID == hiddenWindowID })
```

That is conceptually better than scanning for the first `HItem` string.

On some Tahoe versions, even `NSWindow.windowNumber` / CG window-ID correspondence can become awkward. Upstream work addresses this by matching MenuWrangler/Ice control item windows using geometry and restoring an internal title/tag override.

### Recommended section-boundary hierarchy

Use, in this order:

```text
1. direct known control-item CGWindowID if valid;
2. frame match between the live NSStatusItem window and enumerated CG status windows;
3. internal title/tag override created from that match;
4. title heuristic only as a diagnostic last resort.
```

Never use `ownerName == "MenuWrangler"` as the primary Tahoe boundary identity.

---

# 14. Multi-display and Spaces can create duplicates or misleading `Item-0` windows

`WindowQuery.getMenuBarWindows()` currently requests:

```swift
Bridging.getWindowList(option: [.menuBarItems])
```

It does not select:

- active space;
- current display;
- a particular menu-bar host.

Then `DirectQueryLayoutBar` sorts all returned windows only by `x` coordinate.

That can become problematic when:

- multiple displays have menu bars;
- displays use separate spaces;
- a menu item has per-display clones;
- inactive-space status windows remain in the list;
- system clone windows exist at the menu-bar layer.

### Suggested test

Add a diagnostic count for these three queries side by side:

```text
.menuBarItems
.menuBarItems + .activeSpace
.menuBarItems + .onScreen + .activeSpace
```

For every item also record the intersecting display ID and its space IDs.

Do not blindly switch everything to `activeSpaceOnly: true` because hidden/offscreen items can complicate that. The goal is to understand which list includes canonical items and which includes clones.

### UI-level recommendation

The layout editor should display the items for a **specific active menu-bar display**, rather than combining every menu-bar window from every display into one x-sorted sequence.

---

# 15. macOS 26.4 added another upstream display-ID failure worth porting

Ice PR **#922** documents a different Tahoe issue: on macOS 26.4.1, a private call used to get the active menu-bar display identifier can return nil. That caused item enumeration to succeed but the image/layout cache to have no display ID, ultimately producing an empty layout pane.

Your current direct-query implementation happens to sidestep that particular cache guard, which may be one reason it displays *something*. But if you port the modern cache architecture, also port the newer display-ID fallback rather than reintroducing the 26.4 failure.

For a single-display fallback, upstream used `CGMainDisplayID()`. For a robust multi-display implementation, infer the display from the relevant menu-bar/control-item window bounds when possible.

---

# 16. Window-list fallback filtering is too coarse

Relevant local file:

`Ice/Bridging/Bridging.swift`

If `CGSGetProcessMenuBarWindowList` fails, the fallback looks for:

```swift
layer == 25 || layer == kCGMainMenuWindowLevel
```

This is broad enough to admit windows that are not the status-item population you want.

Also, when the private call **does** succeed, the returned list is accepted without the newer Tahoe filtering found in upstream compatibility work.

### Improvements

- Prefer the private menu-bar-window list when it is available.
- Query descriptions only for those IDs.
- Filter out the actual main-menu window when it leaks into the list.
- Filter zero-sized and obviously invalid windows.
- Track window level using named CoreGraphics level APIs/constants instead of treating integer `25` as the conceptual definition everywhere.
- Add explicit system-clone filtering if the newer upstream code does so for your target OS version.
- Deduplicate window IDs before model construction.

The broad `CGWindowListCopyWindowInfo(.optionAll)` scan is useful as a diagnostic/emergency fallback, but it should not become the authoritative source of identity.

---

# 17. `WindowInfo.isMenuBarItem` is intentionally simple, perhaps too simple for a fallback path

Current definition:

```swift
var isMenuBarItem: Bool {
    layer == kCGStatusWindowLevel
}
```

That is sensible for a known menu-bar ID returned by `CGSGetProcessMenuBarWindowList`, but it is much less discriminating when fed arbitrary windows discovered from `.optionAll`.

For fallback discovery, consider additional sanity checks:

```text
reasonable menu-bar-height bounds
frame near the top edge of one display
nonzero width/height
known status-window level
not a main application menu window
not a wallpaper/window-server artifact
not a duplicate clone
```

Keep these as **validation**, not identity. The source PID/tag should still determine what the item is.

---

# 18. Do not use the Control Center owner app icon as an unidentified Tahoe fallback

Even before you finish the source-PID architecture, you can prevent the current misleading UI.

If all of these are true:

```text
OS >= macOS 26
owner bundle ID == com.apple.controlcenter
window title is empty/generic Item-N
no real source PID known
capture failed
```

then **do not** return Control Center.app’s icon.

Instead show an intentionally neutral placeholder, for example `menubar.rectangle`, and label it something like:

```text
Unknown item · window 12345
```

in a diagnostic build.

That will not fix the underlying issue, but it will stop the UI from falsely implying that ten separate entries are Control Center itself.

Once `sourcePID` is available, fall back to the **source application icon**, not the owner application icon.

---

# 19. The `cachedIcon` API has an arbitrary size test that should be removed

Current code:

```swift
let appIcon = cachedIcon(...)
if appIcon.size != NSSize(width: 24, height: 24) {
    return appIcon
}
```

This uses image dimensions as a proxy for “real app icon versus generic fallback.” That is fragile. A perfectly valid app icon could report 24×24, and a generic image could report something else.

Return an optional instead:

```swift
private static func cachedSourceApplicationIcon(...) -> NSImage?
```

Then use `nil` to mean “not found.” Never infer validity from image size.

---

# 20. Separate item discovery, item identity, and item artwork

The present direct-query path combines all three in one loop:

```text
enumerate window
read metadata
identify delimiter
capture image
choose fallback image
construct UI item
```

That makes every capture problem look like a discovery problem.

A more durable pipeline is:

```text
Stage 1: Discover
    -> canonical window IDs + current bounds

Stage 2: Identify
    -> owner PID
    -> source PID
    -> source bundle ID
    -> system item tag
    -> display name
    -> control-item identity

Stage 3: Classify
    -> visible / hidden / always hidden
    -> display / space

Stage 4: Render model immediately
    -> cards exist even without screenshots

Stage 5: Resolve artwork asynchronously
    -> captured status glyph if possible
    -> known system symbol if appropriate
    -> source application icon
    -> neutral placeholder
```

This architecture gives you a usable layout editor even if screen capture is temporarily unavailable.

---

# 21. Source PID should be the center of the Tahoe fix

The key new piece you need is a reliable answer to:

> “Which process created this status item before Control Center became its WindowServer owner?”

The upstream macOS 26 branch solves this with a dedicated source-PID mechanism and cache, exposed through `MenuBarItemService`.

Once you can obtain `sourcePID`, a large number of other problems simplify:

```text
sourcePID -> NSRunningApplication
          -> real bundle ID
          -> localized app name
          -> app icon fallback
          -> namespace/tag
          -> cache key
```

For system items, retain system-specific tags/titles as appropriate. For MenuWrangler’s own divider/status items, inject known identities from your `ControlItem` objects rather than relying on the re-parented owner.

### Do not confuse `ownerPID` and `sourcePID`

They are both useful:

```text
ownerPID  = process currently owning the WindowServer status window
sourcePID = process that created/originated the menu-bar item
```

On older macOS they may often be equal. On Tahoe they can be radically different.

---

# 22. Replace the legacy image cache key before restoring the original layout view

If you remove `DirectQueryLayoutBar` and return to the older `LayoutBar`, first change this:

```swift
[MenuBarItemInfo: CGImage]
```

where `MenuBarItemInfo` is only `(owner namespace, title)`.

A safer ephemeral key is the current `windowID`, because screenshots correspond to a particular window instance:

```swift
[CGWindowID: CGImage]
```

For longer-lived metadata caches, use a source-aware tag.

A useful distinction is:

```text
WindowSnapshotKey = CGWindowID
PersistentItemKey = source bundle / stable tag / role
```

Do not force one identifier to serve both purposes.

---

# 23. Current item-cache invalidation can miss metadata changes

`MenuBarItemManager.cacheItemsIfNeeded()` skips work when the array of window IDs has not changed:

```swift
if !itemCache.isEmpty && cachedItemWindowIDs == itemWindowIDs {
    return
}
```

On Tahoe, source-PID resolution can change from `nil` to a valid result without the window-ID array changing. A Control Center restart/reparent can also alter metadata in ways that make “same window-ID list” an insufficient cache validity test.

When you add source-PID resolution, cache invalidation should account for:

```text
window IDs
bounds/order
display ID
source-PID resolution state
control-item mapping generation
Control Center process generation
active space/display changes
```

Upstream/community fixes also added negative/failure caching to avoid continuously retrying expensive failed source-PID lookups.

---

# 24. Add failure caching, not just success caching

Without a negative cache, an unresolved item can trigger the same expensive work repeatedly:

```text
query source PID -> fail
refresh -> query again -> fail
refresh -> query again -> fail
```

This can create cache thrash and races with UI presentation.

Use a short TTL for failures, for example:

```text
source PID success: cache until window disappears / Control Center generation changes
source PID failure: retry after ~15–30 seconds or on explicit refresh
capture failure: retry after a short TTL or relevant permission/display change
```

An explicit Refresh button can bypass negative-cache TTLs.

---

# 25. Control Center restarts should invalidate Tahoe-specific caches

Control Center is now part of the menu-item hosting story. If its PID changes, caches keyed to its hosted windows may become stale.

Observe `NSWorkspace` running-application changes and, when `com.apple.controlcenter` terminates/relaunches:

```text
clear source-PID mappings tied to old window IDs
clear owner-PID icon fallback cache
re-enumerate menu-bar windows
re-map MenuWrangler control items
re-resolve display/space
schedule image refresh
```

This is more precise than using `NSApplication.didBecomeActiveNotification` as a general-purpose refresh signal.

---

# 26. Do not post `NSApplication.didBecomeActiveNotification` as your custom refresh event

The Refresh button currently does:

```swift
NotificationCenter.default.post(
    name: NSApplication.didBecomeActiveNotification,
    object: nil
)
```

That notification has system semantics. Fabricating it for unrelated refresh behavior makes the state graph harder to understand and can cause other observers to do inappropriate work.

Define your own notification or, better, expose a refresh method/generation on the discovery service:

```text
MenuBarItemDiscovery.didRequestRefresh
```

or:

```swift
itemDiscovery.refresh(force: true)
```

---

# 27. The capture pointer allocation leaks memory

Current `ScreenCapture.captureWindows` allocates:

```swift
let pointer = UnsafeMutablePointer<UnsafeRawPointer?>.allocate(
    capacity: windowIDs.count
)
```

but does not deallocate it.

That is not the cause of `Item-0`, but repeated layout refreshes can leak memory.

At minimum:

```swift
defer { pointer.deallocate() }
```

Better yet, use scoped Swift storage / `withUnsafe...` APIs so the lifetime is automatically bounded.

Upstream/community Tahoe work has had several fixes around capture-array and window-list lifetime leaks, so this is worth cleaning while touching the file.

---

# 28. Avoid per-item synchronous capture on the main thread

The direct layout currently performs up to two capture calls per window during refresh. With 15–30 menu items that can become dozens of synchronous system calls.

There is an upstream issue, **#777**, reporting hangs inside the same family of screen-capture calls on Tahoe.

Recommended behavior:

```text
main actor:
    render latest metadata cards quickly

background actor/queue:
    capture requested windows
    cap concurrency (e.g. 1–2 at a time)
    apply timeout/failure policy

main actor:
    publish artwork updates
```

Do not launch an unbounded task per icon. A serialized or low-concurrency capture worker is safer with these private/deprecated APIs.

---

# 29. Composite capture may be preferable, but make its geometry tolerant

The older `MenuBarItemImageCache` tries a composite capture, then crops each item. That has performance advantages because it avoids N synchronous captures.

However its current acceptance test is exact:

```swift
CGFloat(compositeImage.width) == frame.width * backingScaleFactor
```

An upstream Tahoe fix noted that a one-pixel discrepancy can occur and made composite handling more tolerant. The newer code also falls back to cached item bounds if a fresh private `CGSGetScreenRectForWindow` call fails.

If you keep composite capture:

- allow a tiny rounding tolerance;
- do not discard the entire composite because of a one-pixel mismatch;
- use current item bounds as a fallback;
- verify y/scale coordinates per display;
- handle negative origins;
- crop only after normalizing into the composite coordinate system.

---

# 30. Black-and-white versus color Control Center icons are probably a rendering symptom, not separate identities

You mentioned seeing both monochrome and color variants of the same stacked-toggle image.

The code mixes several image types:

```text
captured pixels
SF Symbols marked isTemplate = true
NSRunningApplication application icons
```

Template images are tinted according to the view’s current foreground style/appearance, while app icons retain color. A repeated logical fallback can therefore appear monochrome in one path and colored in another.

Do not use color variation as evidence that the items have been correctly distinguished.

For fallbacks:

- SF Symbols can remain template images;
- source application icons should **not** be forcibly made template images;
- real captured status glyphs should preserve their captured pixels;
- every artwork value should carry a `kind` for diagnostics.

For example:

```swift
enum ArtworkKind {
    case captured
    case knownSystemSymbol
    case sourceApplicationIcon
    case genericPlaceholder
}
```

Expose this in debug tooltips.

---

# 31. Improve display names independently of artwork

A layout card should not need a successful screenshot to have a meaningful name.

Suggested display-name priority:

```text
1. known MenuWrangler control-item name
2. known system menu-bar tag name
3. source application localized name + meaningful item title
4. source application localized name
5. meaningful window title
6. neutral “Menu Bar Item” diagnostic name
```

Treat `Item-0` as non-meaningful.

If one app creates multiple menu items, a real semantic tag/title should distinguish them. If no such metadata exists, include a temporary window-ID suffix only in debug builds.

---

# 32. The bundle-ID migration can reset NSStatusItem preferred positions

`ControlItem` uses autosave names:

```text
SItem
HItem
AHItem
```

and stores preferred-position defaults associated with the application’s preferences domain.

Because MenuWrangler has a new bundle identifier, values previously stored under Ice’s bundle/preferences domain will not automatically be present in the new domain.

This can change delimiter positions immediately after rebranding.

It does **not** explain the repeated Control Center image, but it can explain section-boundary surprises that appear to coincide with the rebrand.

### Options

- accept a clean layout reset on first MenuWrangler launch;
- or perform a one-time migration from Ice’s old defaults if you intentionally want to preserve positions;
- add a developer command/button to reset only SItem/HItem/AHItem preferred positions while debugging.

Avoid repeatedly changing these defaults while simultaneously debugging discovery, or you will have two moving variables.

---

# 33. Make sure old Ice and helper copies are not simultaneously active

Your build script kills both `MenuWrangler` and `Ice` and removes both `/Applications` copies, which is good.

Still verify during debugging that there is no:

- old Ice launch-at-login instance;
- copy launched from Downloads/DerivedData;
- stale helper/XPC process after future architecture changes;
- duplicate MenuWrangler app with another signing identity.

Two menu-bar managers can introduce extra delimiters/status windows and make source mapping unnecessarily confusing.

---

# 34. A clean Tahoe-focused model would make `WindowQuery` much smaller

`WindowQuery` currently contains both discovery and a growing list of display heuristics:

```text
wifi -> wifi symbol
battery -> battery symbol
bluetooth -> bolt symbol
sound -> speaker
AirDrop -> symbol
...
Dropbox -> shippingbox
Keyboard Maestro -> command
...
```

This is becoming a manual taxonomy of the current machine rather than a menu-bar discovery system.

I would reduce it to something closer to:

```swift
struct MenuBarWindowSnapshot {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let bounds: CGRect
    let rawTitle: String?
    let displayID: CGDirectDisplayID?
}
```

Then a separate resolver turns that into:

```swift
struct ResolvedMenuBarItem {
    let snapshot: MenuBarWindowSnapshot
    let sourcePID: pid_t?
    let sourceBundleID: String?
    let tag: MenuBarItemTag
    let displayName: String
    let section: MenuBarSection.Name
}
```

Artwork belongs in a third service/cache.

---

# 35. Recommended remediation path

I would tackle this in the following order.

## Phase 0 — Freeze the variables

- Use one Mac and one target macOS build initially.
- Use one signing method.
- Use one installed `/Applications/MenuWrangler.app` copy.
- Reset/regrant Screen Recording and Accessibility once.
- Disable Always-Hidden temporarily if needed so you have only one divider to validate.
- Record whether you are on a single or multi-display setup.

## Phase 1 — Add diagnostics only

Do not change behavior yet. Export one JSON snapshot containing, for every returned menu-bar window:

```json
{
  "windowID": 123,
  "rawTitle": "Item-0",
  "ownerPID": 456,
  "ownerName": "Control Center",
  "ownerBundleID": "com.apple.controlcenter",
  "frame": [x, y, w, h],
  "isOnScreen": false,
  "spaceIDs": [1],
  "displayID": 0,
  "captureDirectSucceeded": false,
  "captureLegacySucceeded": false,
  "fallbackKind": "ownerApplicationIcon"
}
```

This should prove the Control Center fallback chain within one run.

## Phase 2 — Fix the known screen-capture regression

- remove the protocol-dispatched `CGImage` initializer;
- call the initializer directly;
- deallocate the temporary pointer;
- test `screenBounds: nil` for individual captures;
- add `.bestResolution` consistently where useful;
- save failing/successful capture probes by window ID.

Do this before building more icon heuristics.

## Phase 3 — Stop lying in the fallback UI

If a generic Tahoe item is hosted by Control Center and the source is unknown:

- do not show Control Center.app’s icon;
- show neutral placeholder + raw diagnostic info.

This immediately makes subsequent tests readable.

## Phase 4 — Port real source-PID identification

Bring over the coherent newer Ice components for macOS 26:

- source-PID resolver/cache;
- `MenuBarItemService` XPC components;
- source-aware tag/namespace model;
- Tahoe control-item matching;
- item-manager changes that consume sourcePID;
- relevant failure-cache logic.

Do not just copy one class without its cache/model users.

## Phase 5 — Modernize cache keys

Replace owner/title-only item identity in screenshot and metadata caches.

Use `windowID` for current-image snapshots and a source-aware identity/tag for longer-lived state.

## Phase 6 — Restore one authoritative layout pipeline

Once the underlying item cache works on Tahoe, decide whether `DirectQueryLayoutBar` still serves a purpose.

My preference is:

- keep direct query as an optional developer diagnostics view;
- make the production Menu Bar Layout use the same authoritative item manager/model used by movement and other features.

This avoids maintaining two different interpretations of the menu bar.

## Phase 7 — Restore three-section classification and real movement

- use both HItem and AHItem;
- use existing robust predicates or their Tahoe-updated equivalent;
- connect drag/drop to the real item movement mechanism;
- verify movement with source-aware item identity.

## Phase 8 — Harden multi-display/Space behavior

Only after the single-display path is correct:

- display-specific item sets;
- active menu-bar display fallback;
- clone filtering;
- separate-spaces on/off;
- notch/no-notch machines.

---

# 36. Specific code changes I would ask Kilo Code / Antigravity to make first

The following tasks are intentionally small enough that an agent can make one change, build, and let you verify the result before continuing.

## Task A: diagnostics without behavior changes

> Add a developer diagnostic export for the Menu Bar Layout path. For every window returned by `Bridging.getWindowList(option: [.menuBarItems])`, record windowID, raw title, owner PID, owner name, owner bundle ID, bounds from both WindowInfo and `Bridging.getWindowFrame`, on-screen state, active-space state, and which icon fallback was selected. Do not alter filtering or rendering. Add a button in the Menu Bar Layout pane to write the snapshot as JSON to a temporary file and reveal it in Finder.

## Task B: remove the protocol capture indirection

> In `ScreenCapture.swift`, replace the `WindowListImage` protocol/static-method wrapper around `CGImage(windowListFromArrayScreenBounds:windowArray:imageOption:)` with a direct initializer call, matching upstream Ice commit `38d344f`. Preserve existing behavior otherwise. Also fix the allocated-pointer lifetime leak. Do not change discovery or UI in this commit.

## Task C: test nil bounds for single-window capture

> In `WindowQuery.createFallbackImage`, make the first individual capture call omit `screenBounds` so the system computes the enclosing window rectangle. Add logging comparing this result with the existing explicit-frame path in Debug builds. Do not add more title-to-symbol mappings.

## Task D: remove the misleading Control Center fallback

> On macOS 26+, when the owner bundle ID is `com.apple.controlcenter`, the title is empty or matches `Item-<number>`, and capture has failed, do not use `NSRunningApplication(ownerPID).icon`. Return a neutral menu-bar placeholder instead and mark the fallback kind as `unresolvedTahoeSource`.

## Task E: stable SwiftUI identity

> Change `LayoutItemInfo` so its `Identifiable.id` is stable across refreshes, using windowID rather than a fresh UUID. Keep hash/equality behavior consistent.

## Task F: do not reinvent section partitioning

> Refactor `DirectQueryLayoutBar` to use MenuWrangler’s actual HItem/AHItem control-window mappings and the existing section predicates rather than `first { isDelimiter }` + x-coordinate splitting. Do not implement movement yet.

## Task G: source-PID port

> Compare this fork against the current Ice macOS-26 compatibility branch / PR #940. Port the complete source-PID item-identification stack (`MenuBarItemService`, source-PID cache/resolver, source-aware item tag/namespace, item-manager integration, Tahoe control-item mapping). Preserve the MenuWrangler bundle ID and branding. Do not mix this work with UI redesign.

## Task H: XPC signing verification

> After introducing `MenuBarItemService.xpc`, verify both the host app and XPC service are signed by the same development team in normal builds. If ad-hoc builds remain supported, port the conditional same-team peer-requirement behavior described in Ice PR #950. Replace blanket post-build deep signing with a nested-code-aware signing strategy if necessary.

## Task I: modern cache key

> Audit every dictionary/set keyed by `MenuBarItemInfo(namespace:title)`. On macOS 26, multiple distinct items can have `com.apple.controlcenter` + `Item-0`, so this is not unique. Use windowID for ephemeral window/image caches and a source-aware tag for persistent identity. Add a unit test demonstrating that two `Item-0` windows from different source PIDs remain distinct.

---

# 37. Additional tests that can quickly isolate the failure

### Test 1: verify the fallback chain visually

Temporarily replace the owner-app fallback with a bright debug card containing the numeric `ownerPID`.

If all the current Control Center cards display the same PID, the diagnosis is confirmed immediately.

### Test 2: show window ID under `Item-0`

Render:

```text
Item-0
#12345
```

If each repeated card has a different window ID, enumeration is definitely finding distinct windows while title identity is collapsing.

### Test 3: compare owner PID to source PID after port

Render both in a developer tooltip:

```text
owner:  Control Center / PID 400
source: Dropbox / PID 1234
```

On Tahoe this becomes an excellent sanity check.

### Test 4: remove all image fallbacks

For one build, show only successfully captured images; otherwise display a red generic placeholder. This will tell you the true capture success rate without app-icon/SF-Symbol fallbacks masking failure.

### Test 5: turn Screen Recording permission off intentionally

Verify that:

- your permission state becomes false;
- the UI clearly says captured glyphs are unavailable;
- item identity and names still populate via sourcePID;
- source application icons/placeholders still work.

If names disappear when Screen Recording is disabled, discovery and imagery are still too tightly coupled.

### Test 6: one external third-party item

Choose one unmistakable third-party status item and log only its windows over several refreshes. Observe whether:

- window ID changes;
- raw title changes;
- owner remains Control Center;
- source PID remains stable;
- bounds move when hidden/shown.

### Test 7: kill/restart Control Center during a debug run

After your cache-invalidation logic exists, verify that MenuWrangler recovers without relaunch.

### Test 8: single display first

Disconnect secondary monitors and get one-display behavior solid before debugging display clones.

### Test 9: compare macOS 15 and 26

The same diagnostic JSON on Sequoia and Tahoe should make the architectural change obvious. On macOS 15, owner and source often align; on Tahoe, they diverge.

---

# 38. What I would *not* spend much more time on yet

### More SF Symbol title mappings

They make screenshots look better but do not solve identity. `Item-0` provides no information from which to infer Dropbox, Keyboard Maestro, a window manager, etc.

### Owner-name heuristics

On Tahoe, “Control Center” is a host, not necessarily the source.

### Repeatedly switching window-enumeration APIs

You are already getting a meaningful set of status windows. Refine canonical-window filtering, but do not mistake the missing source identity for missing enumeration.

### Treating `Item-0` as an actual item name

It is an implementation-facing placeholder and may not be unique.

### Making the direct-query UI prettier

First make the model authoritative. Otherwise you will polish a diagnostic workaround that still cannot move items or show Always-Hidden.

---

# 39. Ranked cause list

| Rank | Cause | Confidence | Why |
|---|---|---:|---|
| 1 | Tahoe re-parents menu-bar windows to Control Center, destroying the old owner-PID-as-source assumption | **Very high** | Confirmed by upstream Tahoe work; directly explains why source app identity is missing |
| 2 | `WindowQuery` falls back to the owner application icon, therefore returning Control Center’s icon for every unresolved hosted item | **Effectively confirmed by code** | Exact current fallback chain matches screenshot |
| 3 | Generic `Item-0` titles are WindowServer/Control Center metadata, and the UI displays them verbatim | **Effectively confirmed by code + screenshot** | No local `Item-0` literal is used by the card label path |
| 4 | Actual menu-item capture is failing for many items | **Very high** | Otherwise the owner-app fallback would not be visible |
| 5 | The protocol wrapper around the deprecated `CGImage` window-list initializer is contributing to capture failures | **High-value / plausible** | Exact local pattern was later reverted upstream because it caused failures for some users |
| 6 | Legacy `MenuBarItemInfo(namespace:title)` causes collisions for multiple `com.apple.controlcenter:Item-0` items | **Confirmed design flaw** | Hash key contains only namespace and title; immediate if legacy image cache is used |
| 7 | Screen Recording permission state is stale/false-positive after rebrand | **Plausible** | New bundle ID needs its own TCC grant; current fallback permission check can accept generic nonempty titles |
| 8 | DirectQuery layout bypass has created new functional regressions | **Confirmed** | Always-Hidden hard-coded empty; movement is a stub; simplified partitioning |
| 9 | Multiple displays/spaces/clones are adding duplicate/generic windows | **Plausible** | Direct query asks for all menu-bar windows and globally x-sorts them |
| 10 | NSStatusItem preferred positions reset under the new bundle domain | **Plausible secondary effect** | Explains section-boundary changes after rebrand, not repeated icon identity |
| 11 | Broad layer-25 fallback includes noncanonical windows | **Plausible secondary effect** | Fallback is intentionally coarse |
| 12 | SDK/compiler/runtime differences alone are the root cause | **Low confidence by itself** | There are concrete Tahoe architecture changes that explain the symptom more directly |

---

# 40. A proposed target model

This is illustrative rather than copy/paste production code.

```swift
struct MenuBarWindowSnapshot: Hashable, Sendable {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let ownerBundleID: String?
    let rawTitle: String?
    let bounds: CGRect
    let displayID: CGDirectDisplayID?
}

struct MenuBarItemTag: Hashable, Sendable {
    let sourcePID: pid_t?
    let sourceBundleID: String?
    let role: String?       // stable system/control role where known
    let instanceHint: String?
}

struct ResolvedMenuBarItem: Identifiable, Hashable {
    var id: CGWindowID { snapshot.windowID }

    let snapshot: MenuBarWindowSnapshot
    let tag: MenuBarItemTag
    let displayName: String
    let section: MenuBarSection.Name
}
```

Artwork can then be separate:

```swift
enum MenuBarItemArtwork {
    case captured(CGImage)
    case systemSymbol(String)
    case sourceApplicationIcon(NSImage)
    case placeholder
}
```

This avoids making “can I screenshot it?” a prerequisite for “does the item exist?”

---

# 41. Proposed artwork resolver order

After source identity exists, I would use:

```text
1. successfully captured real status-item image
2. known semantic system-item symbol, where a stable system tag exists
3. source application icon
4. neutral placeholder
```

Do **not** use:

```text
Control Center owner app icon as a fallback for unknown re-parented items
```

and do not use raw generic title text as the primary identity.

---

# 42. Proposed naming resolver order

```text
MenuWrangler control role
    ↓
known system tag display name
    ↓
source app + semantic item title
    ↓
source app localized name
    ↓
semantic raw title
    ↓
“Menu Bar Item”
```

For Debug builds, append metadata in a tooltip rather than making the user-facing title ugly:

```text
Window 12345
owner Control Center (PID 400)
source Dropbox (PID 1234)
raw title Item-0
capture failed: transparent
```

---

# 43. Recommended section-classification model

Use MenuWrangler’s own control items as actual boundaries.

With HItem and AHItem both enabled, conceptually the sections are defined by geometry around those boundaries, not by the source application name of arbitrary items.

Reuse the project’s `Predicates.sectionPredicates(...)` logic after updating its inputs for Tahoe control-item mapping.

Do not keep a second, separate x-splitting implementation in SwiftUI unless it is only a diagnostics mode.

---

# 44. Permissions should affect artwork, not existence

A robust Menu Bar Layout should ideally behave this way:

### With Screen Recording permission

- item model is populated;
- real menu glyphs are captured where technically possible;
- source app icon fallback exists where capture fails.

### Without Screen Recording permission

- item model is still populated;
- names/sections still work;
- source application icons or placeholders appear;
- UI clearly explains that exact menu-bar glyph previews require permission.

That makes permission bugs far less catastrophic.

---

# 45. Suggested diagnostic service API

Instead of sprinkling UserDefaults keys across the view, create one debug snapshot object that an AI coding agent or human can inspect consistently.

```swift
struct MenuBarDiagnostics: Codable {
    let generatedAt: Date
    let osVersion: String
    let appVersion: String
    let bundleID: String
    let screenCapturePreflight: Bool
    let accessibilityTrusted: Bool
    let displays: [DisplayDiagnostic]
    let windows: [MenuBarWindowDiagnostic]
}
```

For each window include:

```text
window ID
owner PID/name/bundle
source PID/name/bundle
raw title
resolved tag/name
frame from metadata
frame from CGS
space IDs
display ID
on-screen state
section
capture method used
capture image dimensions
nontransparent-pixel percentage
artwork fallback kind
```

This would be extremely valuable when handing the next iteration to Kilo Code or Antigravity. Instead of an LLM guessing from a screenshot, it can compare structured before/after data.

---

# 46. Test matrix before declaring the fix complete

| Dimension | Cases |
|---|---|
| macOS | 14.x Sonoma, 15.x Sequoia, 26.x Tahoe |
| Display count | 1, 2+ |
| Mac display | notched, non-notched |
| Separate Spaces | enabled, disabled |
| Screen Recording | granted, denied, revoked while running |
| Accessibility | granted, denied |
| Menu bar auto-hide | never, automatic |
| Always-Hidden | disabled, enabled |
| Signing | normal Apple Development build, Release/Developer ID if applicable, ad-hoc if you intentionally support it |
| Lifecycle | clean launch, Control Center restart, display plug/unplug, Space switch, wake from sleep |
| Item mix | Apple system items, standard third-party NSStatusItems, multiple items from one app |

Success criteria should be defined separately for:

```text
discovery
identity
section assignment
artwork
movement
refresh/recovery
```

That prevents “icons appeared once” from being mistaken for a complete fix.

---

# 47. Upstream references worth studying

All references are in the public `jordanbaird/Ice` GitHub repository.

- **PR #940 — `fix: merge macOS 26 compatibility fixes`**  
  Broad Tahoe migration. Includes `MenuBarItemService`, `SourcePIDCache`, private API fallbacks, item handling/cache work, and macOS 26 UI changes.

- **Commit `ad86802` — `macOS 26: Reworks all the way down`**  
  Important architectural note that menu-bar items are owned by Control Center on macOS 26 and the old identity mechanism is inadequate.

- **Commit `38d344f` — `Update screen capture`**  
  Reverts the protocol/static-method indirection around the `CGImage` initializer because the indirection appeared to cause screen capture failures for some users. Your uploaded source still has the pre-fix pattern.

- **PR #903 — `Fix menu bar item identification and navigation on macOS Tahoe`**  
  Documents Control Center ownership/nil-title problems, Tahoe control-item matching, source-PID integration, and title overrides.

- **PR #922 — `Fix "Unable to display menu bar items" on macOS 26.4`**  
  Adds a fallback when the private active-menu-bar display identifier returns nil on 26.4.1. Also contains useful notes about frame fallback and source-PID/cache behavior from combined community fixes.

- **PR #950 — `fix(xpc): make MenuBarItemService work for ad-hoc-signed builds on macOS 26`**  
  Explains why `.isFromSameTeam()` can reject an XPC connection in ad-hoc builds and leave `sourcePID` unavailable.

- **Discussion #588 — Ice 0.11.13 macOS Tahoe Beta 1**  
  Explicitly says Apple made significant menu-bar changes and notes incorrect menu-item names/app icons as a known Tahoe issue.

- **Issue #777 — Ice App Freezes During Screen Capture Operations**  
  Useful warning about synchronous window capture blocking on Tahoe.

The existence of multiple upstream Tahoe layout bugs is important context: **the rebrand is not the sole explanation.** The bundle-ID change can affect permissions/defaults, but Ice itself required substantial architectural changes for macOS 26.

---

# 48. Local source references from the uploaded snapshot

These are the files I would keep open while implementing the repair:

```text
Ice/UI/LayoutBar/WindowQuery.swift
Ice/UI/LayoutBar/LayoutItemInfo.swift
Ice/UI/LayoutBar/LayoutItemView.swift
Ice/UI/LayoutBar/DirectQueryLayoutBar.swift
Ice/Settings/SettingsPanes/MenuBarLayoutSettingsPane.swift

Ice/MenuBar/MenuBarItems/MenuBarItem.swift
Ice/MenuBar/MenuBarItems/MenuBarItemInfo.swift
Ice/MenuBar/MenuBarItems/MenuBarItemManager.swift
Ice/MenuBar/MenuBarItems/MenuBarItemImageCache.swift

Ice/MenuBar/ControlItem/ControlItem.swift
Ice/Utilities/Predicates.swift
Ice/Utilities/WindowInfo.swift
Ice/Utilities/ScreenCapture.swift
Ice/Bridging/Bridging.swift

Ice/Utilities/StatusItemDefaults.swift
Ice/Utilities/MigrationManager.swift
scripts/build.sh
Ice/Ice.entitlements
Ice.xcodeproj/project.pbxproj
```

Particularly important exact observations from the uploaded source:

```text
WindowQuery.swift:
  - discovery uses Bridging.getWindowList(.menuBarItems)
  - capture failure falls back to owner PID application icon
  - owner-icon cache key is PID

LayoutItemView.swift:
  - raw nonempty title is displayed verbatim

LayoutItemInfo.swift:
  - Identifiable ID is a new UUID every refresh

DirectQueryLayoutBar.swift:
  - alwaysHidden is hard-coded []
  - drag/drop moveItem is only a print + refresh stub
  - only one delimiter is used

MenuBarItemInfo.swift:
  - identity/hash = namespace + title

MenuBarItem.swift:
  - namespace derives from the owning application bundle ID

MenuBarItemImageCache.swift:
  - image dictionary is keyed by MenuBarItemInfo

ScreenCapture.swift:
  - still uses the protocol wrapper later reverted upstream
  - allocated window pointer is not deallocated

Bridging.swift:
  - primary discovery uses CGSGetProcessMenuBarWindowList
  - fallback scans all windows for status/main-menu layer

project.pbxproj:
  - product bundle ID is com.jwink75.MenuWrangler
  - deployment target remains macOS 14.0
  - marketing version is still 0.11.12
```

---

# 49. My recommended “first working milestone”

Do not define the first milestone as “every card has the exact correct glyph.” That depends on several fragile capture details.

A much better first milestone is:

> **Every currently running menu-bar item appears exactly once in the correct section, with the correct source application/name, even if some items temporarily use an application icon or neutral placeholder instead of the exact menu-bar glyph.**

Once that is reliable, exact pixel/icon capture is a contained second problem.

This ordering will keep Kilo Code and Antigravity from repeatedly trying to solve identity by changing graphics fallbacks.

---

# 50. Short priority checklist

**Highest priority:**

1. Prove repeated cards have distinct window IDs but the same Control Center owner PID.
2. Replace the protocol-wrapped `CGImage` initializer with the direct call from upstream commit `38d344f`.
3. Stop using the Control Center owner app icon for unresolved Tahoe items.
4. Port the upstream source-PID/Tahoe item-tag architecture rather than expanding title heuristics.
5. Replace `namespace + title` as the unique image/item cache key on macOS 26.

**Next:**

6. Rebuild production layout UI on the authoritative item manager rather than the current direct-query workaround.
7. Restore true HItem/AHItem partitioning and real drag movement.
8. Make image capture asynchronous and fix pointer/capture lifetime issues.
9. Cleanly reset/regrant TCC permissions for `com.jwink75.MenuWrangler` and keep signing identity stable.
10. Port 26.4 display-ID and relevant cache/frame fallbacks from the newer upstream branch.

**Then harden:**

11. multi-display and Spaces behavior;
12. Control Center restart recovery;
13. failure TTLs and cache invalidation;
14. exact glyph capture quality;
15. UI polish.

---

## Bottom line

I would stop treating `Item-0` as an icon-recognition problem. The current behavior is the visible consequence of an **identity-model mismatch introduced by Tahoe**:

```text
real third-party status item
        ↓
Control Center-hosted WindowServer window
        ↓
ownerPID incorrectly treated as sourcePID
        ↓
generic title Item-0
        ↓
capture fails
        ↓
owner app icon fallback
        ↓
Control Center icon repeated for every item
```

Repair the **source identity** first, repair the known capture regression second, and make artwork a best-effort layer on top of a correct item model. That should turn this from an endless sequence of special cases into a tractable port of work that the upstream Ice project has already spent considerable effort solving.
