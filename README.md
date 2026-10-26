# Flutter Projects Cleaner

A PowerShell utility for cleaning multiple Flutter projects at once using [FVM (Flutter Version Management)](https://fvm.app/).

The script scans Flutter/Dart projects inside the current directory, determines which Flutter SDK should be used for each project, runs `flutter clean`, and reports how much disk space was freed from the `build` and `.dart_tool` directories.

It is particularly useful if you keep many Flutter projects in a single directory and want to periodically reclaim disk space without manually cleaning each project.

## Features

- Scans multiple Flutter/Dart projects automatically.
- Uses FVM instead of requiring a system-wide Flutter installation.
- Runs `fvm list` before processing projects.
- Detects the Flutter version configured by each project's FVM configuration.
- Uses the project's configured FVM SDK when it is installed.
- Uses the FVM global SDK for projects without a local FVM configuration.
- Detects projects whose configured Flutter SDK is no longer installed.
- Provides an interactive choice when a project's configured SDK is missing.
- Does **not** automatically install missing Flutter SDK versions.
- Does **not** modify the project's FVM configuration.
- Calculates the size of `build` and `.dart_tool` before and after cleaning.
- Reports disk space freed per project.
- Displays a final summary of cleaned, skipped, and failed projects.

## Requirements

### Windows

The script is designed for PowerShell on Windows.

### FVM

FVM must be installed and accessible from your `PATH`.

Verify it with:

```powershell
fvm --version
```

At least one Flutter SDK must be installed through FVM:

```powershell
fvm list
```

Example:

```text
Version   Channel   Flutter Version   Global
3.41.9    stable    3.41.9            ●
3.27.4    stable    3.27.4
```

### FVM Global SDK

A global Flutter SDK must be configured.

For example:

```powershell
fvm global 3.41.9
```

The global SDK is used as a fallback for projects that do not have a local FVM configuration and, optionally, for projects whose configured SDK is no longer installed.

A global/system Flutter installation is **not required**.

## Installation

Clone this repository or download:

```text
clean-flutter-projects.ps1
```

You can place the script inside the directory containing your Flutter projects.

For example:

```text
D:\Code
│
├── clean-flutter-projects.ps1
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

## Usage

Open PowerShell in the directory containing your projects:

```powershell
cd D:\Code
```

Run:

```powershell
.\clean-flutter-projects.ps1
```

The script will first display the Flutter SDKs currently installed through FVM:

```text
Installed FVM / Flutter versions:

Cache directory: C:\Users\User\fvm\versions

Version   Channel   Flutter Version   Global
3.41.9    stable    3.41.9            ●
3.27.4    stable    3.27.4
```

It then processes each detected project.

## Flutter Version Resolution

The script determines which Flutter SDK to use separately for each project.

### Project with an installed FVM SDK

For example:

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

If Flutter `3.27.4` is installed through FVM, the project is cleaned using its configured SDK:

```text
Project: project_a
FVM config : 3.27.4
Status     : Installed

Running: fvm flutter clean
Flutter: 3.27.4 (project FVM)
```

### Project without FVM configuration

If a project has no `.fvm/fvm_config.json`, the FVM global SDK is used:

```text
Project: project_b
FVM config : Not configured
FVM global : 3.41.9

Running Flutter clean using FVM global SDK
Flutter: 3.41.9 (FVM global)
```

This allows the script to clean projects even when they were never configured with:

```powershell
fvm use <version>
```

A global Flutter installation is not required.

### Project configured with a missing SDK

A project may still reference an older Flutter SDK that has since been removed from the FVM cache.

For example:

```json
{
  "flutterSdkVersion": "3.22.2"
}
```

while the currently installed SDKs are only:

```text
3.41.9
3.27.4
```

The script will **not automatically install Flutter 3.22.2**.

Instead, it asks what to do:

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

The available choices are:

| Option | Behavior                                                                     |
| ------ | ---------------------------------------------------------------------------- |
| `1`    | Clean this project using the FVM global SDK                                  |
| `2`    | Skip this project                                                            |
| `A`    | Use the FVM global SDK for this and all remaining projects with missing SDKs |
| `S`    | Skip this and all remaining projects with missing SDKs                       |

Using the global SDK as a fallback **does not modify** the project's `.fvm/fvm_config.json`.

For example, if the project specifies:

```text
3.22.2
```

but you choose to clean it with:

```text
3.41.9
```

the project will still remain configured for `3.22.2`.

The global SDK is only used temporarily to execute `flutter clean`.

## Disk Space Calculation

Before cleaning each project, the script calculates the size of:

```text
build
.dart_tool
```

Example:

```text
Cache before clean:
  build      : 3.42 GB
  .dart_tool : 845.31 MB
  Total      : 4.25 GB
```

After `flutter clean` completes successfully, the directories are measured again.

The difference is reported as the actual amount of disk space freed:

```text
SUCCESS: project_a
Flutter : 3.41.9

Freed:
  build      : 3.42 GB
  .dart_tool : 843.22 MB
  Total      : 4.24 GB
```

## Summary

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

Followed by the overall summary:

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

## Safety

The script intentionally avoids making changes to Flutter SDK configuration.

It does **not**:

- Install missing Flutter SDKs.
- Run `fvm install`.
- Run `fvm use`.
- Change the FVM global version.
- Modify `.fvm/fvm_config.json`.
- Delete Flutter SDKs.
- Delete the FVM cache.
- Run `flutter pub get`.
- Modify project source code.

The only Flutter maintenance command executed against projects is:

```powershell
flutter clean
```

through either the project's FVM SDK or the configured FVM global SDK.

## What Does `flutter clean` Remove?

`flutter clean` removes generated build artifacts and Flutter tooling state that can be regenerated when the project is built again.

This commonly includes:

```text
build/
.dart_tool/
```

Depending on the Flutter version and platform configuration, other generated files may also be cleaned by Flutter.

After cleaning, the next build may take longer because Flutter needs to regenerate these files.

You may also need to run:

```powershell
fvm flutter pub get
```

before building the project again.

## Project Detection

Currently, the script scans **direct child directories** of the directory from which it is executed.

A directory is considered a project when it contains:

```text
pubspec.yaml
```

For example:

```text
D:\Code
├── project_a       ← detected
├── project_b       ← detected
└── Personal
    └── project_c   ← not detected
```

`project_c` is not detected because it is nested inside another directory.

Recursive project discovery is currently not performed.

## PowerShell Execution Policy

If Windows prevents the script from running because of the PowerShell execution policy, you can allow it for the current PowerShell session:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

Then run:

```powershell
.\clean-flutter-projects.ps1
```

This changes the execution policy only for the current PowerShell process.

## Example Workflow

```powershell
# Check installed FVM SDKs
fvm list

# Configure a global SDK if necessary
fvm global 3.41.9

# Navigate to the projects directory
cd D:\Code

# Run the cleaner
.\clean-flutter-projects.ps1
```

## Limitations

- Windows/PowerShell only.
- Requires FVM.
- Requires an FVM global SDK.
- Currently scans only direct child directories.
- Project detection is based on the presence of `pubspec.yaml`.
- Disk-space reporting covers only `build` and `.dart_tool`.
- Cleaning a project with a different Flutter version than the version it was developed with is intended only as a fallback for `flutter clean`, not for building or running the application.