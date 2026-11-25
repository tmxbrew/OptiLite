# OptiLite

> **Local Windows 10/11 optimizer with a modern graphical interface.**
> Single PowerShell file · no downloads · no installation · zero telemetry · fully reversible.

**¿Prefieres español? → [README.es.md](README.es.md)**

```
┌───────────────┬──────────────────────────────────────────────┐
│  OPTILITE     │  Panel title       [search] (globe) (sun/moon)│
│  ● Summary    │  ┌────────────────────────────────────────┐  │
│  ● Perform.   │  │ Card (hover to see description)    ◉── │  │
│  ● Gaming     │  │ Card (hover to see description)    ◉── │  │
│  ● Privacy    │  │ Cleanup card                [ button ] │  │
│  ● Net & DNS  │  │ Browser card                [ button ] │  │
│  ● Cleanup    │  │ Profile card                [ apply  ] │  │
│  ● Browsers   │  └────────────────────────────────────────┘  │
│  ● Panels     │  Status bar · reboot pending indicator       │
│  ● Startup    │  Light/dark theme · ES/EN · custom scrollbar │
│  ● Profiles   │                                              │
│  RAM · Proc   │                                              │
└───────────────┴──────────────────────────────────────────────┘
```

## Features

- **Light/Dark theme** and **ES/EN language**, both switchable LIVE from the
  top bar (custom-drawn globe and sun/moon icon buttons — no default Windows
  controls) and remembered in `%LOCALAPPDATA%\OptiLite\optilite.json`. Switching
  languages refreshes **the current tab in place** (does not jump back to "Summary").
- **38 reversible tweaks** across Performance, Gaming, Privacy, Network,
  Browsers, and Classic Panels: each one is a toggle switch that reads the *actual*
  system state and applies changes instantly. Descriptions appear as **hover
  tooltips**, keeping the card list clean.
- **One-click DNS**: apply **Google** (8.8.8.8 / 8.8.4.4) or **Cloudflare**
  (1.1.1.1 / 1.0.0.1) DNS to all active adapters; previous DNS settings are backed
  up per adapter and a single button restores them exactly (or resets to DHCP if
  no backup existed).
- **Classic Windows panels**: one action creates a "Classic Panel" folder on
  the Desktop containing God Mode, classic Control Panel, Administrative Tools,
  Network Connections, Printers, Default Apps, User Accounts, and Task Scheduler
  (the same shell GUID tools exposed by WinUtil); another action creates a standalone
  **God Mode** shortcut. Plus, a toggle restores the **classic Win11 context menu**.
- **Browser debloat (Edge / Brave / Firefox)**: policy-based — disables Edge
  telemetry, sidebar/shopping assistant, and background mode; disables Brave
  Rewards/Wallet/VPN/Leo AI and P3A telemetry; disables Firefox telemetry and
  Pocket. **Nothing is uninstalled**; everything is reversible and the switch
  appears grayed out if the browser isn't installed.
- **Deep privacy**: Copilot/Bing in Windows off, Bing web search in the Start
  menu off, Widgets and lock-screen Spotlight content off, telemetry scheduled
  tasks off, and security hardening (SMBv1, LLMNR/mDNS).
- **Startup program manager**: the *Startup* panel lists everything running at
  boot (HKLM/HKCU Run keys + Startup folder) and lets you disable/re-enable each
  entry with a switch — nothing is deleted, so it is always reversible.
- **Undo stack**: every applied change is pushed onto a stack of up to 50 entries
  (`optilite-undo.json`); *Undo last change* reverts them one by one.
- **Backup export / import**: save the state of all tweaks to a `.json` file and
  reapply it anytime or on another PC.
- **Preview mode**: enable *Preview mode* and switches/profiles will report
  exact changes they *would* make — without touching the system.
- **One-click profiles**: Competitive (Valorant/CS2), AAA Gaming, Cloud/Xbox,
  and *Restore Windows* (resets all tweaks — including DNS, browser debloat,
  and the Win11 context menu — back to factory defaults).
- **Built-in restore point**: before applying any profile, a JSON snapshot of
  all settings is automatically saved, reversible in one click.
- **Summary diagnostics**: disk health (SMART), battery wear, running services
  count, and top 5 processes by RAM.
- **Cleanup**: TEMP folders, Prefetch, CBS logs, Windows Error Reporting (WER),
  Windows Update cache, Recycle Bin, and DNS cache.
- **Gaming Ultimate power plan** (duplicates Ultimate Performance, disables
  Core Parking, sets minimum CPU state to 100% on AC power).
- **Custom-drawn icons and scrollbar**: sidebar icons, switch tracks, scrollbar
  thumbs, and tooltips are drawn in XAML paths that follow the active theme —
  zero default Windows glyphs remain.
- **Live monitor**: RAM usage and process count refresh every 5 seconds.
- **Accent-insensitive search** across all tweaks and actions.
- **Anti-cheat aware**: Riot Vanguard and FACEIT can be toggled on/off with a
  switch; if the software isn't installed, the toggle is automatically disabled.
- **Zero network access.** Everything runs locally; the only files written are
  an activity log and state JSONs in `%LOCALAPPDATA%\OptiLite\`.

## Quick Start

1. Download **`OptiLite.ps1`** (or clone the repository).
2. If Windows flagged the downloaded file, unblock it once:
   ```powershell
   Unblock-File .\OptiLite.ps1
   ```
3. Right-click → **Run with PowerShell** (self-elevates and triggers the UAC
   prompt), or run from a terminal:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\OptiLite.ps1
   ```

> **Tip:** the *Summary* panel includes a **"Desktop Shortcut"** action that
> creates a shortcut configured to always launch OptiLite as Administrator.

## Requirements

| | |
|---|---|
| OS | Windows 10 (1809+) or Windows 11, desktop editions (requires WPF — not supported on Server Core / WinPE) |
| PowerShell | 5.1 or later (pre-installed on Windows 10/11) |
| Permissions | Administrator (requested automatically via UAC) |

## Panels & Catalog

### Performance

| Tweak | OFF (recommended for FPS) | Notes |
|---|---|---|
| VBS / Memory Integrity | ~5–8% FPS gain on most systems | Requires reboot; anti-cheats continue working |
| Visual Effects | Minimal animations and transparency | Per-user, instant |
| SysMain (Superfetch) | Disables background preloading service | Little benefit on SSDs |
| Windows Search (Indexing) | Disables background file indexing | File search will be slower |
| Hibernation & Fast Startup | Frees `hiberfil.sys` (GBs of disk space) | Instant |
| Background Apps | Prevents UWP apps from running in background | Desktop programs are unaffected |
| TCP Autotuning | Locks TCP receive window | Requires reboot; often *lowers* throughput — testing only |
| Nagle / TcpAckFrequency | Sends network packets immediately | Requires reboot; lower latency in online games |
| **Power Plan** *(action)* | Gaming Ultimate plan: Core Parking off, min CPU 100% | Action button, not a toggle |

### Gaming

| Tweak | What it does |
|---|---|
| Riot Vanguard (Valorant) | Enables/disables the `vgk` kernel driver and `vgc` service (requires reboot) |
| FACEIT Anti-Cheat (CS2) | Instant toggle for FACEIT background services |
| Xbox & Cloud Gaming Services | Toggles Xbox Live / GamingServices — turn OFF if you don't use Game Pass |
| Game Mode | Prioritizes CPU/GPU resources for the foreground game (recommended ON) |
| Game Bar & DVR | Disables background screen recording (OBS is unaffected) |
| Fullscreen Optimizations (FSO) | Enforces true exclusive fullscreen — lower input latency |
| Pointer Precision (Mouse Accel) | Enforces 1:1 raw mouse movement (competitive standard) |
| MPO | Disables Multi-Plane Overlay — fixes microstutter on AMD Polaris GPUs (RX 400/500) |
| DAW Mode | Prioritizes audio buffers for Ableton/FL Studio (vs. gaming responsiveness) |

### Privacy

Telemetry (minimum level; respects Security level on LTSC editions) ·
DiagTrack service · Activity history · Advertising ID · Suggestions & promoted
apps · Inking & typing collection · Feedback notifications · Sending local
language list to websites · **Copilot & Bing in Windows** · **Bing web search in
Start menu** · **Widgets** · **Lock-screen Spotlight content** · **Telemetry
scheduled tasks** · **Security hardening (SMBv1, LLMNR/mDNS)**.

### Network & DNS

| Toggle / Action | What it does |
|---|---|
| **Google DNS** | Applies 8.8.8.8 / 8.8.4.4 to all active adapters; backs up previous DNS |
| **Cloudflare DNS** | Applies 1.1.1.1 / 1.0.0.1 to all active adapters; backs up previous DNS |
| **Restore Automatic DNS** *(action)* | Reverts each adapter to its pre-OptiLite DNS (or DHCP) |
| Flush DNS Cache *(action)* | Clears the local DNS resolver cache |

### Browsers

Policy-based debloat — uninstalls nothing, fully reversible, and the switch is
grayed out if the browser is not installed:

| Browser | What gets disabled |
|---|---|
| **Microsoft Edge** | Telemetry, Hub/sidebar, shopping assistant, rewards promos, forced sync, startup boost, and background mode |
| **Brave** | Rewards, Wallet, VPN, Leo AI, Brave News, Tor shortcuts, and P3A/metrics reporting |
| **Firefox** | Telemetry, Pocket, Firefox Accounts prompts, built-in screenshots, and promotional home page |

### Classic Panels

| Action / Toggle | What it does |
|---|---|
| **"Classic Panel" Folder** | Desktop folder with 8 classic tools (God Mode, classic Control Panel, Administrative Tools, Network, Printers, Default Apps, User Accounts, and Task Scheduler) |
| **"God Mode" Shortcut** | Standalone shortcut to God Mode (~50 Control Panel categories in one window) |
| **Classic Context Menu (Win11)** | Restores the full Windows 10 right-click menu; applies instantly by restarting Explorer |

### Cleanup

Quick clean (User TEMP + `C:\Windows\Temp`) · Deep clean (+ Prefetch, CBS logs,
WER reports, Windows Update cache) · Empty Recycle Bin · Flush DNS cache.

### Startup

Lists all entries from HKLM/HKCU Run keys and the Startup folder with an
individual toggle per program. Disabling an entry creates a backup (registry
values move to a backup key; folder shortcuts move to `disabled-startup`), so
*re-enabling is always possible from the exact same switch*.

### Profiles

| Profile | Target Use Case |
|---|---|
| COMPETITIVE | Vanguard + FACEIT ON; Xbox/VBS/DVR/FSO/mouse acceleration OFF; uncapped network |
| AAA GAMING | Anti-cheats and Xbox OFF; maximum FPS across the board |
| CLOUD / XBOX | Ready for Game Pass; network tuned for game streaming |
| RESTORE WINDOWS | Resets all tweaks to factory defaults — including DNS, browser debloat, telemetry tasks, and Win11 context menu — (leaves anti-cheats untouched) |
| **Restore Point** | Creates/reverts a JSON snapshot of all 38 tweaks |
| **Undo Last Change** | Reverts the last applied change one by one (50-step stack) |
| **Export / Import Backup** | Saves/applies the state of all tweaks in a portable `.json` file |

## Undo & Safety

- Every change (manual toggle, profile, or imported backup) is recorded in an
  **undo stack**: *Undo last change* reverts them one by one, up to 50 steps back.
- Applying any profile **automatically saves** the current state to
  `%LOCALAPPDATA%\OptiLite\optilite-restore.json`; *Restore last point* reverts
  everything modified since that snapshot.
- Disabled startup programs are **never deleted**: registry values are moved to
  a backup key and folder shortcuts to `disabled-startup`, so they can always be
  re-enabled.
- *RESTORE WINDOWS* resets all settings back to Windows factory defaults.
- Every action is logged to `%LOCALAPPDATA%\OptiLite\optilite.log`.
- OptiLite makes zero network connections, downloads nothing, and never touches
  personal files — only the Windows settings listed above.
- As with any system optimizer: **read the code first** (it is a single readable
  file) and consider creating a Windows System Restore point before major changes.

## FAQ

**Can I undo everything?**
Yes: use the restore point (exact previous states) or the *Restore Windows*
profile (factory defaults). Tweaks that require a reboot are clearly marked.

**I disabled Vanguard and Valorant won't launch.**
That is expected: Valorant requires Vanguard to run. Toggle it back ON and
reboot. OptiLite never uninstalls anti-cheat software; it only changes the
startup type of its services.

**My antivirus flagged the script.**
Heuristic scanners commonly flag PowerShell scripts that modify the registry and
request admin rights. The entire source code is a single auditable file right
here in this repository.

**Does it send data anywhere?**
No. There are zero network calls in the script. Verify it in the source code or
with your firewall.

## Contributing · Security · License

- Contributions are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) (the tweak
  engine is data-driven: one hashtable per tweak).
- Found a security issue? Please follow [SECURITY.md](SECURITY.md).
- Released under the [MIT License](LICENSE).

## Roadmap

- More community-suggested tweaks
- Optional CLI mode (`-Apply profile`, `-Restore`)
- Scheduling for major changes