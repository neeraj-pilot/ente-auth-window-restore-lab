# Auth #1883: Windows window restoration lab

An isolated Flutter Windows sample for [Ente Auth #1883](https://github.com/ente/ente/issues/1883): window position resets on launch, including reports of opening under a top taskbar or on the wrong monitor. This repository contains experiments only. It neither builds nor changes production Auth and never opens Auth's data or preferences.

## What is compared

- **baseline** models Auth's size-only restoration, with the same `window_manager` 0.5.1, 800×1200 logical-pixel defaults, 8192 maximum dimensions, and native launch origin `(70, 70)`. It does not persist position.
- **fixed** stores the normal window's logical size and offset within the selected monitor's work area. It selects the saved monitor when available, falls back to the primary monitor when absent, and fits the window inside the work area. Maximized captures use Windows' normal window placement, converted to screen coordinates; minimized captures preserve the last saved state.

The baseline is a focused policy reproduction, **not an exact Auth executable**. Both modes use isolated JSON files and explicit test flushes instead of Auth's SharedPreferences and lifecycle. Baseline maximize/minimize observations therefore are not proof of those additional bugs in Auth.

Reference Auth source at `3d5e567389670e6a1c3364515544ddec5a814b86`:

- [Window preferences and resize listeners](https://github.com/ente/ente/blob/3d5e567389670e6a1c3364515544ddec5a814b86/mobile/apps/auth/lib/services/window_listener_service.dart)
- [Startup restoration](https://github.com/ente/ente/blob/3d5e567389670e6a1c3364515544ddec5a814b86/mobile/apps/auth/lib/main.dart)
- [Native launch origin](https://github.com/ente/ente/blob/3d5e567389670e6a1c3364515544ddec5a814b86/mobile/apps/auth/windows/runner/main.cpp)

## Implementation boundaries

`lib/placement.dart` contains the geometry/state policy. `windows/runner/window_geometry.*` owns typed Win32 operations without Flutter dependencies; the method channel only transports the snapshot and test commands. Snapshots include current and normal outer-window rectangles, monitor work areas, DPI, and maximize/minimize state. The runner declares `PerMonitorV2` DPI awareness. The native module links the Windows system library `shcore.lib`.

Physical screen coordinates are used at the Win32 boundary. Saved offsets and sizes are relative logical coordinates within one monitor's work area. This avoids comparing global screen coordinates divided by different monitors' scale factors. Moving to this approach in Auth would require a Windows bridge and a preference migration; this sample does not establish that this is the best production design.

The candidate serializes writes, ignores minimized captures, reads native normal bounds when maximized, and begins listening after restoration. A 150 ms debounce reduces event writes; close flushes pending state. Failed writes are reported and do not poison subsequent saves; closing still destroys the window if its flush fails. Run one process per mode/state directory at a time.

## Run on Windows

Use Flutter **3.47.2 / Dart 3.13.2** and the Windows C++ toolchain required by Flutter.

```powershell
flutter pub get --enforce-lockfile
flutter analyze --no-pub
flutter test --no-pub
flutter build windows --release --no-pub
./scripts/windows-check.ps1
```

For interactive testing, extract the entire `windows-sample.zip` workflow artifact, then launch one mode at a time:

```powershell
./auth_window_restore_lab.exe --mode=baseline
./auth_window_restore_lab.exe --mode=fixed
```

State is isolated under `%LOCALAPPDATA%/AuthWindowRestoreLab`, in separate `baseline.json` and `fixed.json` files. To start fresh, close the sample and remove only these sample files. A `--state-dir=<directory>` argument selects a separate test directory.

Move/resize, close, and reopen in each mode. Also try maximizing, closing, reopening, then restoring. The candidate should retain its normal geometry.

## Test-only GitHub Windows workflow

`.github/workflows/windows-lab.yml` runs only on manual `workflow_dispatch`, using `windows-2022`, read-only repository permissions, no secrets, no installer, and no deployment or release step. It checks the SDK archive SHA-256, enforces the pub lockfile, audits pub provenance/advisories, runs formatting/analysis/unit checks, builds the release app, and launches it repeatedly for programmatic native-window checks.

`scripts/windows-check.ps1` uses fresh sample state and removes stale phase reports before each launch. Baseline checks cover only default launch and size-only write/restart: size must survive and position must reset. Candidate checks compare rectangles across independent processes against the original requested bounds, including maximized restart/restore and a move immediately followed by maximize.

Separate move-only and resize-only phases dispatch synthetic `WM_MOVING`/`WM_SIZING` messages through the native plugin path, wait for the state file without an explicit save, and remain alive until PowerShell force-terminates them. Restart must recover the requested rectangle. A separate phase changes geometry without a move event, waits for PowerShell to send `WM_CLOSE`, and verifies that the close callback flushed the new state. Synthetic dispatch does not prove mouse interaction. Each process/checkpoint has a 45-second timeout; inability to create/query a window fails the run rather than claiming GUI coverage.

The artifact `auth-window-restoration-windows` includes the complete runnable bundle, JSON snapshots and event logs, requested/observed bounds, runner session information, dependency evidence, and SDK version. Artifacts expire after 14 days.

## Verification status and limits

Local macOS validation: **15 tests passed**, with clean formatting and analysis. Geometry tests cover four taskbar work-area shapes, negative monitor coordinates, simulated DPI/layout changes, monitor removal, serialization, and maximize/minimize/startup state handling. Session tests use mocked native channels and real temporary files to verify use of native normal geometry, recovery after a failed write, and close cleanup after a failed flush. These are host tests, not Windows device tests.

Windows compilation and the programmatic restart checks are **pending the first workflow run**. No Windows GUI behavior is claimed yet.

Even a passing hosted Windows run does not establish:

- Human mouse dragging, resizing, snapping, title-bar reachability, or visual correctness.
- A real top-positioned/auto-hidden taskbar. Unit tests simulate reserved work areas; they do not move the Windows shell taskbar.
- Physical mixed-DPI monitors, hot unplug/replug, docking, RDP transitions, or Windows virtual desktops. Hosted runners commonly expose one virtual display; JSON artifacts record what was actually available.
- Rapid movement followed by minimizing before the debounce completes: minimized captures intentionally retain the prior state, so the latest geometry can be lost. Moving while maximized and minimize-from-maximized transitions also need real Windows checks. Raw placement flags are diagnostic only.
- Stable physical monitor identity across driver changes: the current candidate uses Windows display device names, which can be renumbered.
- Auth tray behavior, startup integration, installer behavior, or production SharedPreferences timing.

The native rectangle includes the window frame and potentially invisible resize borders. Manual validation should inspect the visible frame too. `WM_DPICHANGED` can alter the requested bounds during a cross-monitor move; the lab does not apply an unverified second-resize workaround. The original reporter's exact Auth version, monitor resolution/scaling, and taskbar setup remain unknown. The pinned current Auth origin is `(70,70)`; this is not an exact reproduction of every older taskbar report.

## Reference implementations

- [Mergelio PR #15](https://github.com/senseyman/mergelio/pull/15) checks work areas and ignores maximized/full-screen geometry, but deliberately discards saved Windows positions when monitor scale factors differ. It does not demonstrate mixed-DPI restoration.
- [LocalSend PR #304](https://github.com/localsend/localsend/pull/304) introduced size/position persistence. Its later [settings-corruption issue #476](https://github.com/localsend/localsend/issues/476) led to sequential preference writes. The [dual-monitor report #2522](https://github.com/localsend/localsend/discussions/2522) remains a report without an established cause; it is not proof of a particular DPI bug.
- Native normal-bounds conversion follows the workspace/screen distinction in [Microsoft's WINDOWPLACEMENT contract](https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-windowplacement) and [Chromium's implementation](https://chromium.googlesource.com/chromium/src/+/138.0.7204.183/ui/views/win/hwnd_message_handler.cc). This does not substitute for testing our runner.

## Dependencies and sources

`window_manager` is pinned to Auth's 0.5.1. `pubspec.lock` fixes all transitive versions and archive hashes. `evidence/dependencies.json` records the checked pub.dev metadata and advisory responses. Re-run `python scripts/audit_dependencies.py` to refresh; it stops on any active advisory requiring assessment. Windows plugin CMake files were inspected; the example-only GoogleTest download is not enabled by this app.

The Flutter SDK archive checksum was checked against the [official Windows release manifest](https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json). GitHub actions are pinned to commits in the official `actions` repositories. Pub packages are fetched without running npm/install scripts; the Windows build compiles the inspected native plugin code.

Win32 references: [GetWindowRect and DPI virtualization](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getwindowrect), [GetMonitorInfoW](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getmonitorinfow), [SetWindowPos](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowpos).
