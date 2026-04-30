#!/usr/bin/env pwsh
$ErrorActionPreference = 'Stop'

if ($args.Count -eq 0 -or $args[0] -eq '--help' -or $args[0] -eq '-h' -or $args[0] -eq '-Help') {
    Write-Output "Usage: $($MyInvocation.MyCommand.Name) <feature-number>"
    Write-Output "Example: $($MyInvocation.MyCommand.Name) 014"
    exit 0
}

$FeatureNum = $args[0]

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
$RepoRoot = Find-RepoRoot -StartDir $ScriptDir
if (-not $RepoRoot) {
    Write-Error "Could not find repository root"
    exit 1
}

Set-Location $RepoRoot

# Find feature directory
$FeatureDir = Get-ChildItem -Path (Join-Path $RepoRoot "specs") -Directory -Filter "${FeatureNum}-*" -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not $FeatureDir) {
    Write-Error "Could not find feature ${FeatureNum} in specs/"
    exit 1
}

$FeatureName = $FeatureDir.Name

Write-Output "Scanning impact for feature: $FeatureName"
Write-Output ""

# Source file extension pattern for multi-language scanning
$sourceExtPattern = '\.(ts|tsx|js|jsx|py|go|rs|java|rb|php|cs|cpp|c|h|hpp|swift|kt|scala|vue|svelte)$'
$pathPattern = '(app/|tests/|src/|lib/|pkg/|internal/|cmd/)[^ ]*'

# Parse tasks.md to find files created/modified
$TasksFile = Join-Path $FeatureDir.FullName "tasks.md"
$FilesAffected = @()

if (Test-Path -LiteralPath $TasksFile -PathType Leaf) {
    Write-Output "=== Files from Original Implementation ==="
    $content = Get-Content -Path $TasksFile -Raw
    $matches_ = [regex]::Matches($content, "${pathPattern}${sourceExtPattern}")
    $FilesAffected = $matches_ | ForEach-Object { $_.Value } | Sort-Object -Unique

    foreach ($file in $FilesAffected) {
        $fullPath = Join-Path $RepoRoot $file
        if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
            Write-Output "  - $file"
        }
    }
    Write-Output ""
}

# Find contracts
$ContractsDir = Join-Path $FeatureDir.FullName "contracts"
if (Test-Path -LiteralPath $ContractsDir -PathType Container) {
    Write-Output "=== Contracts from Original Feature ==="
    Get-ChildItem -Path $ContractsDir -File -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Output "  - $($_.Name)"
    }
    Write-Output ""
}

# Search codebase for references
Write-Output "=== References in Codebase ==="
$SpecFile = Join-Path $FeatureDir.FullName "spec.md"
if (Test-Path -LiteralPath $SpecFile -PathType Leaf) {
    Write-Output "  (Scan for feature-specific imports/references)"
    Write-Output "  Run: Select-String -Path 'app/**','src/**','lib/**' -Pattern '<feature-terms>'"
    Write-Output ""
}

# Check for database schema
Write-Output "=== Database Schema Check ==="
$DataModel = Join-Path $FeatureDir.FullName "data-model.md"
if (Test-Path -LiteralPath $DataModel -PathType Leaf) {
    Write-Output "  Original feature has data model - check for schema changes needed"
    Write-Output "  File: $DataModel"
} else {
    Write-Output "  No data model in original feature"
}
Write-Output ""

# Output summary
Write-Output "=== Summary ==="
Write-Output "Feature: $FeatureName"
Write-Output "Files tracked: $($FilesAffected.Count)"
Write-Output "Tasks file: $TasksFile"
Write-Output "Contracts: $ContractsDir"
Write-Output ""
Write-Output "Next steps:"
Write-Output "1. Review files above for modification needs"
Write-Output "2. Check which tests will break"
Write-Output "3. Identify new contracts needed"
Write-Output "4. Document in modification-spec.md"
