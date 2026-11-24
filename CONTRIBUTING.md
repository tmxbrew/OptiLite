# Contributing to OptiLite

Thanks for your interest in improving OptiLite! 🎮⚡

## Ground rules

1. **Local-only.** OptiLite never downloads anything and never touches the
   network. Any change that adds a download, a web request or a remote script
   will be rejected.
2. **Reversible.** Every tweak must be undoable — either through its own
   switch or through the *Restaurar Windows* preset.
3. **One file.** The whole tool lives in `OptiLite.ps1` and must keep working
   with Windows PowerShell 5.1 (no PowerShell 7-only syntax) and with the
   script saved as **UTF-8 with BOM + CRLF**.

## The tweak engine (how to add a tweak)

Tweaks are data-driven: each one is a hashtable in the `$Items` array with a
`Get` scriptblock that reads the current state and a `Set` scriptblock that
applies it. The GUI builds the switch automatically.

```powershell
@{ Id='example'; Cat='Priv'; Grp='Datos y telemetría'; Reboot=$false
   Name='Ajuste de ejemplo'
   Desc='ON = comportamiento por defecto. OFF = recomendado por XYZ.'
   Get={ (Get-Reg 'HKCU:\Software\Ejemplo' 'Enabled') -ne 0 }
   Set={ param($on) Set-Reg 'HKCU:\Software\Ejemplo' 'Enabled' $(if($on){1}else{0}) } }
```

Rules for a new tweak:

- `Id` must be unique and lowercase; add it to the *Restaurar Windows* preset
  with its Windows-default value.
- `Get` must return `$true` / `$false`, or `$null` when the feature is not
  installed (the switch renders disabled automatically).
- `Reboot=$true` only when the change cannot take effect without a reboot.
- Keep `Desc` short: what ON/OFF mean and one line of guidance.
- Cleanup actions go in `$Actions` (`Run` scriptblock), profiles in `$Presets`.

## Before opening a pull request

- [ ] Tested on Windows 10 **and** Windows 11.
- [ ] `Invoke-ScriptAnalyzer -Path .\OptiLite.ps1` reports no **Errors**
      (CI runs this on every push).
- [ ] The file still starts with a UTF-8 BOM and uses CRLF line endings
      (CI checks this too).
- [ ] UI strings are in Spanish (English UI / i18n is on the roadmap — help
      welcome) and don't rely on ANSI codepage rendering.
- [ ] Updated `README.md`, `README.es.md` and `CHANGELOG.md` if you added or
      changed a tweak, action or profile.

## Workflow

1. Fork, create a branch, make your change.
2. Open a pull request describing **what** the tweak does, **why** it helps,
   and **how** you tested it (hardware/OS included).
3. Be kind and constructive — keep discussions on-topic. By contributing you
   agree your changes are released under the project's [MIT license](LICENSE).
