# clean-flutter-projects.ps1

$ErrorActionPreference = "Stop"

# ============================================================
# Helpers
# ============================================================

function Get-FolderSize {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        return [long]0
    }

    try {
        $size = (
            Get-ChildItem $Path -File -Recurse -Force -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum
        ).Sum

        if ($null -eq $size) {
            return [long]0
        }

        return [long]$size
    }
    catch {
        return [long]0
    }
}

function Format-FileSize {
    param([long]$Bytes)

    if ($Bytes -ge 1TB) {
        return "{0:N2} TB" -f ($Bytes / 1TB)
    }

    if ($Bytes -ge 1GB) {
        return "{0:N2} GB" -f ($Bytes / 1GB)
    }

    if ($Bytes -ge 1MB) {
        return "{0:N2} MB" -f ($Bytes / 1MB)
    }

    if ($Bytes -ge 1KB) {
        return "{0:N2} KB" -f ($Bytes / 1KB)
    }

    return "$Bytes B"
}

function Get-FvmProjectVersion {
    param([string]$ProjectPath)

    $configPath = Join-Path $ProjectPath ".fvm\fvm_config.json"

    if (-not (Test-Path $configPath)) {
        return $null
    }

    try {
        $config = Get-Content $configPath -Raw | ConvertFrom-Json

        if ([string]::IsNullOrWhiteSpace($config.flutterSdkVersion)) {
            return $null
        }

        return $config.flutterSdkVersion
    }
    catch {
        return $null
    }
}

# ============================================================
# Header
# ============================================================

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Flutter Projects Cleaner"
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# 1. Check FVM
# ============================================================

if (-not (Get-Command fvm -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: FVM is not installed or not available in PATH." -ForegroundColor Red
    exit 1
}

Write-Host "Installed FVM / Flutter versions:" -ForegroundColor Yellow
Write-Host ""

fvm list

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "ERROR: Failed to execute 'fvm list'." -ForegroundColor Red
    exit 1
}

Write-Host ""

# ============================================================
# 2. Detect FVM cache
# ============================================================

$fvmCacheCandidates = @(
    (Join-Path $env:USERPROFILE "fvm\versions"),
    (Join-Path $env:LOCALAPPDATA "fvm\versions")
)

$fvmCachePath = $null

foreach ($candidate in $fvmCacheCandidates) {
    if (Test-Path $candidate) {
        $fvmCachePath = $candidate
        break
    }
}

if ([string]::IsNullOrWhiteSpace($fvmCachePath)) {
    Write-Host "ERROR: Could not find FVM versions directory." -ForegroundColor Red
    Write-Host ""
    Write-Host "Checked:" -ForegroundColor DarkGray

    foreach ($candidate in $fvmCacheCandidates) {
        Write-Host "  $candidate" -ForegroundColor DarkGray
    }

    exit 1
}

$installedVersions = @(
    Get-ChildItem $fvmCachePath -Directory |
        Select-Object -ExpandProperty Name
)

if ($installedVersions.Count -eq 0) {
    Write-Host "ERROR: No Flutter SDK is installed through FVM." -ForegroundColor Red
    exit 1
}

Write-Host "Detected installed SDKs:" -ForegroundColor Yellow

foreach ($version in $installedVersions) {
    Write-Host "  - $version" -ForegroundColor DarkGray
}

Write-Host ""

# ============================================================
# 3. Detect FVM global/default Flutter SDK
# ============================================================

$fvmRootPath = Split-Path $fvmCachePath -Parent
$fvmDefaultPath = Join-Path $fvmRootPath "default"

if (-not (Test-Path $fvmDefaultPath)) {
    Write-Host "ERROR: FVM global/default SDK is not configured." -ForegroundColor Red
    Write-Host ""
    Write-Host "Set one first using:" -ForegroundColor Yellow
    Write-Host "  fvm global <version>" -ForegroundColor Yellow
    exit 1
}

$globalFlutterPath = Join-Path $fvmDefaultPath "bin\flutter.bat"

if (-not (Test-Path $globalFlutterPath)) {
    Write-Host "ERROR: Flutter executable was not found in FVM default SDK." -ForegroundColor Red
    Write-Host ""
    Write-Host "Expected:" -ForegroundColor DarkGray
    Write-Host "  $globalFlutterPath" -ForegroundColor DarkGray
    exit 1
}

# ------------------------------------------------------------
# Determine actual global Flutter version from the SDK
# ------------------------------------------------------------

$globalVersion = $null

try {
    $versionJsonPath = Join-Path $fvmDefaultPath "bin\cache\flutter.version.json"

    if (Test-Path $versionJsonPath) {
        $versionJson = Get-Content $versionJsonPath -Raw | ConvertFrom-Json
        $globalVersion = $versionJson.frameworkVersion
    }

    # Fallback if flutter.version.json does not exist
    if ([string]::IsNullOrWhiteSpace($globalVersion)) {
        $versionOutput = & $globalFlutterPath --version --machine | ConvertFrom-Json
        $globalVersion = $versionOutput.frameworkVersion
    }
}
catch {
    Write-Host "ERROR: Could not determine Flutter version from FVM default SDK." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor DarkGray
    exit 1
}

if ([string]::IsNullOrWhiteSpace($globalVersion)) {
    Write-Host "ERROR: FVM global Flutter version is empty." -ForegroundColor Red
    exit 1
}

Write-Host "FVM cache  : $fvmCachePath" -ForegroundColor DarkGray
Write-Host "FVM default: $fvmDefaultPath" -ForegroundColor DarkGray
Write-Host "FVM global : $globalVersion" -ForegroundColor Green
Write-Host ""

# ============================================================
# 4. Find projects
# ============================================================

$projects = @(
    Get-ChildItem -Directory | Where-Object {
        Test-Path (Join-Path $_.FullName "pubspec.yaml")
    }
)

if ($projects.Count -eq 0) {
    Write-Host "No Flutter/Dart projects found." -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($projects.Count) project(s)." -ForegroundColor Yellow
Write-Host ""

# ============================================================
# Statistics
# ============================================================

$cleaned = 0
$skipped = 0
$failed = 0

$totalBuildFreed = [long]0
$totalDartToolFreed = [long]0

$results = @()

# Decision for projects whose configured FVM version
# is no longer installed:
#
# $null    = Ask for each project
# "global" = Use global for all remaining missing versions
# "skip"   = Skip all remaining missing versions

$missingVersionDecision = $null

# ============================================================
# 5. Process projects
# ============================================================

foreach ($project in $projects) {

    Write-Host "----------------------------------------" -ForegroundColor DarkGray
    Write-Host "Project: $($project.Name)" -ForegroundColor Cyan

    $projectVersion = Get-FvmProjectVersion $project.FullName

    $cleanMode = $null
    $cleanVersion = $null

    # --------------------------------------------------------
    # CASE 1:
    # Project has no local FVM configuration.
    #
    # Use FVM global/default SDK.
    # --------------------------------------------------------

    if ([string]::IsNullOrWhiteSpace($projectVersion)) {

        Write-Host "FVM config : Not configured" -ForegroundColor DarkGray
        Write-Host "FVM global : $globalVersion" -ForegroundColor Green

        $cleanMode = "global"
        $cleanVersion = $globalVersion
    }

    # --------------------------------------------------------
    # CASE 2:
    # Project has FVM config and SDK is still installed.
    # --------------------------------------------------------

    elseif ($projectVersion -in $installedVersions) {

        Write-Host "FVM config : $projectVersion" -ForegroundColor DarkGray
        Write-Host "Status     : Installed" -ForegroundColor Green

        $cleanMode = "project"
        $cleanVersion = $projectVersion
    }

    # --------------------------------------------------------
    # CASE 3:
    # Project has FVM config but SDK was removed.
    # --------------------------------------------------------

    else {

        Write-Host "FVM config : $projectVersion" -ForegroundColor DarkGray
        Write-Host "Status     : NOT INSTALLED" -ForegroundColor Yellow
        Write-Host "FVM global : $globalVersion" -ForegroundColor DarkGray
        Write-Host ""

        # ----------------------------------------------------
        # Previous "use global for all" decision
        # ----------------------------------------------------

        if ($missingVersionDecision -eq "global") {

            Write-Host "Using previous decision:" -ForegroundColor DarkGray
            Write-Host "Use FVM global $globalVersion" -ForegroundColor Green

            $cleanMode = "global"
            $cleanVersion = $globalVersion
        }

        # ----------------------------------------------------
        # Previous "skip all" decision
        # ----------------------------------------------------

        elseif ($missingVersionDecision -eq "skip") {

            Write-Host "SKIPPED: Configured Flutter $projectVersion is not installed." -ForegroundColor Yellow
            Write-Host "         Using previous 'Skip All' decision." -ForegroundColor DarkGray

            $skipped++
            continue
        }

        # ----------------------------------------------------
        # Ask user
        # ----------------------------------------------------

        else {

            while ($true) {

                Write-Host "Configured Flutter $projectVersion is not installed." -ForegroundColor Yellow
                Write-Host ""
                Write-Host "  [1] Clean using FVM global ($globalVersion)"
                Write-Host "  [2] Skip this project"
                Write-Host "  [A] Use FVM global for ALL missing versions"
                Write-Host "  [S] Skip ALL projects with missing versions"
                Write-Host ""

                $choice = Read-Host "Choose"

                switch ($choice.ToUpper()) {

                    "1" {
                        $cleanMode = "global"
                        $cleanVersion = $globalVersion
                    }

                    "2" {
                        $cleanMode = "skip"
                    }

                    "A" {
                        $missingVersionDecision = "global"
                        $cleanMode = "global"
                        $cleanVersion = $globalVersion
                    }

                    "S" {
                        $missingVersionDecision = "skip"
                        $cleanMode = "skip"
                    }

                    default {
                        Write-Host ""
                        Write-Host "Invalid option. Please choose 1, 2, A, or S." -ForegroundColor Red
                        Write-Host ""
                    }
                }

                if ($cleanMode) {
                    break
                }
            }

            if ($cleanMode -eq "skip") {
                Write-Host ""
                Write-Host "SKIPPED: $($project.Name)" -ForegroundColor Yellow

                $skipped++
                continue
            }
        }
    }

    # ========================================================
    # Calculate cache size BEFORE cleaning
    # ========================================================

    $buildPath = Join-Path $project.FullName "build"
    $dartToolPath = Join-Path $project.FullName ".dart_tool"

    Write-Host ""
    Write-Host "Calculating cache size..." -ForegroundColor DarkGray

    $buildBefore = Get-FolderSize $buildPath
    $dartToolBefore = Get-FolderSize $dartToolPath

    $totalBefore = $buildBefore + $dartToolBefore

    Write-Host "Cache before clean:" -ForegroundColor DarkGray
    Write-Host "  build      : $(Format-FileSize $buildBefore)" -ForegroundColor DarkGray
    Write-Host "  .dart_tool : $(Format-FileSize $dartToolBefore)" -ForegroundColor DarkGray
    Write-Host "  Total      : $(Format-FileSize $totalBefore)" -ForegroundColor DarkGray

    # ========================================================
    # Clean
    # ========================================================

    Push-Location $project.FullName

    try {

        Write-Host ""

        # ----------------------------------------------------
        # Project SDK exists.
        #
        # FVM can safely resolve its local configuration.
        # ----------------------------------------------------

        if ($cleanMode -eq "project") {

            Write-Host "Running: fvm flutter clean" -ForegroundColor Green
            Write-Host "Flutter: $cleanVersion (project FVM)" -ForegroundColor DarkGray

            & fvm flutter clean
        }

        # ----------------------------------------------------
        # No project FVM config OR configured SDK is missing.
        #
        # Run FVM's global/default Flutter executable directly.
        #
        # This deliberately bypasses stale local FVM config
        # without modifying .fvm/fvm_config.json.
        # ----------------------------------------------------

        else {

            Write-Host "Running Flutter clean using FVM global SDK" -ForegroundColor Green
            Write-Host "Flutter: $cleanVersion (FVM global)" -ForegroundColor DarkGray

            & $globalFlutterPath clean
        }

        # ----------------------------------------------------
        # Check command result
        # ----------------------------------------------------

        if ($LASTEXITCODE -eq 0) {

            # =================================================
            # Calculate cache size AFTER cleaning
            # =================================================

            $buildAfter = Get-FolderSize $buildPath
            $dartToolAfter = Get-FolderSize $dartToolPath

            $freedBuild = [Math]::Max(
                [long]0,
                [long]($buildBefore - $buildAfter)
            )

            $freedDartTool = [Math]::Max(
                [long]0,
                [long]($dartToolBefore - $dartToolAfter)
            )

            $totalFreed = $freedBuild + $freedDartTool

            $totalBuildFreed += $freedBuild
            $totalDartToolFreed += $freedDartTool

            Write-Host ""
            Write-Host "SUCCESS: $($project.Name)" -ForegroundColor Green
            Write-Host "Flutter : $cleanVersion" -ForegroundColor DarkGray
            Write-Host "Freed:" -ForegroundColor Green
            Write-Host "  build      : $(Format-FileSize $freedBuild)" -ForegroundColor Green
            Write-Host "  .dart_tool : $(Format-FileSize $freedDartTool)" -ForegroundColor Green
            Write-Host "  Total      : $(Format-FileSize $totalFreed)" -ForegroundColor Green

            $cleaned++

            $results += [PSCustomObject]@{
                Project  = $project.Name
                Flutter  = $cleanVersion
                Build    = Format-FileSize $freedBuild
                DartTool = Format-FileSize $freedDartTool
                Total    = Format-FileSize $totalFreed
            }
        }
        else {

            Write-Host ""
            Write-Host "FAILED: $($project.Name)" -ForegroundColor Red
            Write-Host "Exit code: $LASTEXITCODE" -ForegroundColor DarkGray

            $failed++
        }
    }
    catch {

        Write-Host ""
        Write-Host "FAILED: $($project.Name)" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor DarkGray

        $failed++
    }
    finally {

        Pop-Location
    }

    Write-Host ""
}

# ============================================================
# 6. Calculate total
# ============================================================

$totalFreed = $totalBuildFreed + $totalDartToolFreed

# ============================================================
# 7. Per-project results
# ============================================================

if ($results.Count -gt 0) {

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host " Space Freed Per Project"
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    $results | Format-Table -AutoSize
}

# ============================================================
# 8. Summary
# ============================================================

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Cleaning Summary"
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "Cleaned : $cleaned" -ForegroundColor Green
Write-Host "Skipped : $skipped" -ForegroundColor Yellow
Write-Host "Failed  : $failed" -ForegroundColor Red

Write-Host ""
Write-Host "Space freed:" -ForegroundColor Cyan
Write-Host "  build      : $(Format-FileSize $totalBuildFreed)" -ForegroundColor Green
Write-Host "  .dart_tool : $(Format-FileSize $totalDartToolFreed)" -ForegroundColor Green
Write-Host "  --------------------------------"
Write-Host "  TOTAL      : $(Format-FileSize $totalFreed)" -ForegroundColor Green
Write-Host ""