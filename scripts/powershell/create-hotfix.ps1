#!/usr/bin/env pwsh
$ErrorActionPreference = 'Stop'

# Parse arguments
$JsonMode = $false
$remainingArgs = @()

foreach ($arg in $args) {
    switch ($arg) {
        { $_ -eq '--json' -or $_ -eq '-Json' } { $JsonMode = $true }
        { $_ -eq '--help' -or $_ -eq '-h' -or $_ -eq '-Help' } {
            Write-Output "Usage: $($MyInvocation.MyCommand.Name) [--json] <incident_description>"
            exit 0
        }
        default { $remainingArgs += $arg }
    }
}

$IncidentDescription = ($remainingArgs -join ' ').Trim()
if ([string]::IsNullOrEmpty($IncidentDescription)) {
    Write-Error "Usage: $($MyInvocation.MyCommand.Name) [--json] <incident_description>"
    exit 1
}

# Find repository root
function Find-RepoRoot {
    param([string]$StartDir)
    $current = $StartDir
    while ($true) {
        if ((Test-Path -LiteralPath (Join-Path $current ".git")) -or
            (Test-Path -LiteralPath (Join-Path $current ".specify") -PathType Container)) {
            return $current
        }
        $parent = Split-Path $current -Parent
        if ([string]::IsNullOrEmpty($parent) -or $parent -eq $current) { return $null }
        $current = $parent
    }
}

$ScriptDir = $PSScriptRoot
$HasGit = $false
$RepoRoot = $null

if (Get-Command git -ErrorAction SilentlyContinue) {
    try {
        $result = git rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0) {
            $RepoRoot = $result
            $HasGit = $true
        }
    } catch { }
}

if (-not $RepoRoot) {
    $RepoRoot = Find-RepoRoot -StartDir $ScriptDir
    if (-not $RepoRoot) {
        Write-Error "Could not determine repository root"
        exit 1
    }
}

Set-Location $RepoRoot

$SpecsDir = Join-Path $RepoRoot "specs"
if (-not (Test-Path -LiteralPath $SpecsDir -PathType Container)) {
    New-Item -ItemType Directory -Path $SpecsDir -Force | Out-Null
}

# Find highest hotfix number
$Highest = 0
Get-ChildItem -Path $SpecsDir -Directory -Filter "hotfix-*" -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.Name -match '^hotfix-(\d+)') {
        $num = [int]$Matches[1]
        if ($num -gt $Highest) { $Highest = $num }
    }
}

$Next = $Highest + 1
$HotfixNum = '{0:D3}' -f $Next

# Create branch name from description
$BranchSuffix = $IncidentDescription.ToLower() -replace '[^a-z0-9]', '-' -replace '-+', '-' -replace '^-', '' -replace '-$', ''
$Words = ($BranchSuffix -split '-' | Where-Object { $_ -ne '' } | Select-Object -First 3) -join '-'
$BranchName = "hotfix/${HotfixNum}-${Words}"
$HotfixId = "hotfix-${HotfixNum}"

# Create git branch
if ($HasGit) {
    git checkout -b $BranchName
} else {
    Write-Warning "[hotfix] Warning: Git repository not detected; skipped branch creation for $BranchName"
}

# Create hotfix directory
$HotfixDir = Join-Path $SpecsDir "${HotfixId}-${Words}"
if (-not (Test-Path -LiteralPath $HotfixDir -PathType Container)) {
    New-Item -ItemType Directory -Path $HotfixDir -Force | Out-Null
}

# Copy templates
$HotfixTemplate = Join-Path $RepoRoot ".specify" "extensions" "workflows" "hotfix" "hotfix-template.md"
$PostmortemTemplate = Join-Path $RepoRoot ".specify" "extensions" "workflows" "hotfix" "post-mortem-template.md"

$HotfixFile = Join-Path $HotfixDir "hotfix.md"
$PostmortemFile = Join-Path $HotfixDir "post-mortem.md"

if (Test-Path -LiteralPath $HotfixTemplate -PathType Leaf) {
    Copy-Item -LiteralPath $HotfixTemplate -Destination $HotfixFile -Force
} else {
    Set-Content -Path $HotfixFile -Value "# Hotfix"
}

if (Test-Path -LiteralPath $PostmortemTemplate -PathType Leaf) {
    Copy-Item -LiteralPath $PostmortemTemplate -Destination $PostmortemFile -Force
} else {
    Set-Content -Path $PostmortemFile -Value "# Post-Mortem"
}

# Add incident start timestamp to hotfix file
$Timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss") + " UTC"
$hotfixContent = Get-Content -Path $HotfixFile -Raw -ErrorAction SilentlyContinue
if ($hotfixContent -and $hotfixContent.Contains('[YYYY-MM-DD HH:MM:SS UTC]')) {
    $hotfixContent = $hotfixContent.Replace('[YYYY-MM-DD HH:MM:SS UTC]', $Timestamp)
    Set-Content -Path $HotfixFile -Value $hotfixContent -NoNewline
}

# Create reminder file for post-mortem
$ReminderFile = Join-Path $HotfixDir "POST_MORTEM_REMINDER.txt"
$reminderContent = @"
POST-MORTEM REMINDER
====================

Hotfix ID: $HotfixId
Incident Start: $Timestamp

⚠️  POST-MORTEM DUE WITHIN 48 HOURS ⚠️

Required Actions:
1. Complete post-mortem.md within 48 hours of incident resolution
2. Schedule post-mortem meeting with stakeholders
3. Create action items to prevent recurrence
4. Update monitoring and tests

Post-Mortem File: $PostmortemFile

Do not delete this reminder until post-mortem is complete.
"@
Set-Content -Path $ReminderFile -Value $reminderContent

# Set environment variable
$env:SPECIFY_HOTFIX = $HotfixId

if ($JsonMode) {
    $output = [ordered]@{
        HOTFIX_ID      = $HotfixId
        BRANCH_NAME    = $BranchName
        HOTFIX_FILE    = (Resolve-Path -LiteralPath $HotfixFile).Path
        POSTMORTEM_FILE = (Resolve-Path -LiteralPath $PostmortemFile).Path
        HOTFIX_NUM     = $HotfixNum
        TIMESTAMP      = $Timestamp
    }
    $output | ConvertTo-Json -Compress
} else {
    Write-Output "HOTFIX_ID: $HotfixId"
    Write-Output "BRANCH_NAME: $BranchName"
    Write-Output "HOTFIX_FILE: $HotfixFile"
    Write-Output "POSTMORTEM_FILE: $PostmortemFile"
    Write-Output "HOTFIX_NUM: $HotfixNum"
    Write-Output "INCIDENT_START: $Timestamp"
    Write-Output ""
    Write-Output "⚠️  EMERGENCY HOTFIX - EXPEDITED PROCESS ⚠️"
    Write-Output "Remember: Post-mortem due within 48 hours"
    Write-Output "SPECIFY_HOTFIX environment variable set to: $HotfixId"
}
