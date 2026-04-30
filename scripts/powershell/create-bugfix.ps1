#!/usr/bin/env pwsh
$ErrorActionPreference = 'Stop'

# Source common functions from spec-kit
$ScriptDir = $PSScriptRoot

# Search for common.ps1 in known locations
$commonFound = $false
$searchPaths = @(
    (Join-Path $ScriptDir ".." "powershell" "common.ps1"),
    (Join-Path $ScriptDir ".." ".." "scripts" "powershell" "common.ps1"),
    (Join-Path $ScriptDir ".." ".." ".specify" "scripts" "powershell" "common.ps1")
)

foreach ($p in $searchPaths) {
    if (Test-Path -LiteralPath $p -PathType Leaf) {
        . $p
        $commonFound = $true
        break
    }
}

if (-not $commonFound) {
    # Fallback: search parent directories
    $searchDir = $ScriptDir
    for ($i = 0; $i -lt 5; $i++) {
        $candidate = Join-Path $searchDir "common.ps1"
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            . $candidate
            $commonFound = $true
            break
        }
        $candidate = Join-Path $searchDir "scripts" "powershell" "common.ps1"
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            . $candidate
            $commonFound = $true
            break
        }
        $searchDir = Split-Path $searchDir -Parent
        if ([string]::IsNullOrEmpty($searchDir)) { break }
    }
}

if (-not $commonFound) {
    Write-Error "Could not find common.ps1. Please ensure spec-kit is properly installed."
    exit 1
}

# Parse arguments
$JsonMode = $false
$remainingArgs = @()

foreach ($arg in $args) {
    switch ($arg) {
        { $_ -eq '--json' -or $_ -eq '-Json' } { $JsonMode = $true }
        { $_ -eq '--help' -or $_ -eq '-h' -or $_ -eq '-Help' } {
            Write-Output "Usage: $($MyInvocation.MyCommand.Name) [--json] <bug_description>"
            exit 0
        }
        default { $remainingArgs += $arg }
    }
}

$BugDescription = ($remainingArgs -join ' ').Trim()
if ([string]::IsNullOrEmpty($BugDescription)) {
    Write-Error "Usage: $($MyInvocation.MyCommand.Name) [--json] <bug_description>"
    exit 1
}

# Use spec-kit common functions
$RepoRoot = Get-RepoRoot
$HasGit = Test-HasGit

Set-Location $RepoRoot

$SpecsDir = Join-Path $RepoRoot "specs"
if (-not (Test-Path -LiteralPath $SpecsDir -PathType Container)) {
    New-Item -ItemType Directory -Path $SpecsDir -Force | Out-Null
}

# Find highest bugfix number
$Highest = 0
if (Test-Path -LiteralPath $SpecsDir -PathType Container) {
    Get-ChildItem -Path $SpecsDir -Directory -Filter "bugfix-*" -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Name -match '^bugfix-(\d+)') {
            $num = [int]$Matches[1]
            if ($num -gt $Highest) { $Highest = $num }
        }
    }
}

$Next = $Highest + 1
$BugNum = '{0:D3}' -f $Next

# Create branch name from description
$BranchSuffix = $BugDescription.ToLower() -replace '[^a-z0-9]', '-' -replace '-+', '-' -replace '^-', '' -replace '-$', ''
$Words = ($BranchSuffix -split '-' | Where-Object { $_ -ne '' } | Select-Object -First 3) -join '-'
$BranchName = "bugfix/${BugNum}-${Words}"
$BugId = "bugfix-${BugNum}"

# Create git branch if git available
if ($HasGit) {
    git checkout -b $BranchName
} else {
    Write-Warning "[bugfix] Warning: Git repository not detected; skipped branch creation for $BranchName"
}

# Create bug directory
$BugDir = Join-Path $SpecsDir "${BugId}-${Words}"
if (-not (Test-Path -LiteralPath $BugDir -PathType Container)) {
    New-Item -ItemType Directory -Path $BugDir -Force | Out-Null
}

# Copy template
$BugfixTemplate = Join-Path $RepoRoot ".specify" "extensions" "workflows" "bugfix" "bug-report-template.md"
$BugReportFile = Join-Path $BugDir "bug-report.md"

if (Test-Path -LiteralPath $BugfixTemplate -PathType Leaf) {
    Copy-Item -LiteralPath $BugfixTemplate -Destination $BugReportFile -Force
} else {
    Set-Content -Path $BugReportFile -Value "# Bug Report"
}

# Set environment variable for current session
$env:SPECIFY_BUGFIX = $BugId

if ($JsonMode) {
    $output = [ordered]@{
        BUG_ID          = $BugId
        BRANCH_NAME     = $BranchName
        BUG_REPORT_FILE = (Resolve-Path -LiteralPath $BugReportFile).Path
        BUG_NUM         = $BugNum
    }
    $output | ConvertTo-Json -Compress
} else {
    Write-Output "BUG_ID: $BugId"
    Write-Output "BRANCH_NAME: $BranchName"
    Write-Output "BUG_REPORT_FILE: $BugReportFile"
    Write-Output "BUG_NUM: $BugNum"
    Write-Output "SPECIFY_BUGFIX environment variable set to: $BugId"
}
