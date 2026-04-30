#!/usr/bin/env pwsh
$ErrorActionPreference = 'Stop'

# Parse arguments
$JsonMode = $false
$remainingArgs = @()

foreach ($arg in $args) {
    switch ($arg) {
        { $_ -eq '--json' -or $_ -eq '-Json' } { $JsonMode = $true }
        { $_ -eq '--help' -or $_ -eq '-h' -or $_ -eq '-Help' } {
            Write-Output "Usage: $($MyInvocation.MyCommand.Name) [--json] <refactoring_description>"
            exit 0
        }
        default { $remainingArgs += $arg }
    }
}

$RefactorDescription = ($remainingArgs -join ' ').Trim()
if ([string]::IsNullOrEmpty($RefactorDescription)) {
    Write-Error "Usage: $($MyInvocation.MyCommand.Name) [--json] <refactoring_description>"
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

# Find highest refactor number
$Highest = 0
Get-ChildItem -Path $SpecsDir -Directory -Filter "refactor-*" -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.Name -match '^refactor-(\d+)') {
        $num = [int]$Matches[1]
        if ($num -gt $Highest) { $Highest = $num }
    }
}

$Next = $Highest + 1
$RefactorNum = '{0:D3}' -f $Next

# Create branch name from description
$BranchSuffix = $RefactorDescription.ToLower() -replace '[^a-z0-9]', '-' -replace '-+', '-' -replace '^-', '' -replace '-$', ''
$Words = ($BranchSuffix -split '-' | Where-Object { $_ -ne '' } | Select-Object -First 3) -join '-'
$BranchName = "refactor/${RefactorNum}-${Words}"
$RefactorId = "refactor-${RefactorNum}"

# Create git branch
if ($HasGit) {
    git checkout -b $BranchName
} else {
    Write-Warning "[refactor] Warning: Git repository not detected; skipped branch creation for $BranchName"
}

# Create refactor directory
$RefactorDir = Join-Path $SpecsDir "${RefactorId}-${Words}"
if (-not (Test-Path -LiteralPath $RefactorDir -PathType Container)) {
    New-Item -ItemType Directory -Path $RefactorDir -Force | Out-Null
}

# Copy template
$RefactorTemplate = Join-Path $RepoRoot ".specify" "extensions" "workflows" "refactor" "refactor-template.md"
$RefactorSpecFile = Join-Path $RefactorDir "refactor-spec.md"

if (Test-Path -LiteralPath $RefactorTemplate -PathType Leaf) {
    Copy-Item -LiteralPath $RefactorTemplate -Destination $RefactorSpecFile -Force
} else {
    Set-Content -Path $RefactorSpecFile -Value "# Refactor Spec"
}

# Create placeholder for metrics
$MetricsBefore = Join-Path $RefactorDir "metrics-before.md"
$MetricsAfter = Join-Path $RefactorDir "metrics-after.md"

$metricsBeforeContent = @'
# Baseline Metrics (Before Refactoring)

**Status**: Not yet captured

Run the following command to capture baseline metrics:

```bash
.specify/extensions/workflows/refactor/measure-metrics.sh --before --dir "$REFACTOR_DIR"
```

This should be done BEFORE making any code changes.
'@

$metricsAfterContent = @'
# Post-Refactoring Metrics (After Refactoring)

**Status**: Not yet captured

Run the following command to capture post-refactoring metrics:

```bash
.specify/extensions/workflows/refactor/measure-metrics.sh --after --dir "$REFACTOR_DIR"
```

This should be done AFTER refactoring is complete and all tests pass.
'@

Set-Content -Path $MetricsBefore -Value $metricsBeforeContent
Set-Content -Path $MetricsAfter -Value $metricsAfterContent

# Create placeholder for behavioral snapshot
$BehavioralSnapshot = Join-Path $RefactorDir "behavioral-snapshot.md"
$snapshotContent = @'
# Behavioral Snapshot

**Purpose**: Document observable behavior before refactoring to verify it's preserved after.

## Key Behaviors to Preserve

### Behavior 1: [Description]
**Input**: [Specific input data/conditions]
**Expected Output**: [Exact expected result]
**Actual Output** (before): [Run and document]
**Actual Output** (after): [Re-run after refactoring - must match]

### Behavior 2: [Description]
**Input**: [Specific input data/conditions]
**Expected Output**: [Exact expected result]
**Actual Output** (before): [Run and document]
**Actual Output** (after): [Re-run after refactoring - must match]

### Behavior 3: [Description]
**Input**: [Specific input data/conditions]
**Expected Output**: [Exact expected result]
**Actual Output** (before): [Run and document]
**Actual Output** (after): [Re-run after refactoring - must match]

## Test Commands
```bash
# Commands to reproduce behaviors
npm test -- [specific test]
npm run dev # Manual testing steps...
```

---
*Update this file with actual behaviors before starting refactoring*
'@

Set-Content -Path $BehavioralSnapshot -Value $snapshotContent

# Set environment variable
$env:SPECIFY_REFACTOR = $RefactorId

if ($JsonMode) {
    $output = [ordered]@{
        REFACTOR_ID        = $RefactorId
        BRANCH_NAME        = $BranchName
        REFACTOR_SPEC_FILE = (Resolve-Path -LiteralPath $RefactorSpecFile).Path
        METRICS_BEFORE     = (Resolve-Path -LiteralPath $MetricsBefore).Path
        METRICS_AFTER      = (Resolve-Path -LiteralPath $MetricsAfter).Path
        BEHAVIORAL_SNAPSHOT = (Resolve-Path -LiteralPath $BehavioralSnapshot).Path
        REFACTOR_NUM       = $RefactorNum
    }
    $output | ConvertTo-Json -Compress
} else {
    Write-Output "REFACTOR_ID: $RefactorId"
    Write-Output "BRANCH_NAME: $BranchName"
    Write-Output "REFACTOR_SPEC_FILE: $RefactorSpecFile"
    Write-Output "METRICS_BEFORE: $MetricsBefore"
    Write-Output "METRICS_AFTER: $MetricsAfter"
    Write-Output "BEHAVIORAL_SNAPSHOT: $BehavioralSnapshot"
    Write-Output "REFACTOR_NUM: $RefactorNum"
    Write-Output "SPECIFY_REFACTOR environment variable set to: $RefactorId"
}
