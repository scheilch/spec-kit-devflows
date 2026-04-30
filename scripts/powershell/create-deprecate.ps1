#!/usr/bin/env pwsh
$ErrorActionPreference = 'Stop'

# Parse arguments
$JsonMode = $false
$ListFeatures = $false
$remainingArgs = @()

foreach ($arg in $args) {
    switch ($arg) {
        { $_ -eq '--json' -or $_ -eq '-Json' } { $JsonMode = $true }
        { $_ -eq '--list-features' -or $_ -eq '-ListFeatures' } {
            $ListFeatures = $true
            $JsonMode = $true
        }
        { $_ -eq '--help' -or $_ -eq '-h' -or $_ -eq '-Help' } {
            Write-Output "Usage: $($MyInvocation.MyCommand.Name) [--json] [--list-features] [<feature_number>] <reason>"
            Write-Output "Example: $($MyInvocation.MyCommand.Name) 014 `"low usage and high maintenance burden`""
            Write-Output "         $($MyInvocation.MyCommand.Name) --list-features `"low usage`""
            exit 0
        }
        default { $remainingArgs += $arg }
    }
}

$FeatureNum = if ($remainingArgs.Count -ge 1) { $remainingArgs[0] } else { $null }
$Reason = if ($remainingArgs.Count -ge 2) { ($remainingArgs[1..($remainingArgs.Count - 1)] -join ' ').Trim() } else { '' }

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

# List features mode
if ($ListFeatures) {
    if ([string]::IsNullOrEmpty($Reason) -and -not [string]::IsNullOrEmpty($FeatureNum)) {
        $Reason = $FeatureNum
        $FeatureNum = $null
    }
    if ([string]::IsNullOrEmpty($Reason)) {
        Write-Error '{"error":"Reason required for --list-features mode"}'
        exit 1
    }

    $features = @()
    if (Test-Path -LiteralPath $SpecsDir -PathType Container) {
        Get-ChildItem -Path $SpecsDir -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d{3}-' } |
            Sort-Object Name |
            ForEach-Object {
                $numOnly = ($_.Name -replace '^(\d+)-.*', '$1')
                $nameOnly = ($_.Name -replace '^\d+-', '')
                $features += [ordered]@{ number = $numOnly; name = $nameOnly; full = $_.Name }
            }
    }

    $result = [ordered]@{
        mode     = 'list'
        reason   = $Reason
        features = $features
    }
    $result | ConvertTo-Json -Compress -Depth 3
    exit 0
}

# Normal mode - require feature number and reason
if ([string]::IsNullOrEmpty($FeatureNum) -or [string]::IsNullOrEmpty($Reason)) {
    Write-Error "Usage: $($MyInvocation.MyCommand.Name) [--json] <feature_number> <reason>"
    exit 1
}

# Find the original feature directory
$FeatureDir = Get-ChildItem -Path $SpecsDir -Directory -Filter "${FeatureNum}-*" -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not $FeatureDir) {
    Write-Error "Feature directory not found for feature number ${FeatureNum}"
    exit 1
}

$FeatureName = $FeatureDir.Name

# Find highest deprecate number
$Highest = 0
Get-ChildItem -Path $SpecsDir -Directory -Filter "deprecate-*" -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.Name -match '^deprecate-(\d+)') {
        $num = [int]$Matches[1]
        if ($num -gt $Highest) { $Highest = $num }
    }
}

$Next = $Highest + 1
$DeprecateNum = '{0:D3}' -f $Next

# Create branch name from feature name
$FeatureShort = $FeatureName -replace '^\d+-', ''
$BranchName = "deprecate/${DeprecateNum}-${FeatureShort}"
$DeprecateId = "deprecate-${DeprecateNum}"

# Create git branch
if ($HasGit) {
    git checkout -b $BranchName
} else {
    Write-Warning "[deprecate] Warning: Git repository not detected; skipped branch creation for $BranchName"
}

# Create deprecation directory
$DeprecateDir = Join-Path $SpecsDir "${DeprecateId}-${FeatureShort}"
if (-not (Test-Path -LiteralPath $DeprecateDir -PathType Container)) {
    New-Item -ItemType Directory -Path $DeprecateDir -Force | Out-Null
}

# Copy template
$DeprecationTemplate = Join-Path $RepoRoot ".specify" "extensions" "workflows" "deprecate" "deprecation-template.md"
$DeprecationFile = Join-Path $DeprecateDir "deprecation.md"

if (Test-Path -LiteralPath $DeprecationTemplate -PathType Leaf) {
    Copy-Item -LiteralPath $DeprecationTemplate -Destination $DeprecationFile -Force
} else {
    Set-Content -Path $DeprecationFile -Value "# Deprecation Plan"
}

# Run dependency scan
$DependenciesFile = Join-Path $DeprecateDir "dependencies.md"
$ScanScript = Join-Path $RepoRoot ".specify" "extensions" "workflows" "deprecate" "scan-dependencies.ps1"

if (Test-Path -LiteralPath $ScanScript -PathType Leaf) {
    try {
        & $ScanScript $FeatureNum $DependenciesFile 2>$null
    } catch { }
} else {
    $depContent = @(
        "# Dependencies",
        "",
        "Dependency scan script not found. Please manually document dependencies."
    )
    Set-Content -Path $DependenciesFile -Value ($depContent -join "`n")
}

# Replace placeholders in deprecation.md
if (Test-Path -LiteralPath $DeprecationFile -PathType Leaf) {
    $content = Get-Content -Path $DeprecationFile -Raw

    $content = $content -replace [regex]::Escape('[FEATURE NAME]'), $FeatureShort
    $content = $content -replace [regex]::Escape('deprecate-###'), $DeprecateId
    $content = $content -replace [regex]::Escape('deprecate/###-short-description'), $BranchName

    # Replace link placeholder
    $originalLink = "[Link to original feature spec, e.g., specs/${FeatureName}/]"
    $content = $content -replace [regex]::Escape('[Link to original feature spec]'), $originalLink

    # Replace first occurrence of date placeholder
    $Today = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
    if ($content -match [regex]::Escape('[YYYY-MM-DD]')) {
        $content = $content.Remove($content.IndexOf('[YYYY-MM-DD]'), '[YYYY-MM-DD]'.Length).Insert($content.IndexOf('[YYYY-MM-DD]'), $Today)
    }

    Set-Content -Path $DeprecationFile -Value $content -NoNewline
}

# Set environment variable
$env:SPECIFY_DEPRECATE = $DeprecateId

if ($JsonMode) {
    $output = [ordered]@{
        DEPRECATE_ID      = $DeprecateId
        BRANCH_NAME       = $BranchName
        DEPRECATION_FILE  = (Resolve-Path -LiteralPath $DeprecationFile).Path
        DEPENDENCIES_FILE = (Resolve-Path -LiteralPath $DependenciesFile).Path
        DEPRECATE_NUM     = $DeprecateNum
        FEATURE_NAME      = $FeatureName
        FEATURE_NUM       = $FeatureNum
        REASON            = $Reason
    }
    $output | ConvertTo-Json -Compress
} else {
    Write-Output "DEPRECATE_ID: $DeprecateId"
    Write-Output "BRANCH_NAME: $BranchName"
    Write-Output "DEPRECATION_FILE: $DeprecationFile"
    Write-Output "DEPENDENCIES_FILE: $DependenciesFile"
    Write-Output "DEPRECATE_NUM: $DeprecateNum"
    Write-Output "FEATURE_NAME: $FeatureName"
    Write-Output "FEATURE_NUM: $FeatureNum"
    Write-Output "REASON: $Reason"
    Write-Output "SPECIFY_DEPRECATE environment variable set to: $DeprecateId"
}
