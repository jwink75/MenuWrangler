# Agent Collaboration Guidelines (Antigravity Agent + Antigravity IDE Kilo Code)

## Roles & Collaboration Model
This project is developed in tandem by two complementary agent workflows:
1. **Antigravity (Pair Programming / Compiler / Build & Sign Agent)**:
   - Manages build orchestration, deep code signing (`Apple Development`), Gatekeeper quarantine removal, running/debugging processes, crash log analysis, and Git/GitHub commits & pushes.
   - Maintains system architectures, bridging shims, and multi-file refactors.
2. **Kilo Code (Antigravity IDE Assistant)**:
   - Focuses on inline code generation, SwiftUI view implementations, and IDE-level feature writing.

---

## Shared Development Practices
- **Always preserve build script workflow**: Execute `./scripts/build.sh` to compile, sign, and launch cleanly.
- **Title-independent status item discovery**: Modern macOS (14/15/26) anonymizes window titles for non-system apps. Never rely on `item.title != nil` or string matches for critical control logic; use window IDs, process IDs, and geometric coordinates.
- **Resilient fallback rendering**: Always provide `NSRunningApplication.icon` or SF Symbols when `CGWindowListCreateImage` returns `nil` or transparent buffers.
- **Section partitioning**: Menu bar items must be partitioned spatially relative to the MenuWrangler delimiter (`...` / `HItem`) coordinates.
