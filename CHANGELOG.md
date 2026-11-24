# Changelog

All notable changes to OptiLite are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
