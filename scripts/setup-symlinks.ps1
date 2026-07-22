# Agent Layer Symlink Hub - portable setup script (Windows PowerShell 5.1+)
#
# Resolves the repo root dynamically from this script's own location, so the
# same repo works on any machine after `git clone`. Detects which AI tools are
# installed (CLI binary on PATH) and links the sources of truth (AGENTS.md,
# skills/) into each installed tool's global config dir.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup-symlinks.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\setup-symlinks.ps1 -ForceAll
#
# If not elevated (and Developer Mode off), the script self-elevates via UAC.
# -ForceAll links every supported tool regardless of detection.

[CmdletBinding()]
param(
  # Internal flag used during self-elevation to prevent re-elevation loops.
  [switch]$Elevated,
  # Link all supported tools even when their CLI binary is not on PATH.
  [switch]$ForceAll
)

# --- repo root (dynamic) ----------------------------------------------------
$ScriptPath   = $MyInvocation.MyCommand.Path
$ScriptDir    = Split-Path -Parent $ScriptPath
$RepoRoot     = Split-Path -Parent $ScriptDir
$SourceAgents = Join-Path $RepoRoot 'AGENTS.md'
$SourceSkills = Join-Path $RepoRoot 'skills'

# --- self-elevation on Windows ---------------------------------------------
$IsWindows = ($PSVersionTable.Platform -ne 'Unix') -and ($PSVersionTable.OS -match 'Win' -or $true) -and
             (-not ($PSVersionTable.PSEdition -eq 'Core' -and $PSVersionTable.OS -match 'Linux|Darwin'))
# Detect non-Windows (PSCore on *nix) where elevation is not needed.
$RunningOnUnix = $false
if ($PSVersionTable.Platform -eq 'Unix') { $RunningOnUnix = $true }
if ($PSVersionTable.PSEdition -eq 'Core' -and ($PSVersionTable.OS -match 'Linux|Darwin')) { $RunningOnUnix = $true }

if ($IsWindows -and -not $RunningOnUnix -and -not $Elevated) {
  $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) {
    # Developer Mode grants symlink permission without admin; try to create a
    # quick throwaway symlink to detect it. If it fails, we need elevation.
    $devModeOk = $false
    try {
      $probe = Join-Path $env:TEMP ('symlink_probe_' + [guid]::NewGuid().ToString('N'))
      New-Item -ItemType SymbolicLink -Path $probe -Value $SourceAgents -ErrorAction Stop | Out-Null
      Remove-Item -Force $probe -ErrorAction SilentlyContinue
     $devModeOk = $true
    } catch {
      $devModeOk = $false
    }

    if (-not $devModeOk) {
      Write-Host 'Administrator privileges required to create symlinks on Windows (Developer Mode appears off).' -ForegroundColor Yellow
      Write-Host 'Re-launching this script elevated...' -ForegroundColor Yellow
      $elevArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath, '-Elevated')
      if ($ForceAll) { $elevArgs += '-ForceAll' }
      try {
        Start-Process -FilePath 'powershell' -Verb RunAs -ArgumentList $elevArgs -ErrorAction Stop
      } catch {
        try {
          Start-Process -FilePath 'pwsh' -Verb RunAs -ArgumentList $elevArgs -ErrorAction Stop
        } catch {
          Write-Host 'ERROR: UAC elevation was cancelled or failed. Re-run from an admin shell.' -ForegroundColor Red
          exit 1
        }
      }
      exit 0
    }
    Write-Host 'Developer Mode detected - proceeding without elevation.' -ForegroundColor Green
  }
}

# --- tool detection ---------------------------------------------------------
# A tool counts as installed when its CLI binary is on PATH.
$ToolState = [ordered]@{}
foreach ($t in @(@('OpenCode', 'opencode'), @('Claude Code', 'claude'), @('Gemini', 'gemini'), @('Codex', 'codex'))) {
  $found = $null -ne (Get-Command $t[1] -ErrorAction SilentlyContinue)
  if ($ForceAll)   { $ToolState[$t[0]] = 'Forced' }
  elseif ($found)  { $ToolState[$t[0]] = 'Installed' }
  else             { $ToolState[$t[0]] = 'Not found' }
}
function Test-ToolEnabled {
  param([string]$Name)
  return ($ToolState[$Name] -ne 'Not found')
}

# --- report state -----------------------------------------------------------
$ReportRows  = New-Object System.Collections.Generic.List[object]
$VerifyList  = New-Object System.Collections.Generic.List[object]
$FailedCount = 0

function Add-ReportRow {
  param([string]$Tool, [string]$LinkType, [string]$Status, [string]$Target, [string]$PointsTo)
  $script:ReportRows.Add([pscustomobject]@{
    Tool      = $Tool
    Installed = $ToolState[$Tool]
    LinkType  = $LinkType
    Status    = $Status
    Target    = $Target
    PointsTo  = $PointsTo
  }) | Out-Null
}

function Add-VerifyEntry {
  param([string]$Kind, [string]$Target)
  $script:VerifyList.Add([pscustomobject]@{ Kind = $Kind; Target = $Target }) | Out-Null
}

# --- low-level helpers ------------------------------------------------------
function Test-IsReparsePoint {
  param([System.IO.FileSystemInfo]$Item)
  return (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Remove-ExistingTarget {
  # Removes a path without ever following a symlink into its target:
  # reparse points are deleted via .NET (only the link itself is removed).
  param([string]$Path)
  $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
  if ($null -eq $item) { return }
  if (Test-IsReparsePoint $item) {
    if ($item.PSIsContainer) { [System.IO.Directory]::Delete($Path) }
    else                     { [System.IO.File]::Delete($Path) }
  } elseif ($item.PSIsContainer) {
    Remove-Item -LiteralPath $Path -Force -Recurse
  } else {
    Remove-Item -LiteralPath $Path -Force
  }
}

# --- link helper (idempotent) ----------------------------------------------
# Ensures $Target is a symlink to $Source. Returns $true when the link is in
# place (created or already correct), $false otherwise.
function Invoke-LinkTarget {
  param(
    [string]$Tool,
    [string]$Target,
    [string]$Source,
    [string]$Kind   # 'file' | 'dir'
  )

  # Safety: never delete the real source.
  if ($Target -eq $Source) {
    Write-Host "ERROR: target equals source ($Target). Skipping." -ForegroundColor Red
    Add-ReportRow -Tool $Tool -LinkType "Symlink($Kind)" -Status 'Failed' -Target $Target -PointsTo $Source
    $script:FailedCount++
    return $false
  }

  # Create parent dir of the target if missing.
  $parent = Split-Path -Parent $Target
  if ($parent -and -not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
  }

  $existing = Get-Item -LiteralPath $Target -Force -ErrorAction SilentlyContinue
  if ($null -ne $existing) {
    if (Test-IsReparsePoint $existing) {
      $cur = $existing.Target
      if ($cur -is [array]) { $cur = $cur[0] }
      if ($cur -eq $Source) {
        Write-Host "Already linked: $Target -> $Source" -ForegroundColor Green
        Add-ReportRow -Tool $Tool -LinkType "Symlink($Kind)" -Status 'Already linked' -Target $Target -PointsTo $Source
        return $true
      }
      Write-Host "Replacing symlink pointing elsewhere: $Target" -ForegroundColor Yellow
      Remove-ExistingTarget -Path $Target
    }
    elseif ($existing.PSIsContainer) {
      Write-Host "Replacing existing directory copy: $Target" -ForegroundColor Yellow
      Remove-ExistingTarget -Path $Target
    }
    else {
      # Stale real-file copy: rename out of the way instead of deleting.
      $bak = "$Target.bak"
      if ($null -ne (Get-Item -LiteralPath $bak -Force -ErrorAction SilentlyContinue)) {
        Remove-ExistingTarget -Path $bak
      }
      Write-Host "Renaming stale file copy: $Target -> $bak" -ForegroundColor Yellow
      Move-Item -LiteralPath $Target -Destination $bak -Force
    }
  }

  try {
    New-Item -ItemType SymbolicLink -Path $Target -Value $Source -ErrorAction Stop | Out-Null
    Write-Host "Linked: $Target -> $Source" -ForegroundColor Green
    Add-ReportRow -Tool $Tool -LinkType "Symlink($Kind)" -Status 'Linked' -Target $Target -PointsTo $Source
    return $true
  } catch {
    Write-Host "ERROR: failed to create symlink $Target -> $Source : $_" -ForegroundColor Red
    Add-ReportRow -Tool $Tool -LinkType "Symlink($Kind)" -Status 'Failed' -Target $Target -PointsTo $Source
    $script:FailedCount++
    return $false
  }
}

# --- Codex: rules file (RTK-aware) ------------------------------------------
function Set-CodexRules {
  $dest = Join-Path $HOME '.codex\AGENTS.md'
  $rtk  = Join-Path $HOME '.codex\RTK.md'

  if ($dest -eq $SourceAgents) {
    Write-Host "ERROR: codex rules target equals source ($dest). Skipping." -ForegroundColor Red
    $script:FailedCount++
    return
  }

  $parent = Split-Path -Parent $dest
  if (-not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
  }

  if (Test-Path -LiteralPath $rtk) {
    # Compose a REAL file referencing the canonical rules + the user's RTK file.
    $lines = @("@$SourceAgents", "@$rtk")
    $existing = Get-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue
    if ($null -ne $existing) {
      if (-not (Test-IsReparsePoint $existing)) {
        $cur = Get-Content -LiteralPath $dest -ErrorAction SilentlyContinue
        if ($null -ne $cur -and (($cur -join "`n") -eq ($lines -join "`n"))) {
          Write-Host "Already linked (composed file): $dest" -ForegroundColor Green
          Add-ReportRow -Tool 'Codex' -LinkType 'File(composed)' -Status 'Already linked' -Target $dest -PointsTo "$SourceAgents + $rtk"
          Add-VerifyEntry -Kind 'codex-composed' -Target $dest
          return
        }
      }
      # Remove a stale symlink/file BEFORE writing (Set-Content would follow a
      # symlink and overwrite the repo source).
      Remove-ExistingTarget -Path $dest
    }
    try {
      Set-Content -LiteralPath $dest -Value $lines -Encoding ASCII -ErrorAction Stop
      Write-Host "Composed: $dest (references repo AGENTS.md + RTK.md)" -ForegroundColor Green
      Add-ReportRow -Tool 'Codex' -LinkType 'File(composed)' -Status 'Linked' -Target $dest -PointsTo "$SourceAgents + $rtk"
      Add-VerifyEntry -Kind 'codex-composed' -Target $dest
    } catch {
      Write-Host "ERROR: failed to write $dest : $_" -ForegroundColor Red
      Add-ReportRow -Tool 'Codex' -LinkType 'File(composed)' -Status 'Failed' -Target $dest -PointsTo "$SourceAgents + $rtk"
      $script:FailedCount++
    }
    return
  }

  if (Invoke-LinkTarget -Tool 'Codex' -Target $dest -Source $SourceAgents -Kind 'file') {
    Add-VerifyEntry -Kind 'file' -Target $dest
  }
}

# --- Codex: in-repo alias symlinks (flatten nested shared skills) -----------
function Set-SourceSkillAliases {
  $aliases = @(
    'engineering\create-architecture-documentation',
    'engineering\debug-mantra',
    'engineering\generate-tests',
    'engineering\post-mortem',
    'engineering\scrutinize',
    'productivity\management-talk'
  )
  foreach ($rel in $aliases) {
    $leaf = Split-Path -Leaf $rel
    $dest = Join-Path $SourceSkills $leaf
    $existing = Get-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue
    if ($null -ne $existing) {
      if (Test-IsReparsePoint $existing) {
        $cur = $existing.Target
        if ($cur -is [array]) { $cur = $cur[0] }
        if ($null -ne $cur -and (($cur -replace '/', '\').TrimEnd('\') -eq $rel)) {
          Write-Host "Alias already linked: $dest -> $rel" -ForegroundColor Green
          continue
        }
        Write-Host "Replacing stale alias symlink: $dest" -ForegroundColor Yellow
        Remove-ExistingTarget -Path $dest
      } else {
        Write-Host "WARN: $dest exists and is not a symlink - skipping alias $rel" -ForegroundColor Yellow
        continue
      }
    }
    # mklink /D stores the relative target verbatim. (New-Item would resolve a
    # relative target against the session cwd and could create a file-type link.)
    $out = cmd /c "mklink /D `"$dest`" `"$rel`"" 2>&1
    if ($LASTEXITCODE -eq 0) {
      Write-Host "Alias linked: $dest -> $rel" -ForegroundColor Green
    } else {
      Write-Host "ERROR: failed to create alias $dest -> $rel : $out" -ForegroundColor Red
      $script:FailedCount++
    }
  }
}

# --- Codex: skills dir (real dir of per-skill links, flat layout) -----------
function Set-CodexSkills {
  $cskills = Join-Path $HOME '.codex\skills'

  if ($cskills -eq $SourceSkills) {
    Write-Host "ERROR: codex skills target equals source ($cskills). Skipping." -ForegroundColor Red
    $script:FailedCount++
    return
  }

  # Codex expects a REAL directory of per-skill links, not one dir symlink.
  $existing = Get-Item -LiteralPath $cskills -Force -ErrorAction SilentlyContinue
  if ($null -ne $existing -and (Test-IsReparsePoint $existing)) {
    Write-Host "Removing dir symlink at $cskills (Codex needs a real directory)." -ForegroundColor Yellow
    Remove-ExistingTarget -Path $cskills
  }
  if (-not (Test-Path -LiteralPath $cskills)) {
    New-Item -ItemType Directory -Path $cskills -Force | Out-Null
  }

  # Flatten nested shared skills via aliases inside the repo, then link.
  Set-SourceSkillAliases

  Get-ChildItem -LiteralPath $SourceSkills -Force | ForEach-Object {
    if ($_.Name -like '.*') { return }
    $skill = $_.FullName
    if (-not (Test-Path -LiteralPath $skill -PathType Container)) { return }
    if (-not (Test-Path -LiteralPath (Join-Path $skill 'SKILL.md'))) { return }
    Invoke-LinkTarget -Tool 'Codex' -Target (Join-Path $cskills $_.Name) -Source $skill -Kind 'dir' | Out-Null
  }

  # Internal .system skills, linked flat (when present in the repo).
  foreach ($name in @('imagegen', 'openai-docs', 'plugin-creator', 'skill-creator', 'skill-installer')) {
    $src = Join-Path $SourceSkills (Join-Path '.system' $name)
    if (Test-Path -LiteralPath $src -PathType Container) {
      Invoke-LinkTarget -Tool 'Codex' -Target (Join-Path $cskills $name) -Source $src -Kind 'dir' | Out-Null
    }
  }

  Add-VerifyEntry -Kind 'codex-skills' -Target $cskills
}

# --- header -----------------------------------------------------------------
Write-Host 'Agent Layer Symlink Hub (PowerShell)' -ForegroundColor Cyan
Write-Host "Repo root : $RepoRoot"
Write-Host "HOME      : $HOME"
Write-Host ''
Write-Host 'Tool detection (CLI binary on PATH):' -ForegroundColor Cyan
foreach ($k in $ToolState.Keys) { Write-Host ("  {0,-12}: {1}" -f $k, $ToolState[$k]) }
if ($ForceAll) { Write-Host '  (-ForceAll set: linking all tools regardless of detection)' -ForegroundColor Yellow }
Write-Host ''

# --- link per installed tool --------------------------------------------------
if (Test-ToolEnabled 'OpenCode') {
  $t1 = Join-Path $HOME '.config\opencode\AGENTS.md'
  $t2 = Join-Path $HOME '.config\opencode\skills'
  if (Invoke-LinkTarget -Tool 'OpenCode' -Target $t1 -Source $SourceAgents -Kind 'file') { Add-VerifyEntry -Kind 'file' -Target $t1 }
  if (Invoke-LinkTarget -Tool 'OpenCode' -Target $t2 -Source $SourceSkills -Kind 'dir')  { Add-VerifyEntry -Kind 'dir'  -Target $t2 }
}

if (Test-ToolEnabled 'Claude Code') {
  $t1 = Join-Path $HOME '.claude\CLAUDE.md'
  $t2 = Join-Path $HOME '.claude\skills'
  if (Invoke-LinkTarget -Tool 'Claude Code' -Target $t1 -Source $SourceAgents -Kind 'file') { Add-VerifyEntry -Kind 'file' -Target $t1 }
  if (Invoke-LinkTarget -Tool 'Claude Code' -Target $t2 -Source $SourceSkills -Kind 'dir')  { Add-VerifyEntry -Kind 'dir'  -Target $t2 }
}

if (Test-ToolEnabled 'Gemini') {
  $t1 = Join-Path $HOME '.gemini\GEMINI.md'
  $t2 = Join-Path $HOME '.gemini\skills'
  if (Invoke-LinkTarget -Tool 'Gemini' -Target $t1 -Source $SourceAgents -Kind 'file') { Add-VerifyEntry -Kind 'file' -Target $t1 }
  if (Invoke-LinkTarget -Tool 'Gemini' -Target $t2 -Source $SourceSkills -Kind 'dir')  { Add-VerifyEntry -Kind 'dir'  -Target $t2 }
}

if (Test-ToolEnabled 'Codex') {
  Set-CodexRules
  Set-CodexSkills
}

# Record skipped tools in the report.
foreach ($k in $ToolState.Keys) {
  if ($ToolState[$k] -eq 'Not found') {
    Add-ReportRow -Tool $k -LinkType '-' -Status 'Skipped-not-installed' -Target '-' -PointsTo '-'
  }
}

# --- verification -----------------------------------------------------------
Write-Host ''
Write-Host '=== Verification ===' -ForegroundColor Cyan
foreach ($v in $VerifyList) {
  $t = $v.Target
  Write-Host "--- verify: $t ---"
  $item = Get-Item -LiteralPath $t -Force -ErrorAction SilentlyContinue

  if ($v.Kind -eq 'codex-composed') {
    Write-Host 'composed file contents:'
    Get-Content -LiteralPath $t -ErrorAction SilentlyContinue | ForEach-Object { Write-Host $_ }
  }
  elseif ($v.Kind -eq 'codex-skills') {
    Write-Host 'per-skill symlinks:'
    Get-ChildItem -LiteralPath $t -Force -ErrorAction SilentlyContinue |
      Select-Object Name, LinkType, Target | Format-Table -AutoSize | Out-Host
  }
  elseif ($null -ne $item) {
    $item | Select-Object LinkType, Target | Format-List | Out-Host
    if ($v.Kind -eq 'file') {
      $resolved = $t
      if ($item.Target) {
        $resolved = $item.Target
        if ($resolved -is [array]) { $resolved = $resolved[0] }
      }
      Write-Host 'first 3 lines of resolved content:'
      $head = Get-Content -LiteralPath $resolved -TotalCount 3 -ErrorAction SilentlyContinue
      $head | ForEach-Object { Write-Host $_ }
      $srcHead = Get-Content -LiteralPath $SourceAgents -TotalCount 3 -ErrorAction SilentlyContinue
      if (($head -join "`n") -eq ($srcHead -join "`n")) {
        Write-Host 'content head matches source: OK' -ForegroundColor Green
      } else {
        Write-Host 'WARN: content head differs from source' -ForegroundColor Yellow
      }
    } else {
      Write-Host 'first 5 child entries:'
      Get-ChildItem -LiteralPath $t -ErrorAction SilentlyContinue |
        Select-Object -First 5 -ExpandProperty Name | ForEach-Object { Write-Host $_ }
    }
  } else {
    Write-Host 'target does not exist' -ForegroundColor Red
  }
  Write-Host ''
}

# --- final report -----------------------------------------------------------
Write-Host '=== Final report ===' -ForegroundColor Cyan
Write-Host '| Tool | Installed? | Link Type | Status | Target Path | Points To |'
Write-Host '|------|------------|-----------|--------|-------------|-----------|'
foreach ($r in $ReportRows) {
  Write-Host ('| {0} | {1} | {2} | {3} | {4} | {5} |' -f $r.Tool, $r.Installed, $r.LinkType, $r.Status, $r.Target, $r.PointsTo)
}
Write-Host ''

if ($FailedCount -gt 0) {
  Write-Host "FAILED_COUNT=$FailedCount" -ForegroundColor Red
  exit 1
}
Write-Host 'All targets linked successfully.' -ForegroundColor Green
