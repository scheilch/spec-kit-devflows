#!/usr/bin/env pwsh
$ErrorActionPreference = 'Stop'

param(
    [Parameter(Position = 0)]
    [string]$FeatureNum,
    [Parameter(Position = 1)]
    [string]$OutputFile
)

# Re-parse from $args if param binding didn't work (called without named params)
if ([string]::IsNullOrEmpty($FeatureNum) -and $args.Count -ge 1) { $FeatureNum = $args[0] }
if ([string]::IsNullOrEmpty($OutputFile) -and $args.Count -ge 2) { $OutputFile = $args[1] }

if ([string]::IsNullOrEmpty($FeatureNum) -or [string]::IsNullOrEmpty($OutputFile)) {
    Write-Error "Usage: $($MyInvocation.MyCommand.Name) <feature_number> <output_file>"
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
$RepoRoot = Find-RepoRoot -StartDir $ScriptDir
if (-not $RepoRoot) {
    Write-Error "Could not determine repository root"
    exit 1
}

Set-Location $RepoRoot

# Find the feature directory
$FeatureDir = Get-ChildItem -Path (Join-Path $RepoRoot "specs") -Directory -Filter "${FeatureNum}-*" -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not $FeatureDir) {
    Write-Error "Feature directory not found for feature number ${FeatureNum}"
    exit 1
}

$FeatureName = $FeatureDir.Name

# Source file extensions for multi-language scanning
$sourceExtensions = @('*.ts', '*.tsx', '*.js', '*.jsx', '*.py', '*.go', '*.rs', '*.java', '*.rb', '*.php', '*.cs', '*.cpp', '*.c', '*.h', '*.hpp', '*.swift', '*.kt', '*.scala', '*.vue', '*.svelte')
$sourceExtPattern = '\.(ts|tsx|js|jsx|py|go|rs|java|rb|php|cs|cpp|c|h|hpp|swift|kt|scala|vue|svelte)$'
$pathPattern = '(app/|tests/|src/|lib/|pkg/|internal/|cmd/)[^ ]*'

# Start output
$output = @()
$output += "# Dependency Scan Results"
$output += ""
$output += "**Feature**: $FeatureName"
$output += "**Scan Date**: $((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss')) UTC"
$output += ""
$output += "---"
$output += ""

# Extract files from tasks.md or plan.md
$TasksFile = Join-Path $FeatureDir.FullName "tasks.md"
$PlanFile = Join-Path $FeatureDir.FullName "plan.md"
$FeatureFiles = @()

$scanSource = $null
if (Test-Path -LiteralPath $TasksFile -PathType Leaf) {
    $scanSource = $TasksFile
    Write-Host "Scanning tasks.md for feature files..." -ForegroundColor DarkGray
} elseif (Test-Path -LiteralPath $PlanFile -PathType Leaf) {
    $scanSource = $PlanFile
    Write-Host "Scanning plan.md for feature files..." -ForegroundColor DarkGray
}

if ($scanSource) {
    $content = Get-Content -Path $scanSource -Raw
    $matches_ = [regex]::Matches($content, "${pathPattern}${sourceExtPattern}")
    $FeatureFiles = $matches_ | ForEach-Object { $_.Value } | Sort-Object -Unique
}

if ($FeatureFiles.Count -eq 0) {
    $output += "## ⚠️ Warning: No Feature Files Found"
    $output += ""
    $output += "Could not automatically detect files created by this feature."
    $output += "Please manually list the files in this section."
    $output += ""
    Set-Content -Path $OutputFile -Value ($output -join "`n")
    exit 0
}

$output += "## Feature Files (Created by This Feature)"
$output += ""
$output += "These files were created as part of feature ${FeatureName}:"
$output += ""

foreach ($file in $FeatureFiles) {
    $fullPath = Join-Path $RepoRoot $file
    if (Test-Path -LiteralPath $fullPath -PathType Leaf) {
        $loc = (Get-Content -Path $fullPath).Count
        $output += "- ``$file`` ($loc lines)"
    } else {
        $output += "- ``$file`` (file not found - may have been moved/renamed)"
    }
}

$output += ""
$output += "---"
$output += ""

# Scan for code dependencies (imports/usage) - language-agnostic
$output += "## Code Dependencies (Other Files Importing Feature Files)"
$output += ""
$output += "Other parts of the codebase that import or reference this feature's files:"
$output += ""

$dependenciesFound = $false
$searchDirs = @('app', 'src', 'lib', 'pkg', 'internal', 'cmd') | ForEach-Object { Join-Path $RepoRoot $_ } | Where-Object { Test-Path -LiteralPath $_ -PathType Container }

# Import patterns for multiple languages
$importPatterns = @(
    'from\s+[''"]',     # Python/JS/TS
    'import\s+[''"]',   # JS/TS/Java/Go
    'require\s*\(',     # Node.js
    '#include\s*[<"]',  # C/C++
    'use\s+',           # Rust/PHP
    'using\s+'          # C#
)

foreach ($featureFile in $FeatureFiles) {
    $modulePath = [System.IO.Path]::GetFileNameWithoutExtension($featureFile)
    $moduleDir = [System.IO.Path]::GetDirectoryName($featureFile) -replace '\\', '/'

    if ($searchDirs.Count -gt 0) {
        $importingFiles = @()
        foreach ($dir in $searchDirs) {
            $found = Get-ChildItem -Path $dir -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -match $sourceExtPattern } |
                ForEach-Object {
                    $content = Get-Content -Path $_.FullName -Raw -ErrorAction SilentlyContinue
                    if ($content -and ($content -match [regex]::Escape($modulePath))) {
                        $_.FullName
                    }
                }
            if ($found) { $importingFiles += $found }
        }

        $importingFiles = $importingFiles | Where-Object { $_ -notmatch [regex]::Escape($featureFile) } | Sort-Object -Unique

        if ($importingFiles.Count -gt 0) {
            $dependenciesFound = $true
            $output += "### Files importing ``$featureFile``:"
            $output += ""
            foreach ($imp in $importingFiles) {
                $relativePath = $imp.Substring($RepoRoot.Length + 1) -replace '\\', '/'
                $output += "- ``$relativePath``"
            }
            $output += ""
        }
    }
}

if (-not $dependenciesFound) {
    $output += "✅ No external dependencies found. This feature appears to be isolated."
    $output += ""
}

$output += "---"
$output += ""

# Scan for test dependencies
$output += "## Test Dependencies"
$output += ""

$testDirs = @('tests', 'test', 'spec') | ForEach-Object { Join-Path $RepoRoot $_ } | Where-Object { Test-Path -LiteralPath $_ -PathType Container }
$testDepsFound = $false

if ($testDirs.Count -gt 0) {
    foreach ($featureFile in $FeatureFiles) {
        $modulePath = [System.IO.Path]::GetFileNameWithoutExtension($featureFile)
        foreach ($testDir in $testDirs) {
            $testMatches = Get-ChildItem -Path $testDir -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '\.(test|spec)\.' } |
                ForEach-Object {
                    $content = Get-Content -Path $_.FullName -Raw -ErrorAction SilentlyContinue
                    if ($content -and ($content -match [regex]::Escape($modulePath))) {
                        $_.FullName
                    }
                }
            if ($testMatches) {
                $testDepsFound = $true
                $output += "Tests referencing ``$featureFile``:"
                $output += ""
                foreach ($t in $testMatches) {
                    $relativePath = $t.Substring($RepoRoot.Length + 1) -replace '\\', '/'
                    $output += "- ``$relativePath``"
                }
                $output += ""
            }
        }
    }
}

if (-not $testDepsFound) {
    $output += "✅ No test dependencies found."
    $output += ""
}

Set-Content -Path $OutputFile -Value ($output -join "`n")
