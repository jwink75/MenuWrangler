# Agent Collaboration Guidelines (Antigravity Agent + Antigravity IDE Kilo Code)

## Roles & Collaboration Model
This project is developed as an **equal peer partnership** between two complementary AI workflows:
1. **Antigravity (Standalone Development Agent)** & **Kilo Code (IDE Assistant)**:
   - Both agents operate as **full equal co-developers**.
   - Both agents have full capability and authority to write code, design SwiftUI views, implement low-level system integrations, diagnose system bugs, maintain build orchestration, and write documentation.
   - Either agent can propose plans, implement source code directly, perform refactors, run `./scripts/build.sh`, and commit to Git.
   - Using both agents provides independent perspectives, second opinions, and diverse problem-solving approaches.

---

## Collaboration Protocol

### Communication & Continuity
- **Shared documentation**: Both agents maintain and read project documentation (e.g., `layout_bars.md`, `new_menu_bar_layout.md`, `MENU LAYOUT TROUBLESHOOTING/`).
- **Status updates**: Both agents update status documentation and commit messages so work can seamlessly hand off between them at any time.

### Shared Practices
- **Always preserve build script workflow**: Execute `./scripts/build.sh` to compile with Xcode, sign with Apple Development identity (`5K6TS92SYQ`), clear Gatekeeper quarantine flags, and deploy cleanly.
- **Title-independent status item discovery**: Modern macOS (14/15/26) anonymizes window titles for non-system apps. Never rely on `item.title != nil` or string matches for critical control logic; use window IDs, geometric coordinates, and client process tracking.
- **Resilient fallback rendering**: Always provide `NSRunningApplication.icon` or SF Symbols when screen capture returns `nil` or transparent buffers.
- **Section partitioning**: Menu bar items must be partitioned spatially relative to delimiter coordinates.
