# Auth #1883 Windows lab

Isolated Flutter sample for [Ente Auth #1883](https://github.com/ente/ente/issues/1883). Production Auth and its data are untouched.

- **Baseline:** retains size but resets position. Models Auth's size-only policy, not its full lifecycle.
- **Candidate:** restores normal bounds and maximized state, fitting the window within an available monitor's work area.

## Run on Windows

Requires Flutter 3.47.2 and the Windows x64 C++ toolchain.

```powershell
flutter pub get --enforce-lockfile
flutter build windows --release --no-pub
./scripts/windows-check.ps1
```

For manual testing, extract the full `windows-sample.zip` workflow artifact and launch `auth_window_restore_lab.exe --mode=baseline` or `--mode=fixed`. Move/resize, close, and reopen. State lives under `%LOCALAPPDATA%/AuthWindowRestoreLab`; run one instance per mode.

## Results and limits

The [manual Windows workflow](https://github.com/neeraj-pilot/ente-auth-window-restore-lab/actions/runs/37208453943) passed at `30c4dbd`: release build, analysis, 15 tests, and 20 process phases. Baseline position reset was reproduced. Candidate checks passed for restart, maximize/restore, synthetic move/resize followed by forced termination, and close-time saves.

The runner had one 1024×768 display at 100% scaling. Real mixed-DPI monitors, hot-plugging, human dragging, taskbar layouts, and Auth's lifecycle remain unverified. Rapid move→minimize can lose the latest bounds before the 150 ms debounce completes; monitor identifiers may change with drivers. This remains an experiment, not a production fix.
