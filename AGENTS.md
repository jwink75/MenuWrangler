# Agent Collaboration Guidelines (Antigravity Agent + Antigravity IDE Kilo Code)

## Roles & Collaboration Model
This project is developed in tandem by two complementary agent workflows:
1. **Antigravity (AG - Standalone Development App)**:
   - Manages build orchestration, deep code signing (`Apple Development`), Gatekeeper quarantine removal, running/debugging processes, crash log analysis, and Git/GitHub commits & pushes.
   - Maintains system architectures, bridging shims, and multi-file refactors.
   - Documents implementation plans and progress in markdown files (e.g., `layout_bars.md`, `new_menu_bar_layout.md`).
2. **Kilo Code (Antigravity IDE Assistant - this tool)**:
   - Focuses on inline code generation, SwiftUI view implementations, and IDE-level feature writing.
   - Implements specific fixes and features as directed by the user or AG.
   - Creates and modifies source files directly in the workspace.

---

## Collaboration Protocol

### Communication
- **AG documents plans**: When AG proposes changes, it creates/updates markdown documentation in the repo (e.g., `layout_bars.md`, `new_menu_bar_layout.md`).
- **Kilo implements**: Kilo reads these documents and implements the described changes.
- **Status updates**: Both agents update the "Implementation Status Summary" in shared documents to reflect current state.

### File Ownership
- **AG owns**: Build scripts (`scripts/build.sh`), documentation (`*.md`), project configuration, and high-level architecture decisions.
- **Kilo owns**: Inline code changes, bug fixes, and feature implementation within source files.
- **Shared**: Both agents may modify any file, but should communicate changes via commit messages and document updates.

### Workflow
1. AG identifies issues and documents them in markdown files
2. User reviews and approves proposed fixes
3. Kilo implements the fixes in source code
4. AG builds, signs, and deploys via `./scripts/build.sh`
5. Both agents verify and update status documentation

---

## Shared Development Practices
- **Always preserve build script workflow**: Execute `./scripts/build.sh` to compile, sign, and launch cleanly.
- **Title-independent status item discovery**: Modern macOS (14/15/26) anonymizes window titles for non-system apps. Never rely on `item.title != nil` or string matches for critical control logic; use window IDs, process IDs, and geometric coordinates.
- **Resilient fallback rendering**: Always provide `NSRunningApplication.icon` or SF Symbols when `CGWindowListCreateImage` returns `nil` or transparent buffers.
- **Section partitioning**: Menu bar items must be partitioned spatially relative to the MenuWrangler delimiter (`...` / `HItem`) coordinates.
- **Document major changes**: When implementing significant features or fixes, update the relevant markdown documentation to reflect the current state.
