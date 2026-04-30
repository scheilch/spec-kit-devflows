#!/usr/bin/env pwsh
$ErrorActionPreference = 'Stop'

# Parse arguments
$Mode = $null
$RefactorDir = $null

$i = 0
while ($i -lt $args.Count) {
    switch ($args[$i]) {
        '--before'  { $Mode = 'before'; $i++ }
        '-Before'   { $Mode = 'before'; $i++ }
        '--after'   { $Mode = 'after'; $i++ }
        '-After'    { $Mode = 'after'; $i++ }
        '--dir'     { $RefactorDir = $args[$i + 1]; $i += 2 }
        '-Dir'      { $RefactorDir = $args[$i + 1]; $i += 2 }
        { $_ -eq '--help' -or $_ -eq '-h' -or $_ -eq '-Help' } {
            Write-Output "Usage: $($MyInvocation.MyCommand.Name) --before|--after [--dir <refactor-dir>]"
            Write-Output ""
            Write-Output "Captures code metrics for refactoring validation"
            Write-Output ""
            Write-Output "Options:"
            Write-Output "  --before    Capture baseline metrics before refactoring"
            Write-Output "  --after     Capture metrics after refactoring"
            Write-Output "  --dir       Refactor directory (auto-detected if not provided)"
            exit 0
        }
        default {
            Write-Error "Unknown option: $($args[$i])"
            exit 1
        }
    }
}

if (-not $Mode) {
    Write-Error "Must specify --before or --after"
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
    Write-Error "Could not find repository root"
    exit 1
}

Set-Location $RepoRoot

# Auto-detect refactor directory if not provided
if (-not $RefactorDir) {
    $RefactorDir = Get-ChildItem -Path (Join-Path $RepoRoot "specs") -Directory -Filter "refactor-*" -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $RefactorDir) {
        Write-Error "No refactor directory found. Use --dir to specify."
        exit 1
    }
}

$ModeTitle = (Get-Culture).TextInfo.ToTitleCase($Mode)
$OutputFile = Join-Path $RefactorDir "metrics-${Mode}.md"

Write-Host "Capturing ${Mode} metrics to: $OutputFile" -ForegroundColor DarkGray
Write-Host ""

# Get git info
$gitCommit = "N/A"
$gitBranch = "N/A"
if (Get-Command git -ErrorAction SilentlyContinue) {
    try {
        $result = git rev-parse --short HEAD 2>$null
        if ($LASTEXITCODE -eq 0) { $gitCommit = $result }
        $result = git branch --show-current 2>$null
        if ($LASTEXITCODE -eq 0) { $gitBranch = $result }
    } catch { }
}

# Start output
$output = @()
$output += "# Metrics Captured $ModeTitle Refactoring"
$output += ""
$output += "**Timestamp**: $(Get-Date)"
$output += "**Git Commit**: $gitCommit"
$output += "**Branch**: $gitBranch"
$output += ""
$output += "---"
$output += ""

# Code Complexity Metrics
$output += "## Code Complexity"
$output += ""

# Lines of Code
$output += "### Lines of Code"

$clocAvailable = $null -ne (Get-Command cloc -ErrorAction SilentlyContinue)
$sourceDirs = @('app', 'src', 'lib', 'pkg', 'internal', 'cmd') | ForEach-Object { Join-Path $RepoRoot $_ } | Where-Object { Test-Path -LiteralPath $_ -PathType Container }

if ($clocAvailable -and $sourceDirs.Count -gt 0) {
    Write-Host "Running cloc analysis..." -ForegroundColor DarkGray
    $output += '```'
    try {
        $clocOutput = & cloc @sourceDirs --quiet 2>$null
        $output += $clocOutput
    } catch {
        $output += "cloc failed"
    }
    $output += '```'
} else {
    $output += "Source file counts (cloc not installed - using file count):"
    $output += ""
    if ($sourceDirs.Count -gt 0) {
        foreach ($dir in $sourceDirs) {
            $files = Get-ChildItem -Path $dir -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -match '\.(ts|tsx|js|jsx|py|go|rs|java|rb|php|cs|cpp|c|h|hpp|swift|kt|scala)$' }
            $fileCount = ($files | Measure-Object).Count
            $totalLines = ($files | ForEach-Object { (Get-Content -Path $_.FullName -ErrorAction SilentlyContinue).Count } | Measure-Object -Sum).Sum
            $dirName = Split-Path $dir -Leaf
            $output += "- **$dirName/**: $fileCount files, $totalLines lines"
        }
    } else {
        $output += "- No standard source directories found"
    }
}
$output += ""

# File Sizes
$output += "### Largest Files"
$output += '```'
if ($sourceDirs.Count -gt 0) {
    $largestFiles = foreach ($dir in $sourceDirs) {
        Get-ChildItem -Path $dir -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -match '\.(ts|tsx|js|jsx|py|go|rs|java|rb|php|cs|cpp|c|h|hpp|swift|kt|scala)$' } |
            ForEach-Object {
                $lineCount = (Get-Content -Path $_.FullName -ErrorAction SilentlyContinue).Count
                [PSCustomObject]@{ Lines = $lineCount; File = $_.FullName.Substring($RepoRoot.Length + 1) -replace '\\', '/' }
            }
    }
    $largestFiles | Sort-Object Lines -Descending | Select-Object -First 10 | ForEach-Object {
        $output += "  $($_.Lines) $($_.File)"
    }
    if (-not $largestFiles) {
        $output += "No source files found"
    }
} else {
    $output += "No source directories found"
}
$output += '```'
$output += ""

# Dependencies
$output += "## Dependencies"
$output += ""

$depFiles = @('package.json', 'requirements.txt', 'go.mod', 'Cargo.toml', 'Gemfile', 'composer.json', 'pom.xml', 'build.gradle')
$depFound = $false
foreach ($depFile in $depFiles) {
    $depPath = Join-Path $RepoRoot $depFile
    if (Test-Path -LiteralPath $depPath -PathType Leaf) {
        $depFound = $true
        $output += "- **Dependency file**: ``$depFile`` found"
    }
}
if (-not $depFound) {
    $output += "- No standard dependency files found"
}
$output += ""

# Test Suite Stats
$output += "## Test Suite"
$output += ""

$testDirs = @('tests', 'test', 'spec') | ForEach-Object { Join-Path $RepoRoot $_ } | Where-Object { Test-Path -LiteralPath $_ -PathType Container }
$testFileCount = 0
foreach ($testDir in $testDirs) {
    $testFileCount += (Get-ChildItem -Path $testDir -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '\.(test|spec)\.' }).Count
}
# Also check for test files in source dirs
foreach ($dir in $sourceDirs) {
    $testFileCount += (Get-ChildItem -Path $dir -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '\.(test|spec)\.' }).Count
}

$output += "- **Test Files**: $testFileCount"

if ($Mode -eq 'before') {
    $output += "- **Test Pass Rate**: Run your test suite to verify 100%"
} else {
    $output += "- **Test Pass Rate**: Should be 100% (verify with your test command)"
}
$output += ""

Set-Content -Path $OutputFile -Value ($output -join "`n")
Write-Host "Metrics written to $OutputFile" -ForegroundColor Green
