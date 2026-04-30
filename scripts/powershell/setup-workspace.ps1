#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Sets up a spec-kit workspace with brownfield and devflow extensions.

.DESCRIPTION
    1. Installs the spec-kit CLI (via uv or pipx)
    2. Initializes the workspace for Copilot integration
    3. Installs the brownfield extension (spec-kit-brownfield)
    4. Installs the devflow extension (spec-kit-devflows)

    After setup, open your AI agent and run the brownfield workflow commands
    as shown in the output.

.PARAMETER WorkspacePath
    Path to the workspace/repository to initialize. Defaults to current directory.

.PARAMETER SpecKitVersion
    Spec-kit release tag to install (e.g. v0.8.3). Default: latest from main.

.PARAMETER BrownfieldVersion
    Brownfield extension version tag. Default: v1.0.0

.PARAMETER DevflowVersion
    Devflow extension version tag. Default: v2.1.1

.PARAMETER Integration
    AI agent integration type. Default: copilot
    Valid values: copilot, claude, cursor, windsurf

.PARAMETER SkipSpecKit
    Skip spec-kit CLI installation (use if already installed).

.EXAMPLE
    .\setup-workspace.ps1 -WorkspacePath C:\myproject

.EXAMPLE
    .\setup-workspace.ps1 -Integration claude -DevflowVersion v2.1.1
#>

[CmdletBinding()]
param(
    [string]$WorkspacePath = ".",
    [string]$SpecKitVersion = "",
    [string]$BrownfieldVersion = "v1.0.0",
    [string]$DevflowVersion = "v2.1.1",
    [ValidateSet("copilot", "claude", "cursor", "windsurf")]
    [string]$Integration = "copilot",
    [switch]$SkipSpecKit
)

$ErrorActionPreference = 'Stop'

function Write-Step { param([int]$Num, [string]$Msg) Write-Host "`n[$Num/4] $Msg" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Msg) Write-Host "  OK  $Msg" -ForegroundColor Green }
function Write-Skip { param([string]$Msg) Write-Host "  SKIP  $Msg" -ForegroundColor Yellow }
function Write-Err  { param([string]$Msg) Write-Host "  ERR $Msg" -ForegroundColor Red }

# Resolve workspace path
$WorkspacePath = (Resolve-Path -LiteralPath $WorkspacePath -ErrorAction Stop).Path

# ── Step 1: Install spec-kit CLI ──────────────────────────────────────────────

Write-Step 1 "Install spec-kit CLI"

if ($SkipSpecKit) {
    Write-Skip "SkipSpecKit flag set"
}
else {
    $specifyCmd = Get-Command specify -ErrorAction SilentlyContinue
    if ($specifyCmd) {
        $currentVersion = & specify version 2>&1 | Select-Object -First 1
        Write-Ok "Already installed: $currentVersion"
    }
    else {
        # Determine installer: prefer uv, fall back to pipx
        $uvCmd = Get-Command uv -ErrorAction SilentlyContinue
        $pipxCmd = Get-Command pipx -ErrorAction SilentlyContinue

        $source = "git+https://github.com/github/spec-kit.git"
        if ($SpecKitVersion) { $source += "@$SpecKitVersion" }

        if ($uvCmd) {
            Write-Host "  Installing via uv..." -ForegroundColor Gray
            & uv tool install specify-cli --from $source
        }
        elseif ($pipxCmd) {
            Write-Host "  Installing via pipx..." -ForegroundColor Gray
            & pipx install $source
        }
        else {
            Write-Err "Neither 'uv' nor 'pipx' found. Install one first:"
            Write-Host "    https://docs.astral.sh/uv/getting-started/installation/"
            Write-Host "    https://pypa.github.io/pipx/installation/"
            exit 1
        }

        # Verify
        $specifyCmd = Get-Command specify -ErrorAction SilentlyContinue
        if (-not $specifyCmd) {
            Write-Err "spec-kit installation failed. Check output above."
            exit 1
        }
        $currentVersion = & specify version 2>&1 | Select-Object -First 1
        Write-Ok "Installed: $currentVersion"
    }
}

# ── Step 2: Initialize workspace ──────────────────────────────────────────────

Write-Step 2 "Initialize workspace: $WorkspacePath"

Push-Location $WorkspacePath
try {
    # Check for git repo
    if (-not (Test-Path ".git")) {
        Write-Err "Not a git repository: $WorkspacePath"
        Write-Host "  Run 'git init' first, or specify a different -WorkspacePath."
        exit 1
    }

    # Check if already initialized
    if (Test-Path ".specify") {
        Write-Skip "Already initialized (.specify/ exists)"
    }
    else {
        Write-Host "  Running: specify init . --integration $Integration" -ForegroundColor Gray
        & specify init . --integration $Integration
        if ($LASTEXITCODE -ne 0) {
            Write-Err "specify init failed (exit code $LASTEXITCODE)"
            exit 1
        }
        Write-Ok "Workspace initialized with --integration $Integration"
    }

    # ── Step 3: Install brownfield extension ──────────────────────────────

    Write-Step 3 "Install brownfield extension ($BrownfieldVersion)"

    $brownfieldUrl = "https://github.com/Quratulain-bilal/spec-kit-brownfield/archive/refs/tags/$BrownfieldVersion.zip"

    # Check if already installed
    $extList = & specify extension list 2>&1 | Out-String
    if ($extList -match "brownfield") {
        Write-Skip "Brownfield extension already installed"
    }
    else {
        Write-Host "  Running: specify extension add --from $brownfieldUrl brownfield" -ForegroundColor Gray
        & specify extension add --from $brownfieldUrl brownfield
        if ($LASTEXITCODE -ne 0) {
            Write-Err "Brownfield extension install failed (exit code $LASTEXITCODE)"
            exit 1
        }
        Write-Ok "Brownfield extension installed"
    }

    # ── Step 4: Install devflow extension ─────────────────────────────────

    Write-Step 4 "Install devflow extension ($DevflowVersion)"

    $devflowUrl = "https://github.com/scheilch/spec-kit-devflows/archive/refs/tags/$DevflowVersion.zip"

    if ($extList -match "devflow") {
        Write-Skip "Devflow extension already installed"
    }
    else {
        Write-Host "  Running: specify extension add --from $devflowUrl devflow" -ForegroundColor Gray
        & specify extension add --from $devflowUrl devflow
        if ($LASTEXITCODE -ne 0) {
            Write-Err "Devflow extension install failed (exit code $LASTEXITCODE)"
            exit 1
        }
        Write-Ok "Devflow extension installed"
    }
}
finally {
    Pop-Location
}

# ── Summary ───────────────────────────────────────────────────────────────────

Write-Host "`n" -NoNewline
Write-Host "============================================" -ForegroundColor Green
Write-Host " Setup complete!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Installed extensions:" -ForegroundColor White
& specify extension list 2>&1 | ForEach-Object { Write-Host "  $_" }

Write-Host ""
Write-Host "Next: Open your AI agent ($Integration) in the workspace and run:" -ForegroundColor Yellow
Write-Host ""
Write-Host "  1. /speckit.brownfield.scan" -ForegroundColor White
Write-Host "     Scans existing codebase, discovers architecture and patterns"
Write-Host ""
Write-Host "  2. /speckit.brownfield.bootstrap" -ForegroundColor White
Write-Host "     Generates constitution + initial specs from scan results"
Write-Host ""
Write-Host "  3. /speckit.brownfield.validate" -ForegroundColor White
Write-Host "     Checks spec coverage and identifies gaps"
Write-Host ""
Write-Host "  4. /speckit.brownfield.migrate all" -ForegroundColor White
Write-Host "     Prioritizes gaps as fix/feature for next steps, then use:"
Write-Host "       /speckit.devflow.bugfix    - for gaps that are defects"
Write-Host "       /speckit.devflow.modify    - for gaps that need feature changes"
Write-Host "       /speckit.devflow.refactor  - for code quality gaps"
Write-Host "       /speckit.specify           - for new feature gaps"
Write-Host ""
