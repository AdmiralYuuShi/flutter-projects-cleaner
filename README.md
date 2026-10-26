# Flutter Projects Cleaner

A PowerShell utility for cleaning multiple Flutter projects at once using [FVM (Flutter Version Management)](https://fvm.app/).

Flutter Projects Cleaner scans Flutter/Dart projects in the current directory, determines the appropriate Flutter SDK for each project, runs `flutter clean`, and reports how much disk space was freed from `build` and `.dart_tool`.

It is useful if you keep many Flutter projects in a single directory and want to periodically reclaim disk space without manually cleaning every project.

## Features

- Automatically scans multiple Flutter/Dart projects.
- Uses FVM — no system-wide Flutter installation required.
- Runs `fvm list` before processing projects.
- Detects the Flutter version configured by each project's FVM configuration.
- Uses the project's configured FVM SDK when available.
- Uses the FVM global SDK for projects without a local FVM configuration.
- Detects projects whose configured Flutter SDK is no longer installed.
- Provides an interactive fallback when a configured SDK is missing.
- Never automatically installs missing Flutter SDK versions.
- Never modifies a project's FVM configuration.
- Calculates `build` and `.dart_tool` sizes before and after cleaning.
- Reports disk space freed per project.
- Displays a final summary of cleaned, skipped, and failed projects.
- Supports one-shot execution directly from GitHub without permanently downloading the script.

## Requirements

### Windows

The script is designed for PowerShell on Windows.

### FVM

[FVM](https://fvm.app/) must be installed and available in your `PATH`.

Verify your installation:

```powershell
fvm --version
```

Check the Flutter SDKs installed through FVM:

```powershell
fvm list
```

For example:

```text
Version   Channel   Flutter Version   Global
3.41.9    stable    3.41.9            ●
3.27.4    stable    3.27.4
```

At least one Flutter SDK must be installed through FVM.

### FVM Global SDK

A global Flutter SDK must also be configured.

For example:

```powershell
fvm global 3.41.9
```

The global SDK is used as a fallback for projects without a local FVM configuration and, optionally, for projects whose configured SDK is no longer installed.

> A system-wide Flutter installation is **not required**.

---

## Quick Start

Open PowerShell in the directory containing your Flutter projects.

For example:

```powershell
cd D:\Code
```

Run the latest version directly from GitHub:

```powershell
$tmp = Join-Path $env:TEMP "flutter-projects-cleaner.ps1"; try { irm https://raw.githubusercontent.com/AdmiralYuuShi/flutter-projects-cleaner/master/clean-flutter-projects.ps1 -OutFile $tmp; & $tmp } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
```

That's it.

The command will:

1. Download the latest script to your Windows temporary directory.
2. Run the script against projects in your **current directory**.
3. Clean the detected projects using the appropriate FVM Flutter SDK.
4. Report how much disk space was freed.
5. Automatically remove the downloaded script when finished.

No Flutter Projects Cleaner files are permanently added to your projects directory.

> [!IMPORTANT]
> The **current working directory** is used as the directory to scan. Run the command from the directory containing your Flutter projects.

---

## How It Works

Suppose your projects are organized like this:

```text
D:\Code
│
├── project_a
│   ├── pubspec.yaml
│   └── .fvm
│
├── project_b
│   ├── pubspec.yaml
│   └── .fvm
│
├── project_c
│   └── pubspec.yaml
│
└── other_project
```

Run Flutter Projects Cleaner from:

```powershell
cd D:\Code
```

The script scans each direct child directory containing a `pubspec.yaml` file and determines which Flutter SDK should be used.

---

## Flutter Version Resolution

The Flutter SDK is resolved independently for every project.

### 1. Project With an Installed FVM SDK

For example, a project may contain:

```text
project_a
└── .fvm
    └── fvm_config.json
```

with:

```json
{
  "flutterSdkVersion": "3.27.4"
}
```

If Flutter `3.27.4` is still installed through FVM, the project is cleaned using its configured SDK:

```text
Project: project_a
FVM config : 3.27.4
Status     : Installed

Running: fvm flutter clean
Flutter: 3.27.4 (project FVM)
```

The project's configured Flutter version is therefore respected even when it differs from the current FVM global version.

### 2. Project Without an FVM Configuration

If a project does not contain:

```text
.fvm/fvm_config.json
```

the FVM global SDK is used instead.

For example:

```text
Project: project_b
FVM config : Not configured
FVM global : 3.41.9

Running Flutter clean using FVM global SDK
Flutter: 3.41.9 (FVM global)
```

This allows projects that were never configured using:

```powershell
fvm use <version>
```

to still be cleaned.

A system-wide `flutter` command is not required.

### 3. Project Configured With a Missing SDK

A project may reference an older Flutter SDK that has since been removed.

For example:

```json
{
  "flutterSdkVersion": "3.22.2"
}
```

while only these versions are currently installed:

```text
3.41.9
3.27.4
```

Flutter Projects Cleaner will **not install Flutter 3.22.2 automatically**.

Instead, you will be prompted:

```text
Project: old_project
FVM config : 3.22.2
Status     : NOT INSTALLED
FVM global : 3.41.9

Configured Flutter 3.22.2 is not installed.

  [1] Clean using FVM global (3.41.9)
  [2] Skip this project
  [A] Use FVM global for ALL missing versions
  [S] Skip ALL projects with missing versions

Choose:
```

Available options:

| Option | Behavior |
| --- | --- |
| `1` | Clean only this project using the FVM global SDK |
| `2` | Skip only this project |
| `A` | Use the FVM global SDK for this and all remaining projects with missing SDKs |
| `S` | Skip this and all remaining projects with missing SDKs |

### Does Using the Global SDK Change the Project?

No.

If a project is configured for:

```text
3.22.2
```

and you choose to clean it using global:

```text
3.41.9
```

the project's FVM configuration remains unchanged.

Flutter Projects Cleaner uses the global SDK only to execute `flutter clean`.

It does **not** run:

```powershell
fvm use 3.41.9
```

and does not modify:

```text
.fvm/fvm_config.json
```

---

## Disk Space Calculation

Before cleaning a project, the script calculates the size of:

```text
build/
.dart_tool/
```

For example:

```text
Cache before clean:
  build      : 3.42 GB
  .dart_tool : 845.31 MB
  Total      : 4.25 GB
```

After `flutter clean` completes successfully, both directories are measured again.

The difference is reported as the actual amount of disk space freed:

```text
SUCCESS: project_a
Flutter : 3.41.9

Freed:
  build      : 3.42 GB
  .dart_tool : 843.22 MB
  Total      : 4.24 GB
```

This means the reported value represents the actual difference before and after cleaning rather than simply assuming the entire directory was deleted.

---

## Cleaning Summary

After all projects have been processed, a per-project report is displayed:

```text
========================================
 Space Freed Per Project
========================================

Project          Flutter   Build     DartTool    Total
-------          -------   -----     --------    -----
project_a        3.41.9    3.42 GB   843.22 MB   4.24 GB
project_b        3.27.4    1.81 GB   521.18 MB   2.32 GB
project_c        3.41.9    2.16 GB   734.15 MB   2.88 GB
```

Followed by an overall summary:

```text
========================================
 Cleaning Summary
========================================

Cleaned : 3
Skipped : 2
Failed  : 0

Space freed:
  build      : 7.39 GB
  .dart_tool : 2.05 GB
  --------------------------------
  TOTAL      : 9.44 GB
```

---

## Manual Installation

If you prefer to inspect the script before running it, download it manually:

```powershell
irm https://raw.githubusercontent.com/AdmiralYuuShi/flutter-projects-cleaner/master/clean-flutter-projects.ps1 -OutFile clean-flutter-projects.ps1
```

You can then inspect `clean-flutter-projects.ps1` before executing it.

Run it with:

```powershell
.\clean-flutter-projects.ps1
```

Alternatively, clone the repository:

```powershell
git clone https://github.com/AdmiralYuuShi/flutter-projects-cleaner.git
```

You can then copy or run `clean-flutter-projects.ps1` wherever needed.

> [!NOTE]
> Project discovery uses the current working directory, not the location of the script itself.

---

## PowerShell Execution Policy

If Windows prevents the script from running because of the PowerShell execution policy, you can temporarily allow scripts for the current PowerShell session:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

Then run Flutter Projects Cleaner again.

This changes the execution policy only for the current PowerShell process.

---

## Safety

Flutter Projects Cleaner is intentionally conservative.

It does **not**:

- Install missing Flutter SDKs.
- Run `fvm install`.
- Run `fvm use`.
- Change the FVM global version.
- Modify `.fvm/fvm_config.json`.
- Delete installed Flutter SDKs.
- Delete the FVM SDK cache.
- Run `flutter pub get`.
- Modify application source code.

For normal projects, the maintenance operation performed is equivalent to:

```powershell
flutter clean
```

using either the project's configured FVM SDK or the FVM global SDK.

---

## What Does `flutter clean` Remove?

`flutter clean` removes generated build artifacts and Flutter tooling state that can be regenerated.

This commonly includes:

```text
build/
.dart_tool/
```

Depending on the Flutter version and platform configuration, Flutter may also clean other generated files.

The next build may take longer because Flutter needs to regenerate the deleted files.

You may also need to run:

```powershell
fvm flutter pub get
```

before building the project again.

---

## Project Detection

Flutter Projects Cleaner currently scans **direct child directories** of the current working directory.

A directory is considered a project when it contains:

```text
pubspec.yaml
```

For example:

```text
D:\Code
│
├── project_a           ← detected
├── project_b           ← detected
│
└── Personal
    └── project_c       ← not detected
```

`project_c` is not detected because it is nested inside `Personal`.

Recursive project discovery is currently not performed.

---

## Limitations

- Windows/PowerShell only.
- Requires FVM.
- Requires at least one Flutter SDK installed through FVM.
- Requires an FVM global SDK.
- Currently scans only direct child directories.
- Project detection is based on the presence of `pubspec.yaml`.
- Disk-space reporting covers `build` and `.dart_tool`.
- Cleaning a project with a different Flutter version than the one it was developed with should only be treated as a fallback for `flutter clean`, not for building, running, or modifying the application.
