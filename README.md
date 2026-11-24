# OptiLite

> **Local Windows 10/11 optimizer with a modern GUI.**
> One PowerShell file · no downloads · no installs · no telemetry · fully reversible.

**¿Prefieres leer en español? → [README.es.md](README.es.md)**

```
┌──────────────┬─────────────────────────────────────────┐
│  OPTILITE    │  Panel title                    [search] │
│  ● Resumen   │  ┌─────────────────────────────────────┐ │
│  ● Rendim.   │  │ Tweak card            ( switch )    │ │
│  ● Juegos    │  │ Tweak card            ( switch )    │ │
│  ● Privac.   │  │ Cleanup card         [ Run button ] │ │
│  ● Limpieza  │  │ Profile card        [ Apply button ]│ │
│  ● Perfiles  │  └─────────────────────────────────────┘ │
│  RAM · Proc  │  Status bar · pending-reboot warning    │
└──────────────┴─────────────────────────────────────────┘
```

## Features

- **24 reversible tweaks** across Performance, Gaming and Privacy — each one is a
  switch that reads the *actual* system state and applies changes instantly.
- **One-click profiles**: Competitivo (Valorant/CS2), Juegos AAA, Cloud/Xbox and
  *Restaurar Windows* (restores every setting to Windows defaults).
- **Built-in restore point**: a JSON snapshot of all tweak states is saved
  before any profile is applied, and can be rolled back with one click.
- **Cleanup actions**: TEMP folders, Prefetch, CBS logs, Windows Error Reports,
  Windows Update cache, Recycle Bin and DNS cache.
- **Gaming Ultimate power plan** (duplicates Ultimate Performance, disables
  Core Parking, 100% minimum CPU on AC).
- **Live monitor**: RAM usage and process count refresh every 5 seconds.
- **Accent-insensitive search** across every tweak and action.
- **Anti-cheat aware**: Riot Vanguard and FACEIT can be toggled on/off;
  switches turn grey automatically if the software is not installed.
- **Zero network access.** Everything runs locally; the only files it writes
  are a log and a restore-point JSON under `%LOCALAPPDATA%\OptiLite\`.

## Quick start

1. Download **`OptiLite.ps1`** (or clone the repository).
2. If your browser/zip program marked the file, unblock it once:
   ```powershell
   Unblock-File .\OptiLite.ps1
   ```
3. Right-click the file → **Run with PowerShell** (it self-elevates and shows
   a UAC prompt), or from a terminal:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\OptiLite.ps1
   ```

> **Tip:** the *Resumen* panel includes a one-click **"Acceso en Escritorio"**
> action that creates a desktop shortcut which always launches OptiLite with
> administrator rights.

## Requirements

| | |
|---|---|
| OS | Windows 10 (1809+) or Windows 11, desktop editions (WPF required — Server Core / WinPE not supported) |
| PowerShell | 5.1 or newer (preinstalled on Windows 10/11) |
| Rights | Administrator (requested automatically via UAC) |

## Panels and catalog

### Rendimiento (Performance)

| Tweak | OFF (recommended for FPS) | Notes |
|---|---|---|
| VBS / Integridad de memoria | ~5–8% FPS gain on most systems | Needs reboot; anti-cheats keep working |
| Efectos visuales | Minimal animations/transparency | Per-user, instant |
| SysMain (Superfetch) | No prefetch service | Low benefit on SSDs |
| Windows Search (indexación) | No background indexing | Search becomes slower |
| Hibernación e Inicio rápido | Frees `hiberfil.sys` (GBs on disk) | Instant |
| Apps en segundo plano | UWP apps can't run closed | Desktop apps unaffected |
| **Plan de energía** *(action)* | Gaming Ultimate plan: Core Parking off, min CPU 100% | Button, not a switch |

### Juegos (Gaming)

| Tweak | What it does |
|---|---|
| Riot Vanguard (Valorant) | Enables/disables the `vgk`/`vgc` kernel driver and service (reboot required) |
| FACEIT Anti-Cheat (CS2) | Instant on/off of the FACEIT services |
| Servicios Xbox y Cloud Gaming | Xbox Live / GamingServices toggle — off if you don't use Game Pass |
| Modo Juego (Game Mode) | CPU/GPU priority for foreground games (recommended ON) |
| Game Bar y DVR | Disables background recording (OBS unaffected) |
| Optimizaciones de pantalla completa (FSO) | True exclusive fullscreen — lower latency |
| Aceleración del puntero | Raw 1:1 mouse movement (competitive standard) |
| MPO | Disables Multi-Plane Overlay — fixes microstutter on AMD Polaris (RX 400/500) |
| Modo DAW | Prioritizes audio buffers for Ableton/FL (vs gaming responsiveness) |

### Privacidad (Privacy)

Telemetría (minimum level; Security is honored on LTSC editions) · DiagTrack
service · Historial de actividad · Identificador de publicidad · Sugerencias y
apps promocionadas · Recolección de escritura y tinta · Notificaciones de
feedback · Envío de idioma local a sitios web.

### Limpieza (Cleanup)

Limpieza rápida (user TEMP + `C:\Windows\Temp`) · Limpieza profunda (+ Prefetch,
CBS logs, WER reports, Windows Update cache) · Vaciar papelera · Vaciar caché DNS.

### Perfiles (Profiles)

| Profile | Intent |
|---|---|
| COMPETITIVO | Vanguard + FACEIT ON, Xbox/VBS/DVR/FSO/mouse-accel OFF, unlimited network |
| JUEGOS AAA | Anti-cheats and Xbox OFF, max FPS everywhere |
| CLOUD / XBOX | Game Pass ready, streaming-friendly network settings |
| RESTAURAR WINDOWS | Every tweak back to Windows defaults (anti-cheats untouched) |
| **Punto de restauración** | Create/rollback a JSON snapshot of all 24 tweak states |

## Undo and safety

- Every profile application **automatically snapshots** the current state to
  `%LOCALAPPDATA%\OptiLite\optilite-restore.json`; *Restaurar último punto*
  reverts everything changed since that snapshot.
- *RESTAURAR WINDOWS* returns all tweaks to factory defaults.
- A plain-text log of every action is kept at `%LOCALAPPDATA%\OptiLite\optilite.log`.
- OptiLite never makes network connections, downloads nothing, and touches
  no personal files — only the Windows settings listed above.
- As with any optimizer: **read the code first** (it's one readable file) and
  consider creating a Windows System Restore point before big changes.

## FAQ

**Can I undo everything?**
Yes — use the restore point (exact previous states) or the *Restaurar Windows*
preset (factory defaults). Tweaks that need a reboot are clearly marked.

**I disabled Vanguard and now Valorant won't start.**
Expected: Valorant requires Vanguard. Flip the switch back on and reboot.
OptiLite never deletes anti-cheat software, it only changes service start modes.

**My antivirus flags the script.**
Heuristics often flag PowerShell scripts that write to the registry and request
admin rights. The entire source is a single auditable file in this repository.

**Does it phone home?**
No. No network calls of any kind. Verify with the source or a firewall monitor.

## Contributing · Security · License

- Contributions welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) (the tweak
  engine is data-driven: one hashtable per tweak).
- Found a security issue? Please follow [SECURITY.md](SECURITY.md).
- Released under the [MIT License](LICENSE).

## Roadmap

- English UI (i18n)
- More community-requested tweaks
- Optional CLI mode (`-Apply preset`, `-Restore`)
