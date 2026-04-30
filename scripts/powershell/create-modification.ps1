#!/usr/bin/env pwsh
$ErrorActionPreference = 'Stop'

# Source common functions from spec-kit
$ScriptDir = $PSScriptRoot

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
$ListFeatures = $false
$FeatureNum = $null
$ModDescription = ''

$i = 0
while ($i -lt $args.Count) {
    switch ($args[$i]) {
        { $_ -eq '--json' -or $_ -eq '-Json' } { $JsonMode = $true; $i++ }
        { $_ -eq '--list-features' -or $_ -eq '-ListFeatures' } {
            $ListFeatures = $true
            $JsonMode = $true
            $i++
        }
        { $_ -eq '--help' -or $_ -eq '-h' -or $_ -eq '-Help' } {
            Write-Output "Usage: $($MyInvocation.MyCommand.Name) [--json] [--list-features] [<feature-number>] <modification-description>"
            Write-Output "Example: $($MyInvocation.MyCommand.Name) 014 `"Add phone number field to profile`""
            Write-Output "         $($MyInvocation.MyCommand.Name) --list-features `"Add phone number field`""
            exit 0
        }
        default {
            if (-not $FeatureNum) {
                $FeatureNum = $args[$i]
            } else {
                if ($ModDescription) { $ModDescription += ' ' }
                $ModDescription += $args[$i]
            }
            $i++
        }
    }
}

$ModDescription = $ModDescription.Trim()

# Use spec-kit common functions
$RepoRoot = Get-RepoRoot
$HasGit = Test-HasGit

Set-Location $RepoRoot

$SpecsDir = Join-Path $RepoRoot "specs"

# List features mode
if ($ListFeatures) {
    if ([string]::IsNullOrEmpty($ModDescription) -and -not [string]::IsNullOrEmpty($FeatureNum)) {
        $ModDescription = $FeatureNum
        $FeatureNum = $null
    }
    if ([string]::IsNullOrEmpty($ModDescription)) {
        Write-Error '{"error":"Description required for --list-features mode"}'
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
        mode        = 'list'
        description = $ModDescription
        features    = $features
    }
    $result | ConvertTo-Json -Compress -Depth 3
    exit 0
}

# Normal mode - require feature number
if ([string]::IsNullOrEmpty($FeatureNum) -or [string]::IsNullOrEmpty($ModDescription)) {
    Write-Error "Usage: $($MyInvocation.MyCommand.Name) [--json] <feature-number> <modification-description>"
    exit 1
}

# Find original feature directory
$FeatureDir = Get-ChildItem -Path $SpecsDir -Directory -Filter "${FeatureNum}-*" -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not $FeatureDir) {
    Write-Error "Could not find feature ${FeatureNum} in specs/"
    exit 1
}

$FeatureName = $FeatureDir.Name

# Find highest modification number for this feature
$ModificationsDir = Join-Path $FeatureDir.FullName "modifications"
if (-not (Test-Path -LiteralPath $ModificationsDir -PathType Container)) {
    New-Item -ItemType Directory -Path $ModificationsDir -Force | Out-Null
}

$HighestMod = 0
Get-ChildItem -Path $ModificationsDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.Name -match '^(\d+)') {
        $num = [int]$Matches[1]
        if ($num -gt $HighestMod) { $HighestMod = $num }
    }
}

$NextMod = $HighestMod + 1
$ModNum = '{0:D3}' -f $NextMod

# Create branch name from description
$BranchSuffix = $ModDescription.ToLower() -replace '[^a-z0-9]', '-' -replace '-+', '-' -replace '^-', '' -replace '-$', ''
$Words = ($BranchSuffix -split '-' | Where-Object { $_ -ne '' } | Select-Object -First 3) -join '-'
$BranchName = "${FeatureNum}-mod-${ModNum}-${Words}"
$ModId = "${FeatureNum}-mod-${ModNum}"

# Create git branch
if ($HasGit) {
    git checkout -b $BranchName
} else {
    Write-Warning "[modify] Warning: Git repository not detected; skipped branch creation for $BranchName"
}

# Create modification directory
$ModDir = Join-Path $ModificationsDir "${ModNum}-${Words}"
if (-not (Test-Path -LiteralPath $ModDir -PathType Container)) {
    New-Item -ItemType Directory -Path $ModDir -Force | Out-Null
}
$contractsDir = Join-Path $ModDir "contracts"
if (-not (Test-Path -LiteralPath $contractsDir -PathType Container)) {
    New-Item -ItemType Directory -Path $contractsDir -Force | Out-Null
}

# Copy template
$ModifyTemplate = Join-Path $RepoRoot ".specify" "extensions" "workflows" "modify" "modification-template.md"
$ModSpecFile = Join-Path $ModDir "modification-spec.md"

if (Test-Path -LiteralPath $ModifyTemplate -PathType Leaf) {
    Copy-Item -LiteralPath $ModifyTemplate -Destination $ModSpecFile -Force
} else {
    Set-Content -Path $ModSpecFile -Value "# Modification Spec"
}

# Run impact analysis
$ImpactScanner = Join-Path $RepoRoot ".specify" "extensions" "workflows" "modify" "scan-impact.ps1"
$ImpactFile = Join-Path $ModDir "impact-analysis.md"

if (Test-Path -LiteralPath $ImpactScanner -PathType Leaf) {
    $impactHeader = @(
        "# Impact Analysis for ${FeatureName}",
        "",
        "**Generated**: $(Get-Date)",
        "**Modification**: ${ModDescription}",
        ""
    )
    Set-Content -Path $ImpactFile -Value ($impactHeader -join "`n")
    try {
        $impactOutput = & $ImpactScanner $FeatureNum 2>&1
        Add-Content -Path $ImpactFile -Value ($impactOutput -join "`n")
    } catch { }
} else {
    Set-Content -Path $ImpactFile -Value "# Impact Analysis`nImpact scanner not found - manual analysis required"
}

# Set environment variable
$env:SPECIFY_MODIFICATION = $ModId

if ($JsonMode) {
    $output = [ordered]@{
        MOD_ID        = $ModId
        BRANCH_NAME   = $BranchName
        MOD_SPEC_FILE = (Resolve-Path -LiteralPath $ModSpecFile).Path
        IMPACT_FILE   = (Resolve-Path -LiteralPath $ImpactFile).Path
        FEATURE_NAME  = $FeatureName
    }
    $output | ConvertTo-Json -Compress
} else {
    Write-Output "MOD_ID: $ModId"
    Write-Output "BRANCH_NAME: $BranchName"
    Write-Output "MOD_SPEC_FILE: $ModSpecFile"
    Write-Output "IMPACT_FILE: $ImpactFile"
    Write-Output "FEATURE_NAME: $FeatureName"
    Write-Output "SPECIFY_MODIFICATION environment variable set to: $ModId"
}
