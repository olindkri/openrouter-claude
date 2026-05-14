# install.ps1 — install openrouter-claude on Windows so it runs from any terminal.
#
# Copies openrouter-claude.ps1 and openrouter-claude.cmd into a per-user install
# directory and adds that directory to the User PATH. Idempotent — re-run to update.
#
# Usage:
#   pwsh -ExecutionPolicy Bypass -File .\install.ps1
#   pwsh -ExecutionPolicy Bypass -File .\install.ps1 -InstallDir "C:\Tools\openrouter-claude"
#   pwsh -ExecutionPolicy Bypass -File .\install.ps1 -Uninstall

[CmdletBinding()]
param(
  [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'Programs\openrouter-claude'),
  [switch]$Uninstall,
  [switch]$NoFzfPrompt
)

$ErrorActionPreference = 'Stop'
$src = $PSScriptRoot
$psFile  = Join-Path $src 'openrouter-claude.ps1'
$cmdFile = Join-Path $src 'openrouter-claude.cmd'

function Add-ToUserPath([string]$dir) {
  $current = [Environment]::GetEnvironmentVariable('Path', 'User')
  $entries = if ($current) { $current -split ';' | Where-Object { $_ -ne '' } } else { @() }
  if ($entries -contains $dir) {
    Write-Host "  PATH already contains: $dir" -ForegroundColor DarkGray
    return $false
  }
  $new = ($entries + $dir) -join ';'
  [Environment]::SetEnvironmentVariable('Path', $new, 'User')
  Write-Host "  Added to User PATH: $dir" -ForegroundColor Green
  return $true
}

function Remove-FromUserPath([string]$dir) {
  $current = [Environment]::GetEnvironmentVariable('Path', 'User')
  if (-not $current) { return $false }
  $entries = $current -split ';' | Where-Object { $_ -ne '' -and $_ -ne $dir }
  $new = $entries -join ';'
  if ($new -eq $current) { return $false }
  [Environment]::SetEnvironmentVariable('Path', $new, 'User')
  Write-Host "  Removed from User PATH: $dir" -ForegroundColor Yellow
  return $true
}

if ($Uninstall) {
  Write-Host "Uninstalling openrouter-claude…" -ForegroundColor Cyan
  if (Test-Path $InstallDir) {
    Remove-Item -Recurse -Force $InstallDir
    Write-Host "  Removed: $InstallDir" -ForegroundColor Yellow
  }
  Remove-FromUserPath $InstallDir | Out-Null
  Write-Host "Done. Open a new terminal for the PATH change to take effect." -ForegroundColor Cyan
  exit 0
}

# --- sanity ---
if (-not (Test-Path $psFile))  { throw "missing source file: $psFile" }
if (-not (Test-Path $cmdFile)) { throw "missing source file: $cmdFile" }

Write-Host "Installing openrouter-claude → $InstallDir" -ForegroundColor Cyan

# 1) copy files
if (-not (Test-Path $InstallDir)) {
  New-Item -ItemType Directory -Path $InstallDir | Out-Null
}
Copy-Item -Force $psFile  (Join-Path $InstallDir 'openrouter-claude.ps1')
Copy-Item -Force $cmdFile (Join-Path $InstallDir 'openrouter-claude.cmd')
Write-Host "  Copied launcher files" -ForegroundColor Green

# 2) PATH
$pathChanged = Add-ToUserPath $InstallDir
# Make it visible in the CURRENT session too
if ($pathChanged -and ($env:Path -notlike "*$InstallDir*")) {
  $env:Path = "$env:Path;$InstallDir"
}

# 3) verify `claude` is reachable
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
  Write-Host ""
  Write-Host "WARN: 'claude' CLI not found on PATH." -ForegroundColor Yellow
  Write-Host "      Install it with:  npm i -g @anthropic-ai/claude-code" -ForegroundColor Yellow
}

# 4) offer to install fzf for the arrow-key picker
if (-not $NoFzfPrompt -and -not (Get-Command fzf -ErrorAction SilentlyContinue)) {
  Write-Host ""
  Write-Host "fzf enables the arrow-key model picker (recommended)." -ForegroundColor Cyan
  $hasWinget = [bool](Get-Command winget -ErrorAction SilentlyContinue)
  $hasScoop  = [bool](Get-Command scoop  -ErrorAction SilentlyContinue)
  if ($hasWinget -or $hasScoop) {
    $ans = Read-Host "Install fzf now? [Y/n]"
    if ($ans -notmatch '^(n|no)$') {
      try {
        if ($hasWinget) { winget install --id junegunn.fzf -e --silent }
        elseif ($hasScoop) { scoop install fzf }
        Write-Host "  fzf installed." -ForegroundColor Green
      } catch {
        Write-Host "  fzf install failed; launcher will fall back to a numbered prompt." -ForegroundColor Yellow
      }
    }
  } else {
    Write-Host "  Install manually with one of:" -ForegroundColor DarkGray
    Write-Host "    winget install junegunn.fzf" -ForegroundColor DarkGray
    Write-Host "    scoop install fzf" -ForegroundColor DarkGray
    Write-Host "    choco install fzf" -ForegroundColor DarkGray
  }
}

# 5) verify Python (PS1 launcher uses it for HTML parsing on first call only)
if (-not (Get-Command python -ErrorAction SilentlyContinue) -and -not (Get-Command python3 -ErrorAction SilentlyContinue)) {
  Write-Host ""
  Write-Host "Note: Python isn't required (the PowerShell launcher parses rankings natively)," -ForegroundColor DarkGray
  Write-Host "but installing it unlocks faster cold starts. winget install Python.Python.3.12" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "Installed." -ForegroundColor Cyan
Write-Host "Open a NEW terminal (cmd, PowerShell, or Windows Terminal) and run:" -ForegroundColor Cyan
Write-Host "    openrouter-claude" -ForegroundColor White
Write-Host ""
Write-Host "On first run it will prompt you for an OpenRouter API key (https://openrouter.ai/keys)." -ForegroundColor DarkGray
