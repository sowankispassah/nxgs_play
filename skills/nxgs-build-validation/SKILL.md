---
name: nxgs-build-validation
description: Run, copy, dependency-sync, and report the NXGS Gaming local build after source changes. Use whenever Codex modifies C++, QML, CMake, Supabase integration files that affect the client build, resources, packaging, or when the user asks to test/build NXGS. Always publish the rebuilt executable into release/NXGS-Gaming-Win/NXGS Gaming.exe and ensure required non-system DLLs are present there.
---

# NXGS Build Validation

## Required Rule

After making code changes in this repository, run a local build before the final response unless the user explicitly says not to build. A build is not complete until the rebuilt executable is copied into the standard release folder:

```text
D:\Coding\nxgs_play\release\NXGS-Gaming-Win\NXGS Gaming.exe
```

## Build Command

From the repository root on Windows PowerShell, prefer:

```powershell
$env:Path = "C:\msys64\mingw64\bin;C:\msys64\usr\bin;" + $env:Path
& "C:\msys64\mingw64\bin\cmake.exe" --build build-local-msys2 --target chiaki --parallel 2
```

If `build-local-msys2` is missing, inspect the repo scripts before creating a new build tree. Prefer existing project scripts and build directories over inventing a new configuration.

## Release Copy

After the build succeeds, copy the freshly linked build-tree executable into the normal test location:

```powershell
Copy-Item -LiteralPath "build-local-msys2\gui\chiaki.exe" -Destination "release\NXGS-Gaming-Win\NXGS Gaming.exe" -Force
Get-Item "release\NXGS-Gaming-Win\NXGS Gaming.exe" | Select-Object FullName,LastWriteTime,Length
```

Treat this release executable as the app the user will test. Do not point the user only at `build-local-msys2\gui\chiaki.exe` unless they specifically ask for the build-tree binary.

## Runtime Dependency Sync

After copying the executable, scan imported DLLs from the release executable. If a non-system DLL is missing from `release\NXGS-Gaming-Win`, copy it from `C:\msys64\mingw64\bin`.

Use this PowerShell check:

```powershell
$release = (Resolve-Path "release\NXGS-Gaming-Win").Path
$exe = Join-Path $release "NXGS Gaming.exe"
$systemDlls = @(
    "ADVAPI32.dll", "bcrypt.dll", "CRYPT32.dll", "IPHLPAPI.DLL",
    "KERNEL32.dll", "msvcrt.dll", "USER32.dll", "WS2_32.dll", "WSOCK32.dll"
)
$imports = & "C:\msys64\mingw64\bin\objdump.exe" -p $exe |
    Select-String "DLL Name:" |
    ForEach-Object { ($_ -split "DLL Name:")[1].Trim() } |
    Sort-Object -Unique
foreach ($dll in $imports) {
    if ($systemDlls -contains $dll) { continue }
    $target = Join-Path $release $dll
    if (!(Test-Path $target)) {
        $source = Join-Path "C:\msys64\mingw64\bin" $dll
        if (Test-Path $source) {
            Copy-Item -LiteralPath $source -Destination $target -Force
        } else {
            Write-Error "Missing runtime DLL and no MSYS2 source found: $dll"
        }
    }
}
```

Run the import scan again afterward. Only Windows system DLLs should remain missing from the release folder.

## Validation Reporting

- Report whether the build passed or failed.
- If it fails, include the first actionable compiler/configuration error and the command used.
- Do not claim the app is testable from a newly modified binary unless `release\NXGS-Gaming-Win\NXGS Gaming.exe` has a timestamp from after the successful build.
- Report whether the runtime dependency scan found and copied missing non-system DLLs.
- Include the release executable path in the final response when the build succeeds.
- Run `git diff --check` after edits and report failures.

## Scope

This skill enforces build validation only. It does not replace release packaging checks from `nxgs-gaming-release`.
