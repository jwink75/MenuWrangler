# Menu Bar Folders - Implementation Plan

## Goal

Extend menu bar layout to support multiple user-defined "folders" alongside the existing Visible/Hidden/Always-Hidden sections. Each folder acts as a group of items that appear as a horizontal section in the menu bar (similar to how Ice currently handles the "hidden" section).

**Layout in actual menu bar:**
```
[Visible Items] [Folder 1] [Folder 2] ... [Ice Bar] [Control Center] [Clock]
```

**Layout in settings pane:**
- Visible section (horizontal bar)
- Folder 1 section (horizontal bar, renameable)
- Folder 2 section (horizontal bar, renameable)
- ... (more folders)
- Hidden section (horizontal bar)
- Always-Hidden section (horizontal bar)
- "New Folder" button

## Key Design Decisions

1. **Folders map to actual menu bar positions**: Each folder is represented by a ControlItem (status item) in the menu bar, placed between Visible items and Ice Bar.
2. **Folder items**: Menu bar items assigned to a folder are positioned near that folder's ControlItem.
3. **Folder creation/deletion**: Creates/removes ControlItem status items dynamically.
4. **Rename**: Updates the ControlItem's label or icon name.

## Architecture

### Current State
- `MenuBarSection.Name` enum: `.visible`, `.hidden`, `.alwaysHidden`
- `ControlItem.Identifier`: `.iceIcon`, `.hidden`, `.alwaysHidden` (creates `SItem`, `HItem`, `AHItem` status items)
- `MenuBarSection` wraps a `ControlItem` and manages its visibility
- Items are positioned using `MenuBarItemManager.move(item:to:)` which calls macOS Accessibility framework

### New Architecture
1. **Extend `MenuBarSection.Name`**: Add `.folder(String)` case for named folders
   - `CaseIterable` won't work with associated values, so we need a custom approach
   - Use a computed `allNames` that combines static cases with dynamic folder names

2. **Extend `ControlItem.Identifier`**: Add `.folder(String)` case
   - Each folder gets a unique status item with a name/icon

3. **FolderManager** (`MenuBarFolderManager`):
   - Persists folder names and item assignments
   - Creates/removes ControlItems dynamically
   - Updates when app launches or settings change

4. **Update `MenuBarSection`**: 
   - Support `.folder(name)` case with a ControlItem
   - Manage visibility of folder items (show when mouse hovers the folder ControlItem)

5. **Update `MenuBarItemManager`**:
   - Extend `ItemCache` to handle folder sections
   - Update `move(item:to:)` to position relative to folder ControlItems

### Steps

#### 1. Folder Persistence (`MenuBarFolderManager.swift`)
- Create `MenuBarFolderManager: ObservableObject`
- Store: folder names array + item-to-folder mapping (windowID -> folder name)
- Methods: `createFolder(name:)`, `deleteFolder(name:)`, `addItem(windowID:to:)`, `removeItem(windowID:)`
- Published properties for reactive UI

#### 2. Extend MenuBarSection.Name
- Add `.folder(String)` case
- Implement `allCases` replacement: `MenuBarFolderManager.shared.allSectionNames`
- Add `isFolder` property
- Update `displayString` to return the folder name

#### 3. Extend ControlItem for Folders
- Add `.folder(String)` identifier case
- Create ControlItem instances dynamically for each folder
- Set unique identifiers (e.g., `Folder:Work`)
- Icon: Allow custom icon selection or use SF Symbol
- Position: After Visible section, before Ice Bar

#### 4. Update MenuBarManager
- Dynamically create/delete `MenuBarSection` instances for folders
- Update `sections` array when folders change
- Reorder sections: visible → folders → iceBar → hidden → controlCenter

#### 5. Update MenuBarItemManager
- `ItemCache` supports folder sections
- `move(item:to:)` handles folder positioning
- Items in a folder are positioned near their folder's ControlItem

#### 6. Settings Pane Updates
- Show all folder sections with `DirectQueryLayoutBar`
- Add "New Folder" button (renameable via inline editing)
- Show folder icon selection (SF Symbol or image picker)
- Drag between any sections updates folder assignment + triggers OS position update

#### 7. Menu Bar Interaction
- Folders act like Ice's hidden section but with separate groups
- Moving mouse to a folder's ControlItem shows that folder's items
- Items stay in their assigned folder until reassigned

## Data Flow

1. User creates folder "Work" in settings
2. `MenuBarFolderManager` saves folder name, creates `MenuBarSection(name: .folder("Work"))`
3. `MenuBarManager` creates a `ControlItem` for "Work" folder, positions it after Visible items
4. User drags Dropbox icon into "Work" folder bar in settings
5. `LayoutItemInfo` assignment updates via `MenuBarFolderManager`
6. `DirectQueryLayoutBar` refreshes, item disappears from source section
7. `MenuBarItemManager` moves the OS-level window to near Work folder's ControlItem
8. User sees "Work" button in actual menu bar; clicking it reveals grouped items

## Risks & Mitigations

1. **Status item limit**: macOS limits total status items. Each folder adds one more. Mitigation: Limit folders to reasonable number (e.g., 10).

2. **Positioning conflicts**: Multiple folders need precise positioning. Mitigation: Use ControlItem positions as anchors, position items relative to their anchor.

3. **Settings pane performance**: Refreshing all sections on each change. Mitigation: Keep existing debounce logic, add folder notifications.

4. **Migration**: Existing Ice config shouldn't break. Mitigation: Folders are additional, not replacement.

## Out of Scope
- Changing actual Control Center / system item behavior
- Custom folder icons (use SF Symbols initially, image picker is future enhancement)
- Nested folders

## Validation
1. Create folder, drag items in/out, verify they move in actual menu bar
2. Rename folder, verify ControlItem updates
3. Delete folder, verify items return to Hidden section
4. App restart, verify folder state persists
5. Verify menu bar layout order: Visible → Folders → IceBar → ControlCenter
