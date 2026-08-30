---
description: Work on the Menu Bar Layout feature
---
# Menu Bar Layout Development

Work on the Menu Bar Layout feature — the settings pane that shows menu bar items for rearrangement.

## Context
The Menu Bar Layout allows users to drag menu bar items between three sections:
- **Visible**: Items always shown
- **Hidden**: Items shown on hover/click
- **Always-Hidden**: Items only shown when explicitly revealed

## Documentation
- `layout_bars.md` — Original problem analysis and fixes
- `new_menu_bar_layout.md` — Direct Query approach documentation

## Key Files
- `Ice/Settings/SettingsPanes/MenuBarLayoutSettingsPane.swift` — Main settings view
- `Ice/UI/LayoutBar/DirectQueryLayoutBar.swift` — New layout bar implementation
- `Ice/UI/LayoutBar/WindowQuery.swift` — Window server query utility
- `Ice/UI/LayoutBar/LayoutItemInfo.swift` — Item data model
- `Ice/UI/LayoutBar/LayoutItemView.swift` — Item display view

## Architecture
The Direct Query approach bypasses the complex cache pipeline:
1. Query `CGWindowListCopyWindowInfo` directly on view appear
2. Filter for layer 25 (menu bar windows)
3. Capture images with `CGWindowListCreateImage`
4. Display immediately in SwiftUI

## Debugging
- Check Console.app for `LayoutBar` log messages
- Use Logger.layoutBar.debug for diagnostics
- Verify window discovery returns items

## Common Issues
- Items not appearing: Check if window query returns results
- Missing images: Verify screen recording permissions
- Gatekeeper errors: Use `./scripts/build.sh` to properly sign
