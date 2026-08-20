# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.1.0] - 2026-08-15

### Added

- Multi-monitor scenes that save every detected display's active/inactive state
- Saved resolution, refresh rate, color depth, and DPI scale for active displays in each scene
- GUI scene manager for save, overwrite, apply, and delete operations
- CLI commands: `scene-save`, `scene-apply`, `scenes`, and `scene-delete`
- Duplicate scene-configuration detection

### Safety

- Atomic final-topology planning instead of sequentially disconnecting displays
- Last-display guard for scene files and runtime plans
- Physical target identity mapping with MonitorId fallback after reboot or driver re-enumeration
- Missing-hardware and clone-source validation before any display write
- Whole-scene rollback of the original topology and active display mode snapshots
- Safe mocked tests for scene persistence, topology planning, hardware mismatch, application, and rollback

### Changed

- GUI and documentation version updated to 1.1.0
- User data now also includes `%USERPROFILE%\.monitormanager\scenes.json`
- GUI workers and newly generated desktop shortcuts now prefer PowerShell 7 (`pwsh.exe`) and fall back to Windows PowerShell 5.1
- CI validates the full safe suite under both PowerShell 7 and Windows PowerShell 5.1

### Fixed

- Existing desktop shortcuts can now be atomically replaced on Windows by using a real backup path with `File.Replace`
- Multi-monitor scene dialogs now use a DPI-aware responsive layout with clearer labels and spacing

## [1.0.0] - 2026-07-21

### Added

#### GUI
- Native WinForms GUI with dark sidebar + light main area design
- Per-monitor card display with connection state, resolution, refresh rate, and DPI
- Template card grid with mini monitor previews (gradient backgrounds)
- One-click template application (double-click a template card)
- Add template dialog with current-config snapshot
- Monitor connect/disconnect via power button (⏻) in sidebar
- Custom monitor naming via rename button (✎)
- Selected state with multi-feedback (blue left border, outline, badge, "已选" label)
- Responsive layout with DPI-aware scaling and resize debounce
- Background subprocess for apply/power operations (non-blocking UI)
- Status bar with active monitor count, primary display info, and offline group count

#### Template Management
- Per-monitor template grouping by monitor device ID
- Template CRUD: save, apply, view details, delete
- Duplicate parameter detection (refuses identical configs)
- Automatic template name selection (matches current display params)
- Legacy format auto-migration (old `[{monitors: [...]}]` → per-monitor groups)
- Data integrity validation on load and save
- Atomic file writes (temp file + rename) to prevent corruption
- Corrupted file detection with automatic backup (`.corrupted.*.bak`)
- Named mutex serialization for multi-instance safety

#### Monitor Identification
- DisplayConfig API (`QueryDisplayConfig`) for precise active path enumeration
- Per-target physical monitor identity via `DisplayConfigGetDeviceInfo` (friendly name + PnP device path)
- Hardware ID matching between target device path and `EnumDisplayDevices` for reliable MonitorId
- Connected-but-inactive monitors detection (all paths scan)
- Fallback to `System.Windows.Forms.Screen` when DisplayConfig is unavailable
- Primary monitor detection via desktop origin (DisplayConfig source mode position)

#### Display Mode Operations
- Resolution, refresh rate, and color depth switching via `ChangeDisplaySettingsEx`
- Per-monitor DPI scaling via `DisplayConfigGetDeviceInfo` / `DisplayConfigSetDeviceInfo` (reverse-engineered type values)
- Staged mode change: write (`CDS_UPDATEREGISTRY | CDS_NORESET`) → commit (`ChangeDisplaySettingsEx(null)`)
- Post-commit readback verification (multiple retries)
- DPI offset calculation from system scale table (100–500, 12 standard tiers)

#### Connect / Disconnect
- Single monitor connect/disconnect from Windows desktop via `SetDisplayConfig`
- Free source detection (prevents clone-group conflicts)
- Last-active-monitor safety guard (refuses to disconnect the only active display)
- Primary monitor migration warning dialog
- Path-only topology submission with database fallback (validate-existing → best-mode)
- Post-operation power state verification through physical target key (not MonitorId alias)

#### Safe Rollback
- Full DEVMODE snapshot before every mode change
- Auto-restore on: commit failure, mode verification mismatch, DPI application failure
- Rollback verification with multiple polling retries
- Rollback itself verified; reports to user if unverified

#### CLI
- `gui` — Launch GUI (default)
- `list` — Enumerate all monitors with details
- `save <spec> <name>` — Save current config as template
- `apply <spec> <name>` — Apply template to monitor
- `disconnect <spec>` / `connect <spec>` — Connect/disconnect monitor
- `templates [spec]` — List templates (optionally filtered)
- `show <spec> <name>` — View template details
- `delete <spec> <name>` — Delete template
- `dpi [spec]` — Set DPI scaling interactively (5 user tiers: 100/125/150/175/200)
- `menu` — Interactive template selection menu
- `diagnose` — Diagnostic report (display state, template comparison, optional refresh rate test)
- `shortcut` — Create desktop shortcut with custom icon
- `help` — Print usage help
- Structured exit codes: 0=success, 1=failure, 2=partial success/usage error
- Base64-encoded worker result markers for reliable GUI background process communication

#### Testing
- Syntax check (`check_syntax.ps1`) — PowerShell AST parse validation
- Safe test suite (`safe_tests.ps1`) — comprehensive unit tests without touching real displays
- ABI struct size validation (6 Win32 structs)
- Template save/duplicate/corruption/invalid-value/legacy-migration tests
- Apply rollback tests: commit failure, mode mismatch, DPI failure
- DPI set/verify/rollback tests
- Monitor power tests: last-active guard, disconnect, connect, free-source detection, physical identity verification
- Topology flag sequence validation (database path vs best-mode fallback)
- `GetNewClosure` safety check (no `$script:` variable access)
- All test side effects isolated to temp directories, cleaned up after run
