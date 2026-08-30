# New Menu Bar Layout: Direct Query Approach

## Problem Statement

The current Menu Bar Layout implementation uses a complex multi-stage pipeline with too many failure points:

```
Window Discovery → Item Cache → Section Filter → View Creation → View Layout → Drawing
     (Bridging)    (ItemCache)   (Predicates)   (ItemView)     (Container)    (CoreGraphics)
```

Items are silently lost at any stage due to:
- Async guards returning early
- Cache population failures
- Combine subscription timing issues
- Zero-width frame calculations
- Image capture failures

## Proposed Solution: Self-Contained Direct Query Layout Bar

Create a new `DirectQueryLayoutBar` that queries the window server directly when the view appears, bypassing the entire cache pipeline.

## Architecture

### Data Model

```swift
struct LayoutItemInfo: Identifiable {
    let id = UUID()
    let windowID: CGWindowID
    let image: NSImage
    let ownerPID: pid_t
    let ownerName: String
    let frame: CGRect
    var isMovable: Bool { true }
}
```

### View Structure

```
DirectQueryLayoutBar (SwiftUI)
├── ScrollView(.horizontal)
│   ├── HStack
│   │   ├── LayoutItemView (per item)
│   │   ├── LayoutItemView
│   │   └── ...
├── .onAppear → refreshItems()
└── .onReceive(didBecomeActive) → refreshItems()
```

### Key Components

1. **DirectQueryLayoutBar** - Main SwiftUI view
2. **LayoutItemInfo** - Simple data model for display items
3. **LayoutItemView** - NSViewRepresentable for each item with drag support
4. **WindowQuery** - Utility for direct window server queries

### Implementation Plan

#### Step 1: Create WindowQuery Utility

```swift
enum WindowQuery {
    static func getMenuBarWindows() -> [LayoutItemInfo] {
        guard let windowList = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        
        return windowList.compactMap { info in
            guard
                let layer = info[kCGWindowLayer as String] as? Int,
                layer == 25,
                let windowID = info[kCGWindowNumber as String] as? CGWindowID,
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
```

#### Step 2: Create LayoutItemInfo Model

```swift
import Cocoa

struct LayoutItemInfo: Identifiable, Hashable {
    let id = UUID()
    let windowID: CGWindowID
    let image: NSImage
    let ownerPID: pid_t
    let ownerName: String
    let frame: CGRect
    
    var isMovable: Bool { true }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(windowID)
    }
    
    static func == (lhs: LayoutItemInfo, rhs: LayoutItemInfo) -> Bool {
        lhs.windowID == rhs.windowID
    }
}
```

#### Step 3: Create LayoutItemView

```swift
import SwiftUI

struct LayoutItemView: View {
    let item: LayoutItemInfo
    
    var body: some View {
        Image(nsImage: item.image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 24, height: 24)
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.1))
            )
            .help(item.ownerName)
    }
}
```

#### Step 4: Create DirectQueryLayoutBar

```swift
import SwiftUI

struct DirectQueryLayoutBar: View {
    let section: MenuBarSection
    @State private var items: [LayoutItemInfo] = []
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    LayoutItemView(item: item)
                }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 32, alignment: .leading)
        }
        .frame(height: 50)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(.quaternary.opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(.quaternary, lineWidth: 0.5)
        )
        .onAppear {
            refreshItems()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshItems()
        }
    }
    
    private func refreshItems() {
        let allWindows = WindowQuery.getMenuBarWindows()
        
        // Filter for this section based on position
        items = filterWindowsForSection(allWindows)
    }
    
    private func filterWindowsForSection(_ windows: [LayoutItemInfo]) -> [LayoutItemInfo] {
        // For now, return all windows - section filtering can be added later
        // based on delimiter positions
        windows.filter { window in
            // Skip Ice's own control items
            window.ownerName != "MenuWrangler" && window.ownerName != "Ice"
        }
    }
}
```

#### Step 5: Update MenuBarLayoutSettingsPane

```swift
@ViewBuilder
private func layoutBar(for section: MenuBarSection.Name) -> some View {
    if let section = appState.menuBarManager.section(withName: section),
       section.isEnabled {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(section.name.displayString) Section")
                .font(.system(size: 14))
                .padding(.leading, 2)
            
            DirectQueryLayoutBar(section: section)
        }
    }
}
```

## Migration Strategy

1. Create new files alongside existing ones
2. Add feature flag to toggle between old and new implementation
3. Test new implementation thoroughly
4. Remove old implementation once validated

## Files to Create

| File | Purpose |
|------|---------|
| `Ice/UI/LayoutBar/WindowQuery.swift` | Direct window server query utility |
| `Ice/UI/LayoutBar/LayoutItemInfo.swift` | Simple data model |
| `Ice/UI/LayoutBar/LayoutItemView.swift` | Individual item view |
| `Ice/UI/LayoutBar/DirectQueryLayoutBar.swift` | Main layout bar view |

## Files to Modify

| File | Change |
|------|--------|
| `MenuBarLayoutSettingsPane.swift` | Use `DirectQueryLayoutBar` instead of `LayoutBar` |

## Advantages

- **No cache dependency** - queries directly on appear
- **No Combine subscriptions** - simpler lifecycle
- **No async guards** - synchronous query
- **Immediate feedback** - items show up instantly
- **Easier to debug** - single function to trace
- **Fewer files** - replaces complex container/padding/scroll hierarchy
- **Pure SwiftUI** - no NSViewRepresentable needed for most parts |

## Future Enhancements

1. Add section filtering based on delimiter positions
2. Add drag-and-drop support for rearranging items
3. Add context menu for item options
4. Integrate with existing move/click functionality
