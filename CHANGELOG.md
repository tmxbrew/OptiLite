# Changelog

All notable changes to OptiLite are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-11-25

Bilingual UI, startup manager, undo stack and backup portability.

### Added

- **Language switch (ES/EN)**: live UI switcher in the top bar; the preference
  persists in `optilite.json` and Spanish remains the default on first run.
  Every panel, card, description and status message is translated.
- **Startup programs panel (Inicio)**: lists every entry from the HKLM/HKCU
  `Run` keys and the user Startup folder, with a switch to disable each one.
  Disabled entries are backed up and fully re-enactable from the same switch;
  folder entries are moved to a `disabled-startup` folder instead of deleted.
- **Undo stack**: every tweak change (manual switch, profile or import) is
  pushed onto an undo stack (up to 50 entries, persisted in
  `optilite-undo.json`); "Deshacer último cambio" reverts them one by one.
- **Backup export/import**: save the current state of all settings to any
  `.json` file and re-apply it later or on another PC (each applied setting
  is undoable).
- **Preview mode**: the "Vista previa" toggle makes switches and profiles
  report what they *would* change without touching the system.
- **Diagnostics in the summary panel**: disk health (SMART failure
  prediction), battery wear vs design capacity, running-services count and
  the top 5 processes by RAM.
- **Network tweaks**: Nagle/TcpAckFrequency (per-interface) and TCP autotuning
  level — both clearly marked as reboot-required/latency-tradeoff tweaks.
- Startup entries and diagnostics are refreshed by the "Refresh states"
  button; the language rebuild keeps every panel in sync.

## [1.0.0] - 2026-11-24

First public release.

### Added

- Dark-themed WPF GUI with sidebar navigation and accent-insensitive search.
- **Rendimiento** panel: 7 tweaks (VBS/memory integrity, visual effects,
  SysMain, Windows Search, hibernation & Fast Startup, background apps,
  network throttling) plus the Gaming Ultimate power-plan action.
- **Juegos** panel: 9 tweaks (Riot Vanguard, FACEIT, Xbox services, Game Mode,
  Game Bar/DVR, fullscreen optimizations, mouse acceleration, MPO, DAW mode).
- **Privacidad** panel: 8 tweaks (telemetry, DiagTrack, activity history,
  advertising ID, suggestions & promoted apps, inking & typing collection,
  feedback notices, language list).
- **Limpieza** panel: quick clean, deep clean (Prefetch, CBS logs, WER,
  Windows Update cache), Recycle Bin, DNS cache.
- **Perfiles** panel: 4 one-click profiles (Competitivo, Juegos AAA,
  Cloud/Xbox, Restaurar Windows) and a JSON restore point that is snapshotted
  automatically before every profile application.
- Live RAM/process monitor (5 s refresh) and pending-reboot indicator.
- Plain-text activity log and restore-point JSON under
  `%LOCALAPPDATA%\OptiLite\`.
- Desktop-shortcut action that launches OptiLite elevated.
- CI workflow: PSScriptAnalyzer lint plus UTF-8 BOM / CRLF encoding checks.
- Documentation: bilingual README (English / Spanish), CONTRIBUTING, SECURITY,
  MIT license.
