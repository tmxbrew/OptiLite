# Security Policy

## Supported versions

| Version | Supported |
| ------- | --------- |
| 1.0.x   | Yes       |

## Reporting a vulnerability

Please use GitHub's **private vulnerability reporting**: *Security* tab →
*Report a vulnerability*. If you cannot use it, open a regular issue asking
for a contact channel — **do not post exploit details publicly**.

You can expect an acknowledgement within a few days. Please give the
maintainers reasonable time to address the issue before any public disclosure.

## What OptiLite does

OptiLite is a local Windows optimizer. When you run it (with a UAC elevation
prompt), it:

- Reads and writes Windows settings in the registry
  (`HKLM\SYSTEM\CurrentControlSet\Services`, `HKLM:\SOFTWARE\Policies`,
  `HKCU:\Software`, …) for the tweaks listed in the README.
- Changes Windows service start modes (SysMain, WSearch, DiagTrack, Xbox,
  Vanguard, FACEIT, …).
- Runs standard system utilities: `powercfg.exe`, `Clear-RecycleBin`,
  `Clear-DnsClientCache`.
- Deletes files in temp/cache locations (`%TEMP%`, `C:\Windows\Temp`,
  `C:\Windows\Prefetch`, `C:\Windows\Logs\CBS`, WER reports,
  `C:\Windows\SoftwareDistribution\Download`).
- Writes exactly two files of its own:
  `%LOCALAPPDATA%\OptiLite\optilite.log` (activity log) and
  `%LOCALAPPDATA%\OptiLite\optilite-restore.json` (restore point).
- Can create a desktop shortcut that relaunches itself elevated.

## What OptiLite never does

- No network access of any kind (no downloads, no telemetry, no updates).
- No execution of remote or downloaded code.
- No collection, storage or transmission of personal data.
- No modification of files outside the locations listed above.

The entire program is one auditable file, `OptiLite.ps1`. If you find a
copy of OptiLite somewhere and it does something not listed here, treat it
as tampered: compare it against the canonical source in this repository.

## Scope

This policy covers the `OptiLite.ps1` file in this repository and the
repository files themselves. Vulnerabilities in Windows itself, in
third-party software or in unmodified copies of other tools are out of scope.
