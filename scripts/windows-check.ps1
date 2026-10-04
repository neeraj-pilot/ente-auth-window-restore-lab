param([string]$Executable = 'build/windows/x64/runner/Release/auth_window_restore_lab.exe')
$ErrorActionPreference = 'Stop'
$exe = (Resolve-Path $Executable).Path
$results = Join-Path $PWD 'results'
New-Item -ItemType Directory -Force $results | Out-Null
Remove-Item (Join-Path $results 'summary.json') -Force -ErrorAction SilentlyContinue
$state = Join-Path $results ('state-' + [guid]::NewGuid().ToString('N'))
@{ os = (Get-CimInstance Win32_OperatingSystem).Caption; userInteractive = [Environment]::UserInteractive;
   sessionId = (Get-Process -Id $PID).SessionId; runner = $env:RUNNER_OS;
   coverage = 'Native window APIs and synthetic event dispatch; no human or physical multi-monitor verification' } |
  ConvertTo-Json | Set-Content (Join-Path $results 'environment.json')

function Assert-Rect($actual, $expected, [string]$label, $fields = @('x', 'y', 'width', 'height')) {
  foreach ($field in $fields) {
    if ($null -eq $actual.$field -or $null -eq $expected.$field -or
        [Math]::Abs($actual.$field - $expected.$field) -gt 3) {
      throw "$label differs at $field (actual $($actual.$field), expected $($expected.$field))"
    }
  }
}

function Run-Phase([string]$mode, [string]$phase, [string]$statePath,
                   [string]$name = "$mode-$phase", [string]$finish = 'exit') {
  $result = Join-Path $results "$name.json"
  Remove-Item $result, "$result.tmp" -Force -ErrorAction SilentlyContinue
  $arguments = @("--mode=$mode", "`"--state-dir=$statePath`"", "--phase=$phase", "`"--result=$result`"")
  $process = Start-Process -FilePath $exe -ArgumentList $arguments -PassThru
  $null = $process.Handle
  try {
    if ($finish -ne 'exit') {
      $deadline = [DateTime]::UtcNow.AddSeconds(45)
      while (-not (Test-Path $result) -and -not $process.HasExited -and [DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 100
      }
      if (-not (Test-Path $result)) { throw "$name did not reach its termination checkpoint" }
      $ready = Get-Content $result -Raw | ConvertFrom-Json
      if (-not $ready.passed -or $ready.waitingFor -ne $finish) { throw "$name failed: $($ready.error)" }
      if ($finish -eq 'kill') {
        if ($process.HasExited) { throw "$name exited before the external kill" }
        Stop-Process -Id $process.Id -Force
      } elseif (-not $process.CloseMainWindow()) {
        throw "$name could not send WM_CLOSE to the sample window"
      }
    }
    if (-not $process.WaitForExit(45000)) { throw "$name timed out; see hosted-GUI limitations in README" }
    $process.Refresh()
    if ($finish -ne 'kill' -and $process.ExitCode -ne 0) { throw "$name exited with $($process.ExitCode)" }
    if (-not (Test-Path $result)) { throw "$name produced no result" }
    $report = Get-Content $result -Raw | ConvertFrom-Json
    if (-not $report.passed) { throw "$name failed: $($report.error)" }
    Write-Host "$name passed"
    return $report
  } finally {
    if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
    $process.Dispose()
  }
}

$baselineState = Join-Path $state 'baseline'
$null = Run-Phase 'baseline' 'default' (Join-Path $state 'baseline-default')
$before = Run-Phase 'baseline' 'write' $baselineState
$after = Run-Phase 'baseline' 'read' $baselineState
Assert-Rect $after.actual.bounds $before.target 'Baseline size' @('width', 'height')
$positionLost = [Math]::Abs($before.target.x - $after.actual.bounds.x) -gt 3 -or
                [Math]::Abs($before.target.y - $after.actual.bounds.y) -gt 3
if (-not $positionLost) { throw 'Baseline did not reproduce position reset on this runner' }

$fixedState = Join-Path $state 'fixed'
$null = Run-Phase 'fixed' 'default' (Join-Path $state 'fixed-default')
$written = Run-Phase 'fixed' 'write' $fixedState
$read = Run-Phase 'fixed' 'read' $fixedState
Assert-Rect $read.actual.bounds $written.target 'Fixed restart'
$maximized = Run-Phase 'fixed' 'maximize' $fixedState
Assert-Rect $maximized.stored.logicalBounds $written.stored.logicalBounds 'Maximize preserves normal bounds'
$restored = Run-Phase 'fixed' 'read-maximized' $fixedState
Assert-Rect $restored.actual.bounds $written.target 'Maximized restart and restore'
$null = Run-Phase 'fixed' 'minimize' $fixedState
$moved = Run-Phase 'fixed' 'move-maximize' $fixedState
$restored = Run-Phase 'fixed' 'read-maximized' $fixedState 'fixed-after-move-maximize'
Assert-Rect $restored.actual.bounds $moved.target 'Move immediately followed by maximize'

foreach ($phase in @('event-move', 'event-resize', 'close-ready')) {
  $caseState = Join-Path $state $phase
  $null = Run-Phase 'fixed' 'write' $caseState "fixed-$phase-seed"
  $finish = if ($phase -eq 'close-ready') { 'close' } else { 'kill' }
  $changed = Run-Phase 'fixed' $phase $caseState "fixed-$phase" $finish
  $reopened = Run-Phase 'fixed' 'read' $caseState "fixed-after-$phase"
  Assert-Rect $reopened.actual.bounds $changed.target "Restart after $phase/$finish"
}
@{ baselinePositionResetReproduced = $positionLost; baselineSizeRetained = $true;
   fixedChecks = 'Independent cross-process bounds, maximize timing, minimized capture, synthetic move/resize then force-kill, WM_CLOSE flush' } |
  ConvertTo-Json | Set-Content (Join-Path $results 'summary.json')
