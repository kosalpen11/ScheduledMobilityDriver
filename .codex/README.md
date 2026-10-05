# Codex Workspace

Repo-local context for Codex agents working on the scheduled-mobility iOS driver app.

Start with `../codex.md`, then read `../README.md` before changing code.

Key expectations:

- Preserve the module boundaries in `DriverModules/Package.swift`.
- Keep the app target at iOS 15.0 or later.
- Prefer small, cohesive Swift types and explicit dependencies.
- Verify with `xcodebuild` when changing app or package code.
