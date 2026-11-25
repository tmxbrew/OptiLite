#requires -version 5.1
# ============================================================================
#
#   ██████╗  ██████╗  ████████╗ ██╗ ██╗      ██╗ ████████╗ ███████╗
#  ██╔═══██╗ ██╔══██╗ ╚══██╔══╝ ██║ ██║      ██╗ ╚══██╔══╝ ██╔════╝
#  ██║   ██║ ██████╔╝    ██║    ██║ ██║      ██║    ██║    █████╗
#  ██║   ██║ ██╔═══╝     ██║    ██║ ██║      ██║    ██║    ██╔══╝
#  ╚██████╔╝ ██║         ██║    ██║ ███████╗ ██╗    ██║    ███████╗
#   ╚═════╝  ╚═╝         ╚═╝    ╚═╝ ╚══════╝ ╚═╝    ╚═╝    ╚══════╝
#
#  OptiLite v1.1.0 · Optimizador local de Windows 10/11 con interfaz gráfica
#  --------------------------------------------------------------------------
#  - 100% local: sin descargas, sin instalaciones, sin telemetría, sin red.
#  - Paneles: Resumen | Rendimiento | Juegos | Privacidad | Limpieza | Inicio
#    | Perfiles  (v1.1: panel "Inicio" con programas de arranque).
#  - Interfaz ES/EN conmutable en vivo; preferencia guardada en optilite.json.
#  - Todo reversible: punto de restauración + pila "Deshacer último" +
#    exportar/importar copia de seguridad + preset "Restaurar Windows".
#  - Modo "Vista previa": muestra qué cambiaría un ajuste/perfil sin aplicarlo.
#  - Registro y copias de seguridad en %LOCALAPPDATA%\OptiLite\
#
#  Uso:  clic derecho sobre OptiLite.ps1 -> "Ejecutar con PowerShell"
#        (se auto-eleva a Administrador), o bien:
#        powershell -NoProfile -ExecutionPolicy Bypass -File .\OptiLite.ps1
#
#  Inspirado en herramientas como WinUtil (Chris Titus Tech) y WinHance.
#  Licencia MIT. Sin garantía de ningún tipo: revisa el código antes de
#  ejecutarlo y crea un punto de restauración del sistema si lo deseas.
#  Detalles en el repositorio: LICENSE, README.md, README.es.md, SECURITY.md.
# ============================================================================

# ---------------- Auto-elevar a Administrador si no tiene permisos ----------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    Start-Process -FilePath "powershell.exe" -ArgumentList $argList -Verb RunAs
    exit
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$ErrorActionPreference = 'SilentlyContinue'
$script:PendingReboot = $false
$script:Preview = $false
$script:Version = '1.1.0'
$script:AppDir = Join-Path $env:LOCALAPPDATA 'OptiLite'
$script:LogPath = Join-Path $script:AppDir 'optilite.log'
$script:BackupPath = Join-Path $script:AppDir 'optilite-restore.json'
$script:CfgPath = Join-Path $script:AppDir 'optilite.json'
$script:UndoPath = Join-Path $script:AppDir 'optilite-undo.json'
$script:DisabledDir = Join-Path $script:AppDir 'disabled-startup'
if (-not (Test-Path $script:AppDir)) { New-Item -Path $script:AppDir -ItemType Directory -Force | Out-Null }
$script:ScriptPath = $PSCommandPath

# ---------------- Idioma (ES por defecto, persistido en optilite.json) ------
$script:Lang = 'ES'
try {
    if (Test-Path $script:CfgPath) {
        $cfg = Get-Content -Path $script:CfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($cfg.Lang -eq 'EN') { $script:Lang = 'EN' }
    }
} catch {}

function T([string]$es, [string]$en) {
    if ($script:Lang -eq 'EN') { return $en } else { return $es }
}

function L($texts) {
    # $texts: hashtable @{ ES = '...'; EN = '...' }
    if ($null -eq $texts) { return '' }
    $v = $texts[$script:Lang]
    if ($null -eq $v -and $texts.Keys -contains 'ES') { $v = $texts['ES'] }
    return [string]$v
}

# ---------------- Logging ----------------------------------------------------
function Write-TempLog([string]$msg) {
    try {
        $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Add-Content -Path $script:LogPath -Value "[$stamp] $msg" -EA 0
    } catch {}
}

# ---------------- Helpers de registro ---------------------------------------
function Get-Reg([string]$path, [string]$name) {
    try {
        $p = Get-ItemProperty -Path $path -EA 0
        if ($null -eq $p) { return $null }
        return $p.$name
    } catch { return $null }
}

function Set-Reg([string]$path, [string]$name, $value, [string]$type = 'DWord') {
    try {
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name $name -Value $value -Type $type -EA 0
    } catch {}
}

# ---------------- Helpers de servicios --------------------------------------
function Get-ServiceStartMode($name) {
    $path = "HKLM:\SYSTEM\CurrentControlSet\Services\$name"
    if (-not (Test-Path $path)) { return -1 }
    $val = (Get-ItemProperty -Path $path -Name 'Start' -EA 0).Start
    if ($null -eq $val) { return -1 }
    return [int]$val
}

function Set-ServiceMode($name, [int]$startVal, [bool]$stopNow = $false, [bool]$startNow = $false) {
    $path = "HKLM:\SYSTEM\CurrentControlSet\Services\$name"
    if (-not (Test-Path $path)) { return $false }
    if ($stopNow) { Stop-Service -Name $name -Force -EA 0 }
    Set-ItemProperty -Path $path -Name 'Start' -Value $startVal -Type DWord -EA 0
    if ($startNow) { Start-Service -Name $name -EA 0 }
    return $true
}

# ---------------- Modulos especificos (heredados de v1, probados) -----------
function Set-VanguardState([bool]$enable) {
    $vgk = Get-ServiceStartMode 'vgk'
    $vgc = Get-ServiceStartMode 'vgc'
    if ($vgk -eq -1 -and $vgc -eq -1) { return "NOT_INSTALLED" }
    $runKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
    $bakKey = "HKLM:\SOFTWARE\OptiLite"
    if ($enable) {
        Set-ServiceMode 'vgk' 1 $false $false | Out-Null
        Set-ServiceMode 'vgc' 3 $false $false | Out-Null
        if (Test-Path $bakKey) {
            $vgPath = (Get-ItemProperty -Path $bakKey -Name 'RiotVanguardRun' -EA 0).RiotVanguardRun
            if ($vgPath) { Set-ItemProperty -Path $runKey -Name 'Riot Vanguard' -Value $vgPath -EA 0 }
        } elseif (Test-Path "$env:ProgramFiles\Riot Vanguard\vgtray.exe") {
            Set-ItemProperty -Path $runKey -Name 'Riot Vanguard' -Value "`"$env:ProgramFiles\Riot Vanguard\vgtray.exe`"" -EA 0
        }
        Write-TempLog "Riot Vanguard activado (requiere reinicio)."
        return "REBOOT_REQUIRED"
    } else {
        Stop-Process -Name 'vgtray' -Force -EA 0
        Set-ServiceMode 'vgc' 4 $true $false | Out-Null
        Set-ServiceMode 'vgk' 4 $false $false | Out-Null
        $curRun = (Get-ItemProperty -Path $runKey -Name 'Riot Vanguard' -EA 0).'Riot Vanguard'
        if ($curRun) {
            if (-not (Test-Path $bakKey)) { New-Item -Path $bakKey -Force | Out-Null }
            Set-ItemProperty -Path $bakKey -Name 'RiotVanguardRun' -Value $curRun -EA 0
            Remove-ItemProperty -Path $runKey -Name 'Riot Vanguard' -EA 0
        }
        Write-TempLog "Riot Vanguard desactivado (requiere reinicio)."
        return "REBOOT_REQUIRED"
    }
}

function Set-FaceitState([bool]$enable) {
    $f1 = Get-ServiceStartMode 'FACEIT'
    $f2 = Get-ServiceStartMode 'FACEITService'
    if ($f1 -eq -1 -and $f2 -eq -1) { return "NOT_INSTALLED" }
    if ($enable) {
        Set-ServiceMode 'FACEIT' 3 $false $false | Out-Null
        Set-ServiceMode 'FACEITService' 3 $false $false | Out-Null
        Write-TempLog "FACEIT Anti-Cheat activado."
        return "OK"
    } else {
        Stop-Process -Name 'faceitclient','faceit' -Force -EA 0
        Set-ServiceMode 'FACEITService' 4 $true $false | Out-Null
        Set-ServiceMode 'FACEIT' 4 $true $false | Out-Null
        Write-TempLog "FACEIT Anti-Cheat detenido y desactivado."
        return "OK"
    }
}

function Set-XboxState([bool]$enable) {
    $xboxServices = @('XblAuthManager', 'XblGameSave', 'XboxGipSvc', 'XboxNetApiSvc', 'GamingServices', 'GamingServicesNet')
    if ($enable) {
        foreach ($s in $xboxServices) {
            $shouldStart = $s -in @('XblAuthManager', 'XboxNetApiSvc', 'XboxGipSvc', 'XblGameSave')
            Set-ServiceMode $s 3 $false $shouldStart | Out-Null
        }
        Write-TempLog "Servicios Xbox activados."
    } else {
        foreach ($s in $xboxServices) { Set-ServiceMode $s 4 $true $false | Out-Null }
        Write-TempLog "Servicios Xbox desactivados."
    }
    return "OK"
}

function Set-AudioDawState([bool]$enable) {
    $mmcss = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
    $audTask = "$mmcss\Tasks\Audio"
    $proAudio = "$mmcss\Tasks\Pro Audio"
    if (-not (Test-Path $audTask)) { New-Item -Path $audTask -Force | Out-Null }
    if (-not (Test-Path $proAudio)) { New-Item -Path $proAudio -Force | Out-Null }
    if ($enable) {
        Set-ItemProperty -Path $mmcss -Name 'SystemResponsiveness' -Value 10 -Type DWord -EA 0
        Set-ItemProperty -Path $audTask -Name 'Priority' -Value 6 -Type DWord -EA 0
        Set-ItemProperty -Path $audTask -Name 'Scheduling Category' -Value 'High' -Type String -EA 0
        Set-ItemProperty -Path $proAudio -Name 'Priority' -Value 6 -Type DWord -EA 0
        Set-ItemProperty -Path $proAudio -Name 'Scheduling Category' -Value 'High' -Type String -EA 0
        Start-Service -Name 'Audiosrv','AudioEndpointBuilder' -EA 0
        Write-TempLog "Modo DAW activado (SystemResponsiveness=10)."
    } else {
        Set-ItemProperty -Path $mmcss -Name 'SystemResponsiveness' -Value 0 -Type DWord -EA 0
        Set-ItemProperty -Path $audTask -Name 'Priority' -Value 2 -Type DWord -EA 0
        Set-ItemProperty -Path $audTask -Name 'Scheduling Category' -Value 'Medium' -Type String -EA 0
        Write-TempLog "Modo Gaming audio restaurado (SystemResponsiveness=0)."
    }
    return "OK"
}

function Set-VbsState([bool]$enable) {
    $dg = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard"
    $hvci = "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity"
    if (-not (Test-Path $dg)) { New-Item -Path $dg -Force | Out-Null }
    if (-not (Test-Path $hvci)) { New-Item -Path $hvci -Force | Out-Null }
    $val = if ($enable) { 1 } else { 0 }
    Set-ItemProperty -Path $dg -Name 'EnableVirtualizationBasedSecurity' -Value $val -Type DWord -EA 0
    Set-ItemProperty -Path $hvci -Name 'Enabled' -Value $val -Type DWord -EA 0
    Write-TempLog "VBS / HVCI actualizado a $enable (requiere reinicio)."
    return "REBOOT_REQUIRED"
}

# ---------------- Red avanzada (v1.1) ----------------------------------------
function Set-NagleState([bool]$enable) {
    $ifRoot = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
    $ifs = Get-ChildItem -Path $ifRoot -EA 0
    foreach ($i in $ifs) {
        if ($enable) {
            Set-Reg $i.PSPath 'TcpAckFrequency' 1
            Set-Reg $i.PSPath 'TCPNoDelay' 1
        } else {
            Remove-ItemProperty -Path $i.PSPath -Name 'TcpAckFrequency' -EA 0
            Remove-ItemProperty -Path $i.PSPath -Name 'TCPNoDelay' -EA 0
        }
    }
    Write-TempLog "Nagle $enable en $($ifs.Count) interfaces (requiere reinicio)."
}

function Get-NagleEnabled {
    $ifRoot = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
    foreach ($i in (Get-ChildItem -Path $ifRoot -EA 0)) {
        $v = Get-Reg $i.PSPath 'TcpAckFrequency'
        if ($null -ne $v -and [int]$v -eq 1) { return $false }
    }
    return $true
}

function Get-TcpAutotuningOn {
    try {
        $lvl = (Get-NetTCPSetting -SettingName Internet -EA 0).AutoTuningLevelLocal
        if ($null -ne $lvl) { return ($lvl -eq 'Normal') }
    } catch {}
    return $null
}

function Set-TcpAutotuning([bool]$enable) {
    $lvl = if ($enable) { 'Normal' } else { 'Disabled' }
    try {
        Set-NetTCPSetting -SettingName Internet -AutoTuningLevelLocal $lvl -EA Stop
        Write-TempLog "TCP autotuning -> $lvl."
        return $true
    } catch {
        return $false
    }
}

# ---------------- Acciones de limpieza y mantenimiento ----------------------
function Invoke-TempClean([bool]$deepClean = $false) {
    $before = (Get-ChildItem "$env:TEMP" -Recurse -Force -EA 0 | Measure-Object -Property Length -Sum).Sum
    if (-not $before) { $before = 0 }
    Get-ChildItem "$env:TEMP" -Force -EA 0 | Remove-Item -Recurse -Force -EA 0
    Get-ChildItem "C:\Windows\Temp" -Force -EA 0 | Remove-Item -Recurse -Force -EA 0
    if ($deepClean) {
        Get-ChildItem "C:\Windows\Prefetch" -Force -EA 0 | Remove-Item -Recurse -Force -EA 0
        Get-ChildItem "C:\Windows\Logs\CBS" -Filter "*.log" -Force -EA 0 | Remove-Item -Recurse -Force -EA 0
        Remove-Item "C:\ProgramData\Microsoft\Windows\WER\ReportQueue\*" -Recurse -Force -EA 0
        Remove-Item "C:\ProgramData\Microsoft\Windows\WER\ReportArchive\*" -Recurse -Force -EA 0
        Stop-Service -Name wuauserv, bits -Force -EA 0
        Remove-Item "C:\Windows\SoftwareDistribution\Download\*" -Recurse -Force -EA 0
        Start-Service -Name wuauserv -EA 0
        Start-Service -Name bits -EA 0
    }
    $after = (Get-ChildItem "$env:TEMP" -Recurse -Force -EA 0 | Measure-Object -Property Length -Sum).Sum
    if (-not $after) { $after = 0 }
    $freedMB = [math]::Max(0, [math]::Round(($before - $after) / 1MB, 1))
    Write-TempLog "Limpieza (deep=$deepClean): ~$freedMB MB liberados."
    return $freedMB
}

function Ensure-GamingPowerPlan {
    $guid = "11111111-1111-1111-1111-111111111111"
    $exists = powercfg.exe -list | Select-String -SimpleMatch $guid
    if (-not $exists) {
        powercfg.exe -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 $guid | Out-Null
        powercfg.exe -changename $guid "Gaming Ultimate Performance" "Maximo rendimiento sin ahorro de energia" | Out-Null
        powercfg.exe -setacvalueindex $guid sub_processor CPMINCORES 100 | Out-Null
        powercfg.exe -setacvalueindex $guid sub_processor PROCTHROTTLEMIN 100 | Out-Null
        powercfg.exe -setacvalueindex $guid 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0 | Out-Null
        powercfg.exe -setacvalueindex $guid sub_pciexpress ee12f906-d277-404b-b6da-e5fa1a576df5 0 | Out-Null
    }
    powercfg.exe -setactive $guid | Out-Null
    Write-TempLog "Plan Gaming Ultimate Performance verificado/activado."
}

function Create-DesktopShortcut {
    if (-not $script:ScriptPath -or -not (Test-Path $script:ScriptPath)) { return $null }
    $targetFile = $script:ScriptPath
    $desktopDir = [Environment]::GetFolderPath('Desktop')
    $scPath = Join-Path $desktopDir 'OptiLite.lnk'
    $wsh = New-Object -ComObject WScript.Shell
    $sc = $wsh.CreateShortcut($scPath)
    $sc.TargetPath = "powershell.exe"
    $sc.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$targetFile`""
    $sc.WorkingDirectory = Split-Path -Parent $targetFile
    $sc.Description = "OptiLite - Optimizador de Windows 10/11 (rendimiento, juegos, privacidad)"
    $sc.IconLocation = "C:\Windows\System32\imageres.dll,109"
    $sc.Save()

    # Marcar el .lnk para que solicite/ejecute como Administrador (byte 0x15 bit 5 = 0x20)
    $bytes = [System.IO.File]::ReadAllBytes($scPath)
    if ($bytes.Length -gt 0x15) {
        $bytes[0x15] = $bytes[0x15] -bor 0x20
        [System.IO.File]::WriteAllBytes($scPath, $bytes)
    }
    Write-TempLog "Acceso directo creado en Escritorio: $scPath"
    return $scPath
}

# ---------------- Punto de restauración (deshacer cambios) -------------------
function New-RestorePoint {
    $states = @{}
    foreach ($it in $script:Items) {
        $cur = & $it.Get
        if ($null -ne $cur) { $states[$it.Id] = [bool]$cur }
    }
    $point = @{ Version = $script:Version; Date = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); States = $states }
    try {
        $point | ConvertTo-Json -Depth 4 | Set-Content -Path $script:BackupPath -Encoding UTF8
    } catch {
        Write-TempLog "No se pudo escribir el punto de restauracion: $($_.Exception.Message)"
        return (T 'No se pudo crear el punto de restauración (revisa los permisos de %LOCALAPPDATA%\OptiLite).' 'Could not create the restore point (check permissions on %LOCALAPPDATA%\OptiLite).')
    }
    Write-TempLog "Punto de restauracion creado ($($states.Count) ajustes)."
    return (T "Punto de restauración creado: $($states.Count) ajustes guardados en optilite-restore.json." "Restore point created: $($states.Count) settings saved to optilite-restore.json.")
}

function Restore-RestorePoint {
    if (-not (Test-Path $script:BackupPath)) { return (T 'Todavía no hay ningún punto de restauración guardado.' 'No restore point has been saved yet.') }
    try {
        $point = Get-Content -Path $script:BackupPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return (T 'El punto de restauración está dañado; crea uno nuevo con "Crear punto de restauración".' 'The restore point is corrupted; create a new one with "Create restore point".')
    }
    if (-not $point.States) { return (T 'El punto de restauración está vacío; crea uno nuevo.' 'The restore point is empty; create a new one.') }
    $changed = 0
    $reboot = $false
    foreach ($prop in $point.States.PSObject.Properties) {
        $it = $script:ItemMap[$prop.Name]
        if (-not $it) { continue }
        $want = [bool]$prop.Value
        $cur = & $it.Get
        if ($cur -ne $want) {
            & $it.Set $want
            $changed++
            if ($it.Reboot) { $reboot = $true }
        }
    }
    if ($reboot) { $script:PendingReboot = $true }
    Write-TempLog "Punto de restauracion aplicado ($changed ajustes revertidos)."
    $extra = if ($reboot) { (T ' (reinicia para aplicar)' ' (reboot to apply)') } else { '' }
    $dateStr = [string]$point.Date
    return (T "Punto del $dateStr restaurado: $changed ajustes revertidos$extra." "Point from $dateStr restored: $changed settings reverted$extra.")
}

# ---------------- Pila de deshacer (v1.1) ------------------------------------
function Initialize-UndoStack {
    $script:UndoStackRaw = @()
    try {
        if (Test-Path $script:UndoPath) {
            $arr = @(Get-Content -Path $script:UndoPath -Raw -Encoding UTF8 | ConvertFrom-Json)
            $script:UndoStackRaw = $arr
        }
    } catch { $script:UndoStackRaw = @() }
    $script:UndoStack = @($script:UndoStackRaw)
}

function Save-UndoStack {
    try {
        ConvertTo-Json -InputObject $script:UndoStack -Depth 4 | Set-Content -Path $script:UndoPath -Encoding UTF8
    } catch {
        Write-TempLog "No se pudo guardar la pila de deshacer: $($_.Exception.Message)"
    }
}

function Push-Undo([string]$id, $from, $to) {
    $entry = @{ Id = $id; From = [bool]$from; To = [bool]$to; Time = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') }
    $script:UndoStack = @($script:UndoStack) + @($entry)
    if ($script:UndoStack.Count -gt 50) { $script:UndoStack = $script:UndoStack[-50..-1] }
    $script:UndoStackRaw = $script:UndoStack
    Save-UndoStack
}

function Undo-Last {
    if (-not $script:UndoStack -or $script:UndoStack.Count -lt 1) {
        return (T 'No hay cambios recientes que deshacer.' 'There are no recent changes to undo.')
    }
    $entry = $script:UndoStack[-1]
    $script:UndoStack = @()
    if ($script:UndoStackRaw.Count -gt 1) { $script:UndoStack = $script:UndoStackRaw[0..($script:UndoStackRaw.Count - 2)] }
    $script:UndoStackRaw = $script:UndoStack
    Save-UndoStack
    $it = $script:ItemMap[$entry.Id]
    if (-not $it) {
        return (T 'El último cambio ya no está disponible (ajuste desconocido).' 'The last change is no longer available (unknown setting).')
    }
    & $it.Set ([bool]$entry.From)
    if ($it.Reboot) { $script:PendingReboot = $true }
    $name = L $it.Name
    $word = if ([bool]$entry.From) { (T 'activado' 'enabled') } else { (T 'desactivado' 'disabled') }
    Write-TempLog "Deshacer: '$($it.Id)' -> $word."
    $extra = if ($it.Reboot) { (T ' (reinicia para aplicar)' ' (reboot to apply)') } else { '' }
    return (T "Deshecho: $name ahora $word$extra." "Undone: $name is now $word$extra.")
}

# ---------------- Exportar / importar copia de seguridad (v1.1) --------------
function Export-BackupFile {
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Filter = (T 'Copia de OptiLite (*.json)|*.json' 'OptiLite backup (*.json)|*.json')
    $dlg.FileName = "optilite-backup-$(Get-Date -Format 'yyyyMMdd-HHmm').json"
    if ($dlg.ShowDialog($script:Window) -ne $true) { return (T 'Exportación cancelada.' 'Export cancelled.') }
    $states = @{}
    foreach ($it in $script:Items) {
        $cur = & $it.Get
        if ($null -ne $cur) { $states[$it.Id] = [bool]$cur }
    }
    $data = @{ Version = $script:Version; Date = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); States = $states }
    try {
        $data | ConvertTo-Json -Depth 4 | Set-Content -Path $dlg.FileName -Encoding UTF8
    } catch {
        return (T 'No se pudo escribir el archivo de copia.' 'Could not write the backup file.')
    }
    Write-TempLog "Copia exportada a: $($dlg.FileName)"
    return (T "Copia exportada: $($states.Count) ajustes en $($dlg.FileName)." "Backup exported: $($states.Count) settings to $($dlg.FileName).")
}

function Import-BackupFile {
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Filter = (T 'Copia de OptiLite (*.json)|*.json' 'OptiLite backup (*.json)|*.json')
    if ($dlg.ShowDialog($script:Window) -ne $true) { return (T 'Importación cancelada.' 'Import cancelled.') }
    try {
        $data = Get-Content -Path $dlg.FileName -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return (T 'El archivo no es una copia válida de OptiLite.' 'The file is not a valid OptiLite backup.')
    }
    if (-not $data.States) {
        return (T 'La copia no contiene estados; elige un archivo creado por "Exportar copia".' 'The backup contains no states; pick a file created by "Export backup".')
    }
    $changed = 0
    $reboot = $false
    foreach ($prop in $data.States.PSObject.Properties) {
        $it = $script:ItemMap[$prop.Name]
        if (-not $it) { continue }
        $want = [bool]$prop.Value
        $cur = & $it.Get
        if ($null -ne $cur -and $cur -ne $want) {
            & $it.Set $want
            Push-Undo $it.Id $cur $want
            $changed++
            if ($it.Reboot) { $reboot = $true }
        }
    }
    if ($reboot) { $script:PendingReboot = $true }
    Write-TempLog "Copia importada desde $($dlg.FileName) ($changed ajustes)."
    $extra = if ($reboot) { (T ' (reinicia para aplicar)' ' (reboot to apply)') } else { '' }
    $dateStr = [string]$data.Date
    return (T "Copia del $dateStr importada: $changed ajustes aplicados$extra." "Backup from $dateStr imported: $changed settings applied$extra.")
}

# ---------------- Programas de inicio (v1.1) ---------------------------------
function Get-StartupEntries {
    $list = @()
    $runHives = @(
        @{ Loc = 'HKLM'; Key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run' },
        @{ Loc = 'HKCU'; Key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' }
    )
    foreach ($hive in $runHives) {
        $props = Get-ItemProperty -Path $hive.Key -EA 0
        if ($props) {
            foreach ($p in $props.PSObject.Properties) {
                if ($p.Name -match '^(PSPath|PSParentPath|PSChildName|PSDrive|PSProvider)$') { continue }
                $list += @{ Name = $p.Name; Cmd = [string]$p.Value; Loc = $hive.Loc; Key = $hive.Key; Type = 'Reg' }
            }
        }
        $bakKey = "HKLM:\SOFTWARE\OptiLite\StartupBackup\$($hive.Loc)"
        if (Test-Path $bakKey) {
            $bprops = Get-ItemProperty -Path $bakKey -EA 0
            if ($bprops) {
                foreach ($p in $bprops.PSObject.Properties) {
                    if ($p.Name -match '^(PSPath|PSParentPath|PSChildName|PSDrive|PSProvider)$') { continue }
                    $list += @{ Name = $p.Name; Cmd = [string]$p.Value; Loc = $hive.Loc; Key = $hive.Key; Type = 'Reg'; Disabled = $true }
                }
            }
        }
    }
    $startDir = [Environment]::GetFolderPath('Startup')
    if ($startDir -and (Test-Path $startDir)) {
        foreach ($f in (Get-ChildItem -Path $startDir -EA 0)) {
            $list += @{ Name = $f.BaseName; Cmd = $f.Name; Loc = 'Folder'; Path = $f.FullName; Type = 'Folder' }
        }
    }
    if (Test-Path $script:DisabledDir) {
        foreach ($f in (Get-ChildItem -Path $script:DisabledDir -EA 0)) {
            $list += @{ Name = $f.BaseName; Cmd = $f.Name; Loc = 'Folder'; Path = $f.FullName; Type = 'Folder'; Disabled = $true }
        }
    }
    return $list
}

function Set-StartupEnabled($entry, [bool]$on) {
    if ($entry.Type -eq 'Folder') {
        $startDir = [Environment]::GetFolderPath('Startup')
        if (-not (Test-Path $script:DisabledDir)) { New-Item -Path $script:DisabledDir -ItemType Directory -Force | Out-Null }
        if ($on) {
            if (-not $entry.Path -or -not (Test-Path $entry.Path)) { return (T 'No se encontró el archivo para reactivar.' 'The file to re-enable was not found.') }
            Move-Item -Path $entry.Path -Destination (Join-Path $startDir $entry.Cmd) -Force -EA Stop
        } else {
            if (-not $entry.Path -or -not (Test-Path $entry.Path)) { return (T 'No se encontró el archivo que desactivar.' 'The file to disable was not found.') }
            Move-Item -Path $entry.Path -Destination (Join-Path $script:DisabledDir $entry.Cmd) -Force -EA Stop
        }
        Write-TempLog "Inicio '$($entry.Name)' ($($entry.Loc)) -> $on."
        return 'OK'
    }
    $bakKey = "HKLM:\SOFTWARE\OptiLite\StartupBackup\$($entry.Loc)"
    if ($on) {
        $cmd = (Get-Reg $bakKey $entry.Name)
        if (-not $cmd) { return (T 'No hay respaldo para este programa; actívalo desde su instalador.' 'No backup exists for this program; re-enable it from its installer.') }
        if (-not (Test-Path $entry.Key)) { New-Item -Path $entry.Key -Force | Out-Null }
        Set-ItemProperty -Path $entry.Key -Name $entry.Name -Value $cmd -EA 0
        Remove-ItemProperty -Path $bakKey -Name $entry.Name -EA 0
    } else {
        if (-not (Test-Path $bakKey)) { New-Item -Path $bakKey -Force | Out-Null }
        Set-ItemProperty -Path $bakKey -Name $entry.Name -Value $entry.Cmd -EA 0
        Remove-ItemProperty -Path $entry.Key -Name $entry.Name -EA 0
    }
    Write-TempLog "Inicio '$($entry.Name)' ($($entry.Loc)) -> $on."
    return 'OK'
}
# ============================================================================
#  DEFINICION DE AJUSTES  (motor data-driven, estilo WinUtil/WinHance)
#  Cada item:  Id, Cat (Perf/Games/Priv), Grp (subgrupo ES/EN), Name/Desc (ES/EN),
#  Reboot (si cambia → pide reinicio), Get (estado actual: $true/$false/$null),
#  Set (aplica $true/$false).  $null en Get = "no instalado" (interruptor gris).
# ============================================================================

$Items = @(
    # ------------------------------ RENDIMIENTO ------------------------------
    @{ Id='vbs'; Cat='Perf'; Grp=@{ES='Sistema y energía';EN='System & power'}; Reboot=$true
       Name=@{ES='VBS / Integridad de memoria';EN='VBS / Memory integrity'}
       Desc=@{ES='Aísla el kernel con virtualización. Desactivado gana ~5-8% de FPS en la mayoría de equipos; Vanguard y FACEIT funcionan igual sin él.'
              EN='Isolates the kernel with virtualization. Off gains ~5-8% FPS on most systems; Vanguard and FACEIT work fine without it.'}
       Get={ (Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'EnableVirtualizationBasedSecurity') -eq 1 }
       Set={ param($on) Set-VbsState $on | Out-Null } }

    @{ Id='fx'; Cat='Perf'; Grp=@{ES='Sistema y energía';EN='System & power'}; Reboot=$false
       Name=@{ES='Efectos visuales en modo rendimiento';EN='Visual effects in performance mode'}
       Desc=@{ES='ON = animaciones y transparencias al mínimo (más FPS libres). OFF = Windows decide (aspecto por defecto).'
              EN='ON = minimal animations/transparency (extra free FPS). OFF = Windows decides (default look).'}
       Get={ (Get-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting') -eq 2 }
       Set={ param($on) Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' $(if($on){2}else{0}) } }

    @{ Id='sysmain'; Cat='Perf'; Grp=@{ES='Sistema y energía';EN='System & power'}; Reboot=$false
       Name=@{ES='SysMain (Superfetch)';EN='SysMain (Superfetch)'}
       Desc=@{ES='Precarga apps frecuentes en RAM. Con SSD y RAM suficiente su beneficio es bajo: desactívalo para liberar disco y CPU.'
              EN='Pre-loads frequent apps into RAM. Little benefit with an SSD and enough RAM: disable to free disk and CPU.'}
       Get={ $m = Get-ServiceStartMode 'SysMain'; if ($m -eq -1) { $null } else { $m -ne 4 } }
       Set={ param($on) if ($on) { Set-ServiceMode 'SysMain' 2 $false $true | Out-Null } else { Set-ServiceMode 'SysMain' 4 $true $false | Out-Null } } }

    @{ Id='wsearch'; Cat='Perf'; Grp=@{ES='Sistema y energía';EN='System & power'}; Reboot=$false
       Name=@{ES='Windows Search (indexación)';EN='Windows Search (indexing)'}
       Desc=@{ES='Indexa archivos en segundo plano. Desactivado ahorra CPU/disco constante; el buscador será más lento.'
              EN='Indexes files in the background. Off saves constant CPU/disk; the search box becomes slower.'}
       Get={ $m = Get-ServiceStartMode 'WSearch'; if ($m -eq -1) { $null } else { $m -ne 4 } }
       Set={ param($on) if ($on) { Set-ServiceMode 'WSearch' 2 $false $true | Out-Null } else { Set-ServiceMode 'WSearch' 4 $true $false | Out-Null } } }

    @{ Id='hiber'; Cat='Perf'; Grp=@{ES='Sistema y energía';EN='System & power'}; Reboot=$false
       Name=@{ES='Hibernación e Inicio rápido';EN='Hibernation & Fast Startup'}
       Desc=@{ES='OFF libera ~6-13 GB del SSD (hiberfil.sys) y evita raridades de drivers al arrancar. ON restaura ambos.'
              EN='OFF frees ~6-13 GB of SSD (hiberfil.sys) and avoids odd driver states at boot. ON restores both.'}
       Get={ Test-Path 'C:\hiberfil.sys' }
       Set={ param($on) if ($on) { powercfg.exe /h on | Out-Null } else { powercfg.exe /h off | Out-Null } } }

    @{ Id='bgapps'; Cat='Perf'; Grp=@{ES='Sistema y energía';EN='System & power'}; Reboot=$false
       Name=@{ES='Apps en segundo plano';EN='Background apps'}
       Desc=@{ES='Permite que apps UWP sigan ejecutándose cerradas. OFF reduce consumo de RAM y CPU (no afecta programas de escritorio).'
              EN='Lets UWP apps keep running while closed. Off lowers RAM/CPU usage (desktop apps unaffected).'}
       Get={ (Get-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled') -ne 1 }
       Set={ param($on) Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' $(if($on){0}else{1}) } }

    @{ Id='net'; Cat='Perf'; Grp=@{ES='Red';EN='Network'}; Reboot=$true
       Name=@{ES='Límite de red multimedia (throttling)';EN='Multimedia network throttling'}
       Desc=@{ES='Windows limita el tráfico de red a 10 paquetes/ms. OFF elimina el límite → menos latencia y mejor online.'
              EN='Windows caps network traffic at 10 packets/ms. Off removes the cap → lower latency, better online play.'}
       Get={ $v = Get-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex'; ($v -ne -1 -and $v -ne 4294967295) }
       Set={ param($on) $val = if ($on) { 10 } else { 0xFFFFFFFF }; Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex' $val } }

    @{ Id='autotcp'; Cat='Perf'; Grp=@{ES='Red';EN='Network'}; Reboot=$true
       Name=@{ES='TCP Autotuning (nivel normal)';EN='TCP Autotuning (normal level)'}
       Desc=@{ES='Windows ajusta el tamaño de ventana TCP. Desactivarlo (OFF) fija una ventana fija: en pocos equipos baja la latencia, pero suele PERDER throughput.'
              EN='Windows tunes the TCP window size. Off fixes a static window: rarely lowers latency and usually LOSES throughput.'}
       Get={ Get-TcpAutotuningOn }
       Set={ param($on) $null = Set-TcpAutotuning $on } }

    @{ Id='nagle'; Cat='Perf'; Grp=@{ES='Red';EN='Network'}; Reboot=$true
       Name=@{ES='Nagle / TCP AckFrequency';EN='Nagle / TCP AckFrequency'}
       Desc=@{ES='Agrupa paquetes pequeños antes de enviarlos. OFF fuerza envío inmediato (TcpAckFrequency=1, TCPNoDelay=1) → menos latencia en juegos online; requiere reinicio.'
              EN='Batches small packets before sending. Off forces immediate send (TcpAckFrequency=1, TCPNoDelay=1) → lower latency for online games; reboot required.'}
       Get={ Get-NagleEnabled }
       Set={ param($on) Set-NagleState $on } }

    # --------------------------------- JUEGOS --------------------------------
    @{ Id='vg'; Cat='Games'; Grp=@{ES='Anti-cheats';EN='Anti-cheats'}; Reboot=$true
       Name=@{ES='Riot Vanguard (Valorant)';EN='Riot Vanguard (Valorant)'}
       Desc=@{ES='Driver kernel vgk.sys + servicio vgc. Si Valorant no lo exige, mantenlo OFF para arrancar más rápido y sin procesos en kernel.'
              EN='vgk.sys kernel driver + vgc service. If Valorant does not require it, keep OFF for faster boot with no kernel processes.'}
       Get={ $a = Get-ServiceStartMode 'vgk'; $b = Get-ServiceStartMode 'vgc'; if ($a -eq -1 -and $b -eq -1) { $null } elseif ($a -ne 4) { $true } else { $false } }
       Set={ param($on) Set-VanguardState $on | Out-Null } }

    @{ Id='fac'; Cat='Games'; Grp=@{ES='Anti-cheats';EN='Anti-cheats'}; Reboot=$false
       Name=@{ES='FACEIT Anti-Cheat (CS2)';EN='FACEIT Anti-Cheat (CS2)'}
       Desc=@{ES='Controlador FACEIT + servicio auxiliar. Se activa y desactiva al instante, sin reiniciar.'
              EN='FACEIT driver + helper service. Toggles on/off instantly, no reboot needed.'}
       Get={ $a = Get-ServiceStartMode 'FACEIT'; $b = Get-ServiceStartMode 'FACEITService'; if ($a -eq -1 -and $b -eq -1) { $null } elseif (($a -ne 4 -and $a -ne -1) -or ($b -ne 4 -and $b -ne -1)) { $true } else { $false } }
       Set={ param($on) Set-FaceitState $on | Out-Null } }

    @{ Id='xbox'; Cat='Games'; Grp=@{ES='Servicios de juego';EN='Game services'}; Reboot=$false
       Name=@{ES='Servicios Xbox y Cloud Gaming';EN='Xbox & Cloud Gaming services'}
       Desc=@{ES='Xbox Live Auth, NetApi, GameSave, GamingServices y soporte de mandos. OFF si no usas Game Pass / juegos de la Store.'
              EN='Xbox Live Auth, NetApi, GameSave, GamingServices and controller support. OFF if you do not use Game Pass / Store games.'}
       Get={ $m = Get-ServiceStartMode 'XblAuthManager'; if ($m -eq -1) { $null } else { $m -ne 4 } }
       Set={ param($on) Set-XboxState $on | Out-Null } }

    @{ Id='gamemode'; Cat='Games'; Grp=@{ES='Captura y pantalla';EN='Capture & display'}; Reboot=$false
       Name=@{ES='Modo Juego (Game Mode)';EN='Game Mode'}
       Desc=@{ES='Da prioridad de CPU/GPU al juego en primer plano. Recomendado: ON.'
              EN='Gives foreground games CPU/GPU priority. Recommended: ON.'}
       Get={ (Get-Reg 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled') -ne 0 }
       Set={ param($on) $v = if ($on) { 1 } else { 0 }; Set-Reg 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' $v; Set-Reg 'HKCU:\Software\Microsoft\GameBar' 'AllowAutoGameMode' $v } }

    @{ Id='dvr'; Cat='Games'; Grp=@{ES='Captura y pantalla';EN='Capture & display'}; Reboot=$false
       Name=@{ES='Game Bar y DVR (grabación de fondo)';EN='Game Bar & DVR (background recording)'}
       Desc=@{ES='Graba clips en segundo plano y puede bajar FPS. Recomendado: OFF (las capturas con OBS no se ven afectadas).'
              EN='Records clips in the background and can drop FPS. Recommended: OFF (OBS captures unaffected).'}
       Get={ (Get-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled') -ne 0 -and (Get-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled') -ne 0 }
       Set={ param($on) $v = if ($on) { 1 } else { 0 }; Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' $v; Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' $v; Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' $v } }

    @{ Id='fso'; Cat='Games'; Grp=@{ES='Captura y pantalla';EN='Capture & display'}; Reboot=$false
       Name=@{ES='Optimizaciones de pantalla completa (FSO)';EN='Fullscreen optimizations (FSO)'}
       Desc=@{ES='ON = compatibilidad por defecto de Windows. OFF = exclusiva real → menos latencia y stutter; actívalo si un juego antiguo falla.'
              EN='ON = Windows default compatibility. OFF = true exclusive → less latency and stutter; enable if an old game fails.'}
       Get={ (Get-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_FSEBehaviorMode') -ne 2 }
       Set={ param($on) if ($on) { Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_FSEBehaviorMode' 0; Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_HonorUserFSEBehaviorMode' 0; Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_DXGIHonorFSEWindowsCompatible' 0 } else { Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_FSEBehaviorMode' 2; Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_HonorUserFSEBehaviorMode' 1; Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_DXGIHonorFSEWindowsCompatible' 1; Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_EFSEFeatureFlags' 0 } } }

    @{ Id='ptr'; Cat='Games'; Grp=@{ES='Precisión y hardware';EN='Precision & hardware'}; Reboot=$false
       Name=@{ES='Aceleración del puntero (precisión mejorada)';EN='Pointer acceleration (enhanced precision)'}
       Desc=@{ES='Curva de aceleración del ratón. OFF = movimiento 1:1 constante, estándar competitivo (CS2 / Valorant).'
              EN='Mouse acceleration curve. OFF = constant 1:1 movement, the competitive standard (CS2 / Valorant).'}
       Get={ (Get-Reg 'HKCU:\Control Panel\Mouse' 'MouseSpeed') -ne 0 }
       Set={ param($on) if ($on) { Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseSpeed' 1 'String'; Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseThreshold1' 6 'String'; Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseThreshold2' 10 'String' } else { Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseSpeed' 0 'String'; Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseThreshold1' 0 'String'; Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseThreshold2' 0 'String' } } }

    @{ Id='mpo'; Cat='Games'; Grp=@{ES='Precisión y hardware';EN='Precision & hardware'}; Reboot=$true
       Name=@{ES='MPO (Multi-Plane Overlay)';EN='MPO (Multi-Plane Overlay)'}
       Desc=@{ES='Conocido por causar microstutter y flashes en las GPU AMD Polaris (serie RX 400/500). OFF suele estabilizar el frametime.'
              EN='Known to cause microstutter and flicker on AMD Polaris GPUs (RX 400/500 series). OFF usually stabilizes frametime.'}
       Get={ (Get-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm' 'OverlayTestMode') -ne 5 }
       Set={ param($on) if ($on) { Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm' -Name 'OverlayTestMode' -EA 0 } else { Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm' 'OverlayTestMode' 5 } } }

    @{ Id='daw'; Cat='Games'; Grp=@{ES='Precisión y hardware';EN='Precision & hardware'}; Reboot=$false
       Name=@{ES='Modo DAW (audio prioritario)';EN='DAW mode (priority audio)'}
       Desc=@{ES='ON protege el buffer de audio para Ableton/FL (SystemResponsiveness=10). OFF = modo gaming (=0, máx. FPS).'
              EN='ON protects the audio buffer for Ableton/FL (SystemResponsiveness=10). OFF = gaming mode (=0, max FPS).'}
       Get={ (Get-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'SystemResponsiveness') -eq 10 }
       Set={ param($on) Set-AudioDawState $on | Out-Null } }

    # ------------------------------- PRIVACIDAD ------------------------------
    @{ Id='tele'; Cat='Priv'; Grp=@{ES='Datos y telemetría';EN='Data & telemetry'}; Reboot=$false
       Name=@{ES='Telemetría y datos de diagnóstico';EN='Telemetry & diagnostic data'}
       Desc=@{ES='Datos que Windows envía a Microsoft. OFF = nivel mínimo (en las ediciones LTSC se respeta el nivel Seguridad). Recomendado: OFF.'
              EN='Data Windows sends to Microsoft. OFF = minimum level (Security level honored on LTSC editions). Recommended: OFF.'}
       Get={ (Get-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry') -ne 0 }
       Set={ param($on) Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' $(if($on){1}else{0}) } }

    @{ Id='diag'; Cat='Priv'; Grp=@{ES='Datos y telemetría';EN='Data & telemetry'}; Reboot=$false
       Name=@{ES='Servicio DiagTrack (experiencias conectadas)';EN='DiagTrack service (connected experiences)'}
       Desc=@{ES='El servicio que sube la telemetría. Desactivarlo complementa el ajuste anterior; se aplica al instante.'
              EN='The service that uploads telemetry. Disabling it complements the previous tweak; applies instantly.'}
       Get={ $m = Get-ServiceStartMode 'DiagTrack'; if ($m -eq -1) { $null } else { $m -ne 4 } }
       Set={ param($on) if ($on) { Set-ServiceMode 'DiagTrack' 2 $false $true | Out-Null } else { Set-ServiceMode 'DiagTrack' 4 $true $false | Out-Null } } }

    @{ Id='act'; Cat='Priv'; Grp=@{ES='Datos y telemetría';EN='Data & telemetry'}; Reboot=$false
       Name=@{ES='Historial de actividad';EN='Activity history'}
       Desc=@{ES='Registro de apps y archivos usados que puede sincronizarse con la nube. Recomendado: OFF.'
              EN='Record of apps and files used that may sync to the cloud. Recommended: OFF.'}
       Get={ (Get-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableActivityFeed') -ne 0 }
       Set={ param($on) $v = if ($on) { 1 } else { 0 }; Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableActivityFeed' $v; Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'PublishUserActivities' $v; Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'UploadUserActivities' $v } }

    @{ Id='adid'; Cat='Priv'; Grp=@{ES='Personalización y anuncios';EN='Personalization & ads'}; Reboot=$false
       Name=@{ES='Identificador de publicidad';EN='Advertising ID'}
       Desc=@{ES='ID anónimo que las apps usan para personalizar anuncios. Recomendado: OFF.'
              EN='Anonymous ID apps use to personalize ads. Recommended: OFF.'}
       Get={ (Get-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled') -ne 0 }
       Set={ param($on) Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' $(if($on){1}else{0}) } }

    @{ Id='sugg'; Cat='Priv'; Grp=@{ES='Personalización y anuncios';EN='Personalization & ads'}; Reboot=$false
       Name=@{ES='Sugerencias, consejos y apps promocionadas';EN='Suggestions, tips & promoted apps'}
       Desc=@{ES='Recomendaciones en el menú Inicio y descargas automáticas de apps sugeridas. Recomendado: OFF.'
              EN='Start menu recommendations and automatic downloads of suggested apps. Recommended: OFF.'}
       Get={ (Get-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SystemPaneSuggestionsEnabled') -ne 0 }
       Set={ param($on) $v = if ($on) { 1 } else { 0 }; $p = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; foreach ($n in @('SystemPaneSuggestionsEnabled','SilentInstalledAppsEnabled','SubscribedContent-338388Enabled','SubscribedContent-338389Enabled','SubscribedContent-353698Enabled','SubscribedContent-310093Enabled')) { Set-Reg $p $n $v } } }

    @{ Id='ink'; Cat='Priv'; Grp=@{ES='Personalización y anuncios';EN='Personalization & ads'}; Reboot=$false
       Name=@{ES='Recolección de escritura y tinta';EN='Inking & typing collection'}
       Desc=@{ES='Envía lo que escribes/tecleas para "mejorar sugerencias". Recomendado: OFF.'
              EN='Sends what you write/type to "improve suggestions". Recommended: OFF.'}
       Get={ (Get-Reg 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection') -ne 1 }
       Set={ param($on) $v = if ($on) { 0 } else { 1 }; Set-Reg 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' $v; Set-Reg 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' $v; Set-Reg 'HKCU:\Software\Microsoft\Personalization\Settings' 'AcceptedPrivacyPolicy' $(if($on){1}else{0}) } }

    @{ Id='fb'; Cat='Priv'; Grp=@{ES='Personalización y anuncios';EN='Personalization & ads'}; Reboot=$false
       Name=@{ES='Notificaciones de comentarios (Feedback)';EN='Feedback notifications'}
       Desc=@{ES='Encuestas "¿Qué te parece Windows?" que aparecen de vez en cuando. Recomendado: OFF.'
              EN='"How is Windows?" surveys that pop up now and then. Recommended: OFF.'}
       Get={ (Get-Reg 'HKCU:\Software\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod') -ne 0 }
       Set={ param($on) Set-Reg 'HKCU:\Software\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod' $(if($on){1}else{0}) } }

    @{ Id='lang'; Cat='Priv'; Grp=@{ES='Personalización y anuncios';EN='Personalization & ads'}; Reboot=$false
       Name=@{ES='Enviar idioma local a los sitios web';EN='Send local language to websites'}
       Desc=@{ES='Los sitios pueden pedir tu lista de idiomas para fingerprinting leve. Recomendado: OFF.'
              EN='Sites can request your language list for light fingerprinting. Recommended: OFF.'}
       Get={ (Get-Reg 'HKCU:\Control Panel\International\User Profile' 'HttpAcceptLanguageOptOut') -ne 1 }
       Set={ param($on) Set-Reg 'HKCU:\Control Panel\International\User Profile' 'HttpAcceptLanguageOptOut' $(if($on){0}else{1}) } }
)

# --------------------------- Acciones (botones) -----------------------------
$Actions = @(
    @{ Id='quick';  Cat='Clean'; Grp=@{ES='Archivos y caché';EN='Files & cache'}; Name=@{ES='Limpieza rápida';EN='Quick cleanup'}; Btn=@{ES='Limpiar';EN='Clean'}
       Desc=@{ES='Borra tu %TEMP% y C:\Windows\Temp. Seguro y diario; libera espacio al momento.'
              EN='Deletes your %TEMP% and C:\Windows\Temp. Safe for daily use; frees space right away.'}
       Run={ Invoke-TempClean $false } }
    @{ Id='deep';   Cat='Clean'; Grp=@{ES='Archivos y caché';EN='Files & cache'}; Name=@{ES='Limpieza profunda';EN='Deep cleanup'}; Btn=@{ES='Limpiar todo';EN='Clean all'}
       Desc=@{ES='Rápida + Prefetch + logs CBS + informes de errores (WER) + caché de Windows Update.'
              EN='Quick + Prefetch + CBS logs + error reports (WER) + Windows Update cache.'}
       Run={ Invoke-TempClean $true } }
    @{ Id='bin';    Cat='Clean'; Grp=@{ES='Archivos y caché';EN='Files & cache'}; Name=@{ES='Vaciar papelera';EN='Empty Recycle Bin'}; Btn=@{ES='Vaciar';EN='Empty'}
       Desc=@{ES='Elimina definitivamente los archivos de la Papelera de reciclaje.'
              EN='Permanently deletes the files in the Recycle Bin.'}
       Run={ Clear-RecycleBin -Force -EA 0; T 'Papelera vaciada.' 'Recycle Bin emptied.' } }
    @{ Id='dns';    Cat='Clean'; Grp=@{ES='Archivos y caché';EN='Files & cache'}; Name=@{ES='Vaciar caché DNS';EN='Flush DNS cache'}; Btn=@{ES='Vaciar';EN='Flush'}
       Desc=@{ES='Útil tras cambiar de red o DNS: obliga a resolver nombres de nuevo.'
              EN='Useful after changing network or DNS: forces name resolution again.'}
       Run={ Clear-DnsClientCache -EA 0; T 'Caché DNS vaciada.' 'DNS cache flushed.' } }
    @{ Id='plan';   Cat='Perf';  Grp=@{ES='Energía';EN='Power'}; Name=@{ES='Plan de energía Gaming Ultimate';EN='Gaming Ultimate power plan'}; Btn=@{ES='Activar';EN='Activate'}
       Desc=@{ES='Duplica el plan Ultimate Performance, desactiva Core Parking y pone min. CPU al 100% (enchufado).'
              EN='Duplicates Ultimate Performance, disables Core Parking and sets min. CPU at 100% (on AC).'}
       Run={ Ensure-GamingPowerPlan; T 'Plan Gaming Ultimate Performance activo (Core Parking 0%).' 'Gaming Ultimate Performance plan active (Core Parking 0%).' } }

    @{ Id='rpoint'; Cat='Profiles'; Grp=@{ES='Copia de seguridad';EN='Backup'}; Name=@{ES='Crear punto de restauración';EN='Create restore point'}; Btn=@{ES='Crear';EN='Create'}
       Desc=@{ES='Guarda en un JSON el estado actual de todos los ajustes. Se crea automáticamente antes de aplicar un perfil.'
              EN='Saves the current state of every setting to a JSON file. Created automatically before applying a profile.'}
       Run={ New-RestorePoint } }
    @{ Id='rrestore'; Cat='Profiles'; Grp=@{ES='Copia de seguridad';EN='Backup'}; Name=@{ES='Restaurar último punto';EN='Restore last point'}; Btn=@{ES='Restaurar';EN='Restore'}
       Desc=@{ES='Reaplica el último punto guardado y deshace todos los cambios hechos con OptiLite desde entonces.'
              EN='Re-applies the last saved point and reverts every change made with OptiLite since then.'}
       Run={ Restore-RestorePoint } }
    @{ Id='undo'; Cat='Profiles'; Grp=@{ES='Copia de seguridad';EN='Backup'}; Name=@{ES='Deshacer último cambio';EN='Undo last change'}; Btn=@{ES='Deshacer';EN='Undo'}
       Desc=@{ES='Revierte el último ajuste aplicado (uno por uno). La pila guarda hasta 50 cambios recientes y se conserva entre sesiones.'
              EN='Reverts the last applied setting (one at a time). The stack keeps up to 50 recent changes and persists between sessions.'}
       Run={ Undo-Last } }
    @{ Id='export'; Cat='Profiles'; Grp=@{ES='Copia de seguridad';EN='Backup'}; Name=@{ES='Exportar copia de seguridad';EN='Export backup'}; Btn=@{ES='Exportar';EN='Export'}
       Desc=@{ES='Guarda todos los estados actuales en un .json que elijas (p. ej. para llevarte tu configuración a otro PC o guardarla antes de probar).'
              EN='Saves all current states to a .json you pick (e.g. to move your setup to another PC or store it before experimenting).'}
       Run={ Export-BackupFile } }
    @{ Id='import'; Cat='Profiles'; Grp=@{ES='Copia de seguridad';EN='Backup'}; Name=@{ES='Importar copia de seguridad';EN='Import backup'}; Btn=@{ES='Importar';EN='Import'}
       Desc=@{ES='Aplica una copia .json exportada antes: solo cambia los ajustes que difieren y los registra como deshacibles.'
              EN='Applies a previously exported .json: only differing settings change, and each one is pushed onto the undo stack.'}
       Run={ Import-BackupFile } }
)

# ------------------------------ Perfiles ------------------------------------
$Presets = @(
    @{ Id='comp'; Name='COMPETITIVO'; Color='#34D399'
       Desc=@{ES='Vanguard ON, FACEIT ON, Xbox OFF, VBS OFF, Game Mode ON, DVR OFF, FSO OFF, aceleración de ratón OFF, red sin límite y sin Nagle, MPO OFF, audio gaming.'
              EN='Vanguard ON, FACEIT ON, Xbox OFF, VBS OFF, Game Mode ON, DVR OFF, FSO OFF, mouse acceleration OFF, unlimited network with Nagle off, MPO OFF, gaming audio.'}
       States=@{ vg=$true; fac=$true; xbox=$false; vbs=$false; gamemode=$true; dvr=$false; fso=$false; ptr=$false; net=$false; nagle=$false; mpo=$false; daw=$false } }
    @{ Id='aaa'; Name='JUEGOS AAA'; Color='#60A5FA'
       Desc=@{ES='Anti-cheats OFF, Xbox OFF, VBS OFF, efectos visuales al mínimo, SysMain OFF, DVR/FSO/ratón OFF, red sin límite, MPO OFF. Máximo FPS.'
              EN='Anti-cheats OFF, Xbox OFF, VBS OFF, minimal visual effects, SysMain OFF, DVR/FSO/mouse OFF, unlimited network, MPO OFF. Max FPS.'}
       States=@{ vg=$false; fac=$false; xbox=$false; vbs=$false; fx=$true; sysmain=$false; gamemode=$true; dvr=$false; fso=$false; ptr=$false; net=$false; mpo=$false; daw=$false } }
    @{ Id='cloud'; Name='CLOUD / XBOX'; Color='#A78BFA'
       Desc=@{ES='Xbox y Game Pass ON, anti-cheats OFF, VBS OFF, red sin límite para streaming, audio gaming.'
              EN='Xbox and Game Pass ON, anti-cheats OFF, VBS OFF, unlimited network for streaming, gaming audio.'}
       States=@{ vg=$false; fac=$false; xbox=$true; vbs=$false; net=$false; daw=$false } }
    @{ Id='reset'; Name='RESTAURAR WINDOWS'; Color='#F59E0B'
       Desc=@{ES='Devuelve TODOS los ajustes a valores por defecto de Windows (telemetría, efectos, servicios, DVR, ratón...). Los anti-cheats no se tocan.'
              EN='Returns ALL settings to Windows defaults (telemetry, effects, services, DVR, mouse...). Anti-cheats are untouched.'}
       States=@{ vbs=$true; fx=$false; sysmain=$true; wsearch=$true; hiber=$true; bgapps=$true; net=$true; autotcp=$true; nagle=$true; xbox=$true; gamemode=$true; dvr=$true; fso=$true; ptr=$true; mpo=$true; daw=$false; tele=$true; diag=$true; act=$true; adid=$true; sugg=$true; ink=$true; fb=$true; lang=$true } }
)
# ============================================================================
#  INTERFAZ (WPF) - estilo WinHance: sidebar + tarjetas + interruptores
# ============================================================================
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="OptiLite v1.1.0 · Optimizador de Windows 10/11"
        Height="680" Width="1000" MinHeight="620" MinWidth="880"
        WindowStartupLocation="CenterScreen"
        Background="#0B0E14" FontFamily="Segoe UI">
    <Window.Resources>
        <Style x:Key="CardStyle" TargetType="Border">
            <Setter Property="Background" Value="#12161F"/>
            <Setter Property="BorderBrush" Value="#1E2735"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="CornerRadius" Value="10"/>
            <Setter Property="Padding" Value="14,12"/>
            <Setter Property="Margin" Value="0,0,0,10"/>
        </Style>
        <Style x:Key="GrpHeader" TargetType="TextBlock">
            <Setter Property="Foreground" Value="#8FA0B8"/>
            <Setter Property="FontSize" Value="10.5"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="Margin" Value="2,2,0,8"/>
        </Style>
        <Style x:Key="ChipBorder" TargetType="Border">
            <Setter Property="Background" Value="#131926"/>
            <Setter Property="BorderBrush" Value="#253048"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="CornerRadius" Value="6"/>
            <Setter Property="Padding" Value="9,4"/>
        </Style>
        <Style x:Key="BtnStyle" TargetType="Button">
            <Setter Property="Foreground" Value="#E2E8F0"/>
            <Setter Property="Background" Value="#1C2431"/>
            <Setter Property="BorderBrush" Value="#2C3A50"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="13,6"/>
            <Setter Property="FontSize" Value="11.5"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="bdr" Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="7" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bdr" Property="Opacity" Value="0.85"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="bdr" Property="Opacity" Value="0.7"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="bdr" Property="Opacity" Value="0.4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="NavBtn" TargetType="ToggleButton">
            <Setter Property="Foreground" Value="#9AA6B8"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="FontSize" Value="12.5"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Margin" Value="10,2"/>
            <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ToggleButton">
                        <Border x:Name="nav" Background="{TemplateBinding Background}" CornerRadius="8" Padding="12,9">
                            <ContentPresenter VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="nav" Property="Background" Value="#141B27"/>
                            </Trigger>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="nav" Property="Background" Value="#182536"/>
                                <Setter Property="Foreground" Value="#7DD3FC"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="SwitchStyle" TargetType="CheckBox">
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Focusable" Value="False"/>
            <Setter Property="VerticalAlignment" Value="Center"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="CheckBox">
                        <Border x:Name="track" Width="44" Height="24" CornerRadius="12"
                                Background="#232B3A" BorderBrush="#33405A" BorderThickness="1">
                            <Ellipse x:Name="thumb" Width="16" Height="16" Fill="#94A3B8"
                                     HorizontalAlignment="Left" Margin="3,0,0,0" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="track" Property="Background" Value="#38BDF8"/>
                                <Setter TargetName="track" Property="BorderBrush" Value="#38BDF8"/>
                                <Setter TargetName="thumb" Property="Fill" Value="#FFFFFF"/>
                                <Setter TargetName="thumb" Property="HorizontalAlignment" Value="Right"/>
                                <Setter TargetName="thumb" Property="Margin" Value="0,0,3,0"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="track" Property="Opacity" Value="0.85"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="track" Property="Opacity" Value="0.35"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Grid>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="202"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>

        <!-- ================= SIDEBAR ================= -->
        <Border Grid.Column="0" Background="#0D1118" BorderBrush="#1B2333" BorderThickness="0,0,1,0">
            <DockPanel>
                <StackPanel DockPanel.Dock="Top" Margin="16,18,14,14">
                    <TextBlock Text="OPTILITE" Foreground="#38BDF8" FontSize="15" FontWeight="Bold"/>
                    <StackPanel Orientation="Horizontal" Margin="0,6,0,0">
                        <Border Width="7" Height="7" CornerRadius="4" Background="#10B981" VerticalAlignment="Center" Margin="0,0,6,0"/>
                        <TextBlock x:Name="TxtSidebarSub" Text="Optimización local · sin descargas" Foreground="#5D6B80" FontSize="10"/>
                    </StackPanel>
                </StackPanel>

                <Border DockPanel.Dock="Bottom" Background="#0F141D" BorderBrush="#1B2333" BorderThickness="0,1,0,0" Padding="12,10">
                    <StackPanel>
                        <StackPanel Orientation="Horizontal" HorizontalAlignment="Center">
                            <Border Style="{StaticResource ChipBorder}" Margin="0,0,6,0">
                                <TextBlock x:Name="TxtLiveRam" Text="RAM --" Foreground="#6EE7B7" FontSize="10.5" FontWeight="SemiBold"/>
                            </Border>
                            <Border Style="{StaticResource ChipBorder}">
                                <TextBlock x:Name="TxtLiveProc" Text="Proc --" Foreground="#93C5FD" FontSize="10.5" FontWeight="SemiBold"/>
                            </Border>
                        </StackPanel>
                        <Button x:Name="BtnRefreshAll" Content="Refrescar estados" Style="{StaticResource BtnStyle}" Margin="0,8,0,0" FontSize="10.5" Padding="0,5"/>
                        <Border x:Name="BadgePending" Visibility="Collapsed" Background="#2A1F0E" BorderBrush="#D97706" BorderThickness="1" CornerRadius="6" Padding="8,4" Margin="0,8,0,0">
                            <TextBlock x:Name="TxtPendingBadge" Text="Reinicio pendiente" Foreground="#FCD34D" FontSize="10.5" FontWeight="Bold" HorizontalAlignment="Center"/>
                        </Border>
                    </StackPanel>
                </Border>

                <StackPanel Margin="0,6,0,10">
                    <ToggleButton x:Name="NavHome" Style="{StaticResource NavBtn}" IsChecked="True">
                        <StackPanel Orientation="Horizontal">
                            <Border Width="8" Height="8" CornerRadius="4" Background="#38BDF8" VerticalAlignment="Center"/>
                            <TextBlock x:Name="NavHomeTxt" Text="Resumen" Margin="10,0,0,0" VerticalAlignment="Center"/>
                        </StackPanel>
                    </ToggleButton>
                    <ToggleButton x:Name="NavPerf" Style="{StaticResource NavBtn}">
                        <StackPanel Orientation="Horizontal">
                            <Border Width="8" Height="8" CornerRadius="4" Background="#F59E0B" VerticalAlignment="Center"/>
                            <TextBlock x:Name="NavPerfTxt" Text="Rendimiento" Margin="10,0,0,0" VerticalAlignment="Center"/>
                        </StackPanel>
                    </ToggleButton>
                    <ToggleButton x:Name="NavGames" Style="{StaticResource NavBtn}">
                        <StackPanel Orientation="Horizontal">
                            <Border Width="8" Height="8" CornerRadius="4" Background="#8B5CF6" VerticalAlignment="Center"/>
                            <TextBlock x:Name="NavGamesTxt" Text="Juegos" Margin="10,0,0,0" VerticalAlignment="Center"/>
                        </StackPanel>
                    </ToggleButton>
                    <ToggleButton x:Name="NavPriv" Style="{StaticResource NavBtn}">
                        <StackPanel Orientation="Horizontal">
                            <Border Width="8" Height="8" CornerRadius="4" Background="#10B981" VerticalAlignment="Center"/>
                            <TextBlock x:Name="NavPrivTxt" Text="Privacidad" Margin="10,0,0,0" VerticalAlignment="Center"/>
                        </StackPanel>
                    </ToggleButton>
                    <ToggleButton x:Name="NavClean" Style="{StaticResource NavBtn}">
                        <StackPanel Orientation="Horizontal">
                            <Border Width="8" Height="8" CornerRadius="4" Background="#22D3EE" VerticalAlignment="Center"/>
                            <TextBlock x:Name="NavCleanTxt" Text="Limpieza" Margin="10,0,0,0" VerticalAlignment="Center"/>
                        </StackPanel>
                    </ToggleButton>
                    <ToggleButton x:Name="NavStartup" Style="{StaticResource NavBtn}">
                        <StackPanel Orientation="Horizontal">
                            <Border Width="8" Height="8" CornerRadius="4" Background="#FB923C" VerticalAlignment="Center"/>
                            <TextBlock x:Name="NavStartupTxt" Text="Inicio" Margin="10,0,0,0" VerticalAlignment="Center"/>
                        </StackPanel>
                    </ToggleButton>
                    <ToggleButton x:Name="NavProfiles" Style="{StaticResource NavBtn}">
                        <StackPanel Orientation="Horizontal">
                            <Border Width="8" Height="8" CornerRadius="4" Background="#F472B6" VerticalAlignment="Center"/>
                            <TextBlock x:Name="NavProfilesTxt" Text="Perfiles" Margin="10,0,0,0" VerticalAlignment="Center"/>
                        </StackPanel>
                    </ToggleButton>
                </StackPanel>
            </DockPanel>
        </Border>

        <!-- ================= CONTENIDO ================= -->
        <Grid Grid.Column="1" Margin="18,14,18,12">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <Grid Grid.Row="0" Margin="0,0,0,10">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0">
                    <TextBlock x:Name="TxtSectionTitle" Text="Resumen" Foreground="#F1F5F9" FontSize="17" FontWeight="Bold"/>
                    <TextBlock x:Name="TxtSectionDesc" Text="Estado del equipo y acciones rápidas" Foreground="#7C8AA0" FontSize="11" Margin="0,2,0,0"/>
                </StackPanel>
                <ToggleButton x:Name="BtnPreview" Grid.Column="1" Style="{StaticResource NavBtn}" Margin="0,0,8,0" Padding="10,6" FontSize="11">
                    <TextBlock Text="👁 Vista previa" FontSize="11" FontWeight="SemiBold"/>
                </ToggleButton>
                <Grid Grid.Column="2" Width="215" VerticalAlignment="Center" Margin="0,0,8,0">
                    <Border Background="#12161F" BorderBrush="#243043" BorderThickness="1" CornerRadius="7">
                        <TextBox x:Name="TxtSearch" Background="Transparent" BorderThickness="0" Padding="10,6" Foreground="#E2E8F0" FontSize="11.5" VerticalContentAlignment="Center"/>
                    </Border>
                    <TextBlock x:Name="TxtSearchHint" Text="Buscar ajuste..." Foreground="#5A6A82" FontSize="11.5" Margin="12,0,0,0" VerticalAlignment="Center" HorizontalAlignment="Left" IsHitTestVisible="False"/>
                </Grid>
                <ComboBox x:Name="CmbLang" Grid.Column="3" Width="70" VerticalAlignment="Center" FontSize="11" SelectedIndex="0">
                    <ComboBoxItem Content="ES"/>
                    <ComboBoxItem Content="EN"/>
                </ComboBox>
            </Grid>

            <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Padding="0,0,4,0">
                <Grid>
                    <StackPanel x:Name="PanelHome">
                        <Border Style="{StaticResource CardStyle}">
                            <StackPanel>
                                <TextBlock x:Name="GrpSysInfo" Text="EQUIPO" Style="{StaticResource GrpHeader}"/>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="120"/>
                                        <ColumnDefinition Width="*"/>
                                    </Grid.ColumnDefinitions>
                                    <Grid.RowDefinitions>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="Auto"/>
                                    </Grid.RowDefinitions>
                                    <TextBlock x:Name="LblCpu" Grid.Row="0" Grid.Column="0" Text="Procesador" Foreground="#7C8AA0" FontSize="11.5" Margin="0,3"/>
                                    <TextBlock x:Name="TxtSysCpu" Grid.Row="0" Grid.Column="1" Text="--" Foreground="#E2E8F0" FontSize="11.5" FontWeight="SemiBold" Margin="0,3"/>
                                    <TextBlock x:Name="LblGpu" Grid.Row="1" Grid.Column="0" Text="Gráfica" Foreground="#7C8AA0" FontSize="11.5" Margin="0,3"/>
                                    <TextBlock x:Name="TxtSysGpu" Grid.Row="1" Grid.Column="1" Text="--" Foreground="#E2E8F0" FontSize="11.5" FontWeight="SemiBold" Margin="0,3"/>
                                    <TextBlock x:Name="LblRam" Grid.Row="2" Grid.Column="0" Text="Memoria" Foreground="#7C8AA0" FontSize="11.5" Margin="0,3"/>
                                    <TextBlock x:Name="TxtSysRam" Grid.Row="2" Grid.Column="1" Text="--" Foreground="#E2E8F0" FontSize="11.5" FontWeight="SemiBold" Margin="0,3"/>
                                    <TextBlock x:Name="LblOs" Grid.Row="3" Grid.Column="0" Text="Sistema" Foreground="#7C8AA0" FontSize="11.5" Margin="0,3"/>
                                    <TextBlock x:Name="TxtSysOs" Grid.Row="3" Grid.Column="1" Text="--" Foreground="#E2E8F0" FontSize="11.5" FontWeight="SemiBold" Margin="0,3"/>
                                    <TextBlock x:Name="LblDisk" Grid.Row="4" Grid.Column="0" Text="Disco C:" Foreground="#7C8AA0" FontSize="11.5" Margin="0,3"/>
                                    <TextBlock x:Name="TxtSysDisk" Grid.Row="4" Grid.Column="1" Text="--" Foreground="#E2E8F0" FontSize="11.5" FontWeight="SemiBold" Margin="0,3"/>
                                </Grid>
                            </StackPanel>
                        </Border>

                        <Border Style="{StaticResource CardStyle}">
                            <StackPanel>
                                <TextBlock x:Name="GrpDiag" Text="DIAGNÓSTICO" Style="{StaticResource GrpHeader}"/>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="120"/>
                                        <ColumnDefinition Width="*"/>
                                    </Grid.ColumnDefinitions>
                                    <Grid.RowDefinitions>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="Auto"/>
                                    </Grid.RowDefinitions>
                                    <TextBlock x:Name="LblHealth" Grid.Row="0" Grid.Column="0" Text="Salud del disco" Foreground="#7C8AA0" FontSize="11.5" Margin="0,3"/>
                                    <TextBlock x:Name="TxtDiskHealth" Grid.Row="0" Grid.Column="1" Text="--" Foreground="#E2E8F0" FontSize="11.5" FontWeight="SemiBold" Margin="0,3"/>
                                    <TextBlock x:Name="LblBattery" Grid.Row="1" Grid.Column="0" Text="Batería" Foreground="#7C8AA0" FontSize="11.5" Margin="0,3"/>
                                    <TextBlock x:Name="TxtBattery" Grid.Row="1" Grid.Column="1" Text="--" Foreground="#E2E8F0" FontSize="11.5" FontWeight="SemiBold" Margin="0,3"/>
                                    <TextBlock x:Name="LblServices" Grid.Row="2" Grid.Column="0" Text="Servicios en ejecución" Foreground="#7C8AA0" FontSize="11.5" Margin="0,3"/>
                                    <TextBlock x:Name="TxtServices" Grid.Row="2" Grid.Column="1" Text="--" Foreground="#E2E8F0" FontSize="11.5" FontWeight="SemiBold" Margin="0,3"/>
                                </Grid>
                                <TextBlock x:Name="TxtTopRam" Text="--" Foreground="#8B99AE" FontSize="11" TextTrimming="CharacterEllipsis" Margin="0,6,0,0"/>
                            </StackPanel>
                        </Border>

                        <Border Style="{StaticResource CardStyle}">
                            <StackPanel>
                                <TextBlock x:Name="GrpState" Text="ESTADO" Style="{StaticResource GrpHeader}"/>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="120"/>
                                        <ColumnDefinition Width="*"/>
                                    </Grid.ColumnDefinitions>
                                    <Grid.RowDefinitions>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="Auto"/>
                                        <RowDefinition Height="Auto"/>
                                    </Grid.RowDefinitions>
                                    <TextBlock x:Name="LblReboot" Grid.Row="0" Grid.Column="0" Text="Cambios sin reiniciar" Foreground="#7C8AA0" FontSize="11.5" Margin="0,3"/>
                                    <TextBlock x:Name="TxtSumReboot" Grid.Row="0" Grid.Column="1" Text="--" Foreground="#6EE7B7" FontSize="11.5" FontWeight="SemiBold" Margin="0,3"/>
                                    <TextBlock x:Name="LblVg" Grid.Row="1" Grid.Column="0" Text="Riot Vanguard" Foreground="#7C8AA0" FontSize="11.5" Margin="0,3"/>
                                    <TextBlock x:Name="TxtSumVg" Grid.Row="1" Grid.Column="1" Text="--" Foreground="#E2E8F0" FontSize="11.5" FontWeight="SemiBold" Margin="0,3"/>
                                    <TextBlock x:Name="LblFac" Grid.Row="2" Grid.Column="0" Text="FACEIT" Foreground="#7C8AA0" FontSize="11.5" Margin="0,3"/>
                                    <TextBlock x:Name="TxtSumFac" Grid.Row="2" Grid.Column="1" Text="--" Foreground="#E2E8F0" FontSize="11.5" FontWeight="SemiBold" Margin="0,3"/>
                                </Grid>
                            </StackPanel>
                        </Border>

                        <Border Style="{StaticResource CardStyle}">
                            <StackPanel>
                                <TextBlock x:Name="GrpQuick" Text="ACCIONES RÁPIDAS" Style="{StaticResource GrpHeader}"/>
                                <WrapPanel>
                                    <Button x:Name="BtnQuickTemp" Content="Limpiar TEMP" Style="{StaticResource BtnStyle}" Margin="0,0,8,8"/>
                                    <Button x:Name="BtnQuickDeep" Content="Limpieza profunda" Style="{StaticResource BtnStyle}" Margin="0,0,8,8"/>
                                    <Button x:Name="BtnQuickPlan" Content="Plan Ultimate" Style="{StaticResource BtnStyle}" Margin="0,0,8,8"/>
                                    <Button x:Name="BtnQuickUndo" Content="Deshacer último" Style="{StaticResource BtnStyle}" Margin="0,0,8,8"/>
                                    <Button x:Name="BtnQuickShortcut" Content="Acceso en Escritorio" Style="{StaticResource BtnStyle}" Margin="0,0,0,8"/>
                                </WrapPanel>
                            </StackPanel>
                        </Border>
                    </StackPanel>
                    <StackPanel x:Name="PanelPerf" Visibility="Collapsed"/>
                    <StackPanel x:Name="PanelGames" Visibility="Collapsed"/>
                    <StackPanel x:Name="PanelPriv" Visibility="Collapsed"/>
                    <StackPanel x:Name="PanelClean" Visibility="Collapsed"/>
                    <StackPanel x:Name="PanelStartup" Visibility="Collapsed"/>
                    <StackPanel x:Name="PanelProfiles" Visibility="Collapsed"/>
                </Grid>
            </ScrollViewer>

            <Grid Grid.Row="2" Margin="0,10,0,0">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <Border x:Name="BorderStatus" Grid.Column="0" Background="#141821" BorderBrush="#252B38" BorderThickness="1" CornerRadius="6" Padding="10,7" Margin="0,0,8,0">
                    <TextBlock x:Name="TxtStatus" Text="Listo. Los interruptores se aplican al instante; los cambios que piden reinicio se indican en esta barra." Foreground="#CBD5E1" FontSize="11" TextTrimming="CharacterEllipsis"/>
                </Border>
                <Button x:Name="BtnReboot" Grid.Column="1" Content="Reiniciar PC" Style="{StaticResource BtnStyle}" Background="#2B2112" BorderBrush="#F59E0B" Foreground="#FCD34D" Padding="14,7"/>
            </Grid>
        </Grid>
    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)
# ---------------- Referencias de controles -----------------------------------
$script:Window = $window
$script:Controls = @{}
foreach ($n in @('TxtSectionTitle','TxtSectionDesc','PanelHome','PanelPerf','PanelGames','PanelPriv','PanelClean','PanelStartup','PanelProfiles','TxtLiveRam','TxtLiveProc','BtnRefreshAll','BadgePending','TxtPendingBadge','BorderStatus','TxtStatus','BtnReboot','TxtSearch','TxtSearchHint','TxtSysCpu','TxtSysGpu','TxtSysRam','TxtSysOs','TxtSysDisk','TxtDiskHealth','TxtBattery','TxtServices','TxtTopRam','TxtSumReboot','TxtSumVg','TxtSumFac','BtnQuickTemp','BtnQuickDeep','BtnQuickPlan','BtnQuickUndo','BtnQuickShortcut','NavHome','NavPerf','NavGames','NavPriv','NavClean','NavStartup','NavProfiles','NavHomeTxt','NavPerfTxt','NavGamesTxt','NavPrivTxt','NavCleanTxt','NavStartupTxt','NavProfilesTxt','TxtSidebarSub','CmbLang','BtnPreview','GrpSysInfo','GrpDiag','GrpState','GrpQuick','LblCpu','LblGpu','LblRam','LblOs','LblDisk','LblHealth','LblBattery','LblServices','LblReboot','LblVg','LblFac')) {
    $script:Controls[$n] = $window.FindName($n)
}

$script:BrushCache = @{}
function Get-Br([string]$hex) {
    if (-not $script:BrushCache.ContainsKey($hex)) {
        $conv = New-Object System.Windows.Media.BrushConverter
        $script:BrushCache[$hex] = $conv.ConvertFromString($hex)
    }
    return $script:BrushCache[$hex]
}

function Update-UiNow {
    try { [void]$script:Window.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Background, [Action]{}) } catch {}
}

function Remove-Accents([string]$s) {
    $norm = $s.Normalize([System.Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $norm.ToCharArray()) {
        $cat = [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch)
        if ($cat -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($ch) }
    }
    return $sb.ToString()
}

# ---------------- Construcción de tarjetas -----------------------------------
$script:ItemMap = @{}
foreach ($it in $Items) { $script:ItemMap[$it.Id] = $it }
$script:ItemControls = @{}
$script:AllCards = @()
$script:AllGroups = @{}
$script:StartupCards = @()

$script:CatPanels   = @{ 'Perf' = 'PanelPerf'; 'Games' = 'PanelGames'; 'Priv' = 'PanelPriv'; 'Clean' = 'PanelClean'; 'Profiles' = 'PanelProfiles' }
$script:PanelWords  = @{
    'PanelPerf'     = 'rendimiento cpu energia red efectos servicios performance power network'
    'PanelGames'    = 'juegos gaming anti-cheat fps latencia games'
    'PanelPriv'     = 'privacidad telemetria anuncios datos privacy telemetry ads'
    'PanelClean'    = 'limpieza disco cache temporales cleanup disk temp'
    'PanelStartup'  = 'inicio arranque programas autostart boot startup programs'
    'PanelProfiles' = 'perfil preset rapido restauracion backup deshacer undo copia exportar importar profile'
}

function New-Text([string]$text, [string]$hex, [double]$size, [string]$weight = 'SemiBold', [bool]$wrap = $false) {
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = $text
    $t.Foreground = Get-Br $hex
    $t.FontSize = $size
    switch ($weight) {
        'SemiBold' { $t.FontWeight = [System.Windows.FontWeights]::SemiBold }
        'Bold'     { $t.FontWeight = [System.Windows.FontWeights]::Bold }
        default    { $t.FontWeight = [System.Windows.FontWeights]::Normal }
    }
    if ($wrap) { $t.TextWrapping = [System.Windows.TextWrapping]::Wrap }
    return $t
}

function Add-GroupHeader([string]$panel, [string]$grp) {
    $key = "$panel|$grp"
    if ($script:AllGroups.ContainsKey($key)) { return $script:AllGroups[$key] }
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = $grp.ToUpper()
    $tb.Style = $script:Window.TryFindResource('GrpHeader')
    [void]$script:Controls[$panel].Children.Add($tb)
    $g = @{ Header = $tb; Cards = @() }
    $script:AllGroups[$key] = $g
    return $g
}

function Register-Card([string]$panel, $grp, $card, [string]$searchText) {
    $g = Add-GroupHeader $panel $grp
    $g.Cards += @{ El = $card }
    $words = "$panel $($script:PanelWords[$panel])"
    $script:AllCards += @{ Panel = $panel; El = $card; Text = (Remove-Accents "$searchText $words").ToLower() }
}

function Get-WhatIfText($it, [bool]$target) {
    $name = L $it.Name
    $on = (T 'activado' 'enabled'); $off = (T 'desactivado' 'disabled')
    $cur = & $it.Get
    $curTxt = if ($null -eq $cur) { (T 'no instalado' 'not installed') } elseif ($cur) { $on } else { $off }
    $tgtTxt = if ($target) { $on } else { $off }
    $reboot = if ($it.Reboot) { (T ' · pide reinicio' ' · reboot required') } else { '' }
    return (T "[VISTA PREVIA] $name : $curTxt -> $tgtTxt$reboot (no se ha aplicado nada).`nDesactiva 'Vista previa' y repite el clic para aplicar." "[PREVIEW] $name : $curTxt -> $tgtTxt$reboot (nothing has been applied).`nTurn 'Preview' off and click again to apply.")
}

function Add-ToggleCard([string]$panel, $item) {
    $card = New-Object System.Windows.Controls.Border
    $card.Style = $script:Window.TryFindResource('CardStyle')
    $dock = New-Object System.Windows.Controls.DockPanel

    $chk = New-Object System.Windows.Controls.CheckBox
    $chk.Style = $script:Window.TryFindResource('SwitchStyle')
    $chk.Tag = $item
    $chk.Margin = New-Object System.Windows.Thickness(14, 0, 0, 0)
    [System.Windows.Controls.DockPanel]::SetDock($chk, [System.Windows.Controls.Dock]::Right)
    [void]$dock.Children.Add($chk)

    $txt = New-Object System.Windows.Controls.StackPanel
    $txt.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    $nameTb = New-Text (L $item.Name) '#F1F5F9' 13 'SemiBold'
    [void]$txt.Children.Add($nameTb)
    $desc = New-Text (L $item.Desc) '#8B99AE' 11 'Normal' $true
    $desc.Margin = New-Object System.Windows.Thickness(0, 2, 0, 0)
    [void]$txt.Children.Add($desc)
    if ($item.Reboot) {
        $tag = New-Text (T 'PIDE REINICIO' 'REBOOT REQUIRED') '#D97706' 9 'Bold'
        $tag.Margin = New-Object System.Windows.Thickness(0, 4, 0, 0)
        [void]$txt.Children.Add($tag)
    }
    [void]$dock.Children.Add($txt)
    $card.Child = $dock

    Register-Card $panel (L $item.Grp) $card "$((L $item.Name)) $((L $item.Desc)) $((L $item.Grp))"
    [void]$script:Controls[$panel].Children.Add($card)
    $script:ItemControls[$item.Id] = $chk

    $chk.Add_Click({
        param($sender, $e)
        $it = $sender.Tag
        $target = [bool]$sender.IsChecked
        if ($script:Preview) {
            Set-Status (Get-WhatIfText $it $target)
            return
        }
        $cur = & $it.Get
        if ($cur -eq $target) {
            Set-Status "$((L $it.Name)): $(T 'ya estaba en ese estado.' 'already in that state.')"
            return
        }
        & $it.Set $target
        Push-Undo $it.Id $cur $target
        if ($it.Reboot) { $script:PendingReboot = $true }
        Write-TempLog "Ajuste '$($it.Id)' -> $target."
        Refresh-AllStates
        $word = if ($target) { (T 'activado' 'enabled') } else { (T 'desactivado' 'disabled') }
        $extra = if ($it.Reboot) { (T ' (reinicia para aplicar)' ' (reboot to apply)') } else { '' }
        Set-Status "$((L $it.Name)) $word$extra. $(T 'Puedes deshacerlo con "Deshacer último".' 'You can undo it with "Undo last change".')"
    })
}

function Add-ActionCard([string]$panel, $act) {
    $card = New-Object System.Windows.Controls.Border
    $card.Style = $script:Window.TryFindResource('CardStyle')
    $dock = New-Object System.Windows.Controls.DockPanel

    $btn = New-Object System.Windows.Controls.Button
    $btn.Style = $script:Window.TryFindResource('BtnStyle')
    $btn.Content = L $act.Btn
    $btn.Tag = $act
    $btn.Margin = New-Object System.Windows.Thickness(14, 0, 0, 0)
    $btn.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    [System.Windows.Controls.DockPanel]::SetDock($btn, [System.Windows.Controls.Dock]::Right)
    [void]$dock.Children.Add($btn)

    $txt = New-Object System.Windows.Controls.StackPanel
    $txt.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    [void]$txt.Children.Add((New-Text (L $act.Name) '#F1F5F9' 13 'SemiBold'))
    $desc = New-Text (L $act.Desc) '#8B99AE' 11 'Normal' $true
    $desc.Margin = New-Object System.Windows.Thickness(0, 2, 0, 0)
    [void]$txt.Children.Add($desc)
    [void]$dock.Children.Add($txt)
    $card.Child = $dock

    Register-Card $panel (L $act.Grp) $card "$((L $act.Name)) $((L $act.Desc))"
    [void]$script:Controls[$panel].Children.Add($card)

    $btn.Add_Click({
        param($sender, $e)
        $act = $sender.Tag
        Set-Status "$(T 'Ejecutando' 'Running'): $((L $act.Name))..."
        Update-UiNow
        $res = & $act.Run
        Write-TempLog "Accion '$($act.Id)' ejecutada."
        Refresh-AllStates
        Refresh-LiveStats
        if ($res -is [ValueType]) {
            $tpl = T 'completada (~{0} MB liberados).' 'completed (~{0} MB freed).'
            Set-Status "$((L $act.Name)) $($tpl -f $res)"
        }
        elseif ($res) { Set-Status "$((L $act.Name)): $res" }
        else { Set-Status "$((L $act.Name)) $(T 'completada.' 'completed.')" }
    })
}

function Add-PresetCard($preset) {
    $card = New-Object System.Windows.Controls.Border
    $card.Style = $script:Window.TryFindResource('CardStyle')
    $dock = New-Object System.Windows.Controls.DockPanel

    $bar = New-Object System.Windows.Controls.Border
    $bar.Width = 4
    $bar.CornerRadius = New-Object System.Windows.CornerRadius(2)
    $bar.Background = Get-Br $preset.Color
    $bar.Margin = New-Object System.Windows.Thickness(0, 0, 12, 0)
    [System.Windows.Controls.DockPanel]::SetDock($bar, [System.Windows.Controls.Dock]::Left)
    [void]$dock.Children.Add($bar)

    $btn = New-Object System.Windows.Controls.Button
    $btn.Style = $script:Window.TryFindResource('BtnStyle')
    $btn.Content = T 'Aplicar perfil' 'Apply profile'
    $btn.Tag = $preset
    $btn.Margin = New-Object System.Windows.Thickness(14, 0, 0, 0)
    $btn.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    [System.Windows.Controls.DockPanel]::SetDock($btn, [System.Windows.Controls.Dock]::Right)
    [void]$dock.Children.Add($btn)

    $txt = New-Object System.Windows.Controls.StackPanel
    $txt.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    [void]$txt.Children.Add((New-Text $preset.Name $preset.Color 13.5 'Bold'))
    $desc = New-Text (L $preset.Desc) '#8B99AE' 11 'Normal' $true
    $desc.Margin = New-Object System.Windows.Thickness(0, 3, 0, 0)
    [void]$txt.Children.Add($desc)
    [void]$dock.Children.Add($txt)
    $card.Child = $dock

    Register-Card 'PanelProfiles' (T 'Perfiles de un clic' 'One-click profiles') $card "$($preset.Name) $((L $preset.Desc))"
    [void]$script:Controls['PanelProfiles'].Children.Add($card)

    $btn.Add_Click({
        param($sender, $e)
        $p = $sender.Tag
        if ($script:Preview) {
            $lines = @()
            foreach ($id in $p.States.Keys) {
                $it = $script:ItemMap[$id]
                if (-not $it) { continue }
                $cur = & $it.Get
                if ($null -ne $cur -and $cur -ne $p.States[$id]) {
                    $on = (T 'activado' 'enabled'); $off = (T 'desactivado' 'disabled')
                    $curTxt = if ($cur) { $on } else { $off }
                    $tgtTxt = if ($p.States[$id]) { $on } else { $off }
                    $lines += "$(L $it.Name): $curTxt -> $tgtTxt"
                }
            }
            if ($lines.Count -eq 0) {
                Set-Status "[PREVIEW] $($p.Name): $(T 'ya está aplicado; no hay nada que cambiar.' 'already applied; nothing to change.')"
            } else {
                $msg = "[VISTA PREVIA] $($p.Name) $(T 'cambiaría' 'would change') $($lines.Count) $(T 'ajustes (no se ha aplicado nada):' 'settings (nothing applied):') " + ($lines -join ' · ')
                Set-Status $msg
            }
            return
        }
        Set-Status "$(T 'Aplicando perfil' 'Applying profile') $($p.Name)..."
        Update-UiNow
        $null = New-RestorePoint
        $changed = 0
        $reboot = $false
        foreach ($id in $p.States.Keys) {
            $it = $script:ItemMap[$id]
            if (-not $it) { continue }
            $want = $p.States[$id]
            $cur = & $it.Get
            if ($cur -ne $want) {
                & $it.Set $want
                Push-Undo $it.Id $cur $want
                $changed++
                if ($it.Reboot) { $reboot = $true }
            }
        }
        if ($reboot) { $script:PendingReboot = $true }
        Write-TempLog "Perfil '$($p.Name)' aplicado ($changed ajustes)."
        Refresh-AllStates
        $tpl = T 'aplicado: {0} ajustes (punto de restauración actualizado).' 'applied: {0} settings (restore point updated).'
        $msg = "$(T 'Perfil' 'Profile') $($p.Name) $($tpl -f $changed)"
        if ($reboot) { $msg = $msg + (T ' Reinicia para aplicar los cambios de kernel/energía.' ' Reboot to apply the kernel/power changes.') }
        Set-Status $msg
    })
}

# ---------------- Panel Inicio (v1.1) ----------------------------------------
function Get-StartupPreview($entries) {
    $enabled = @($entries | Where-Object { -not $_.Disabled })
    $disabled = @($entries | Where-Object { $_.Disabled })
    $lines = @()
    foreach ($en in $enabled) { $lines += "$(T 'DESACTIVAR' 'DISABLE') : $($en.Name) ($($en.Loc))" }
    foreach ($en in $disabled) { $lines += "$(T 'REACTIVAR' 'RE-ENABLE') : $($en.Name) ($($en.Loc))" }
    return $lines
}

function Add-StartupCard($entry) {
    $card = New-Object System.Windows.Controls.Border
    $card.Style = $script:Window.TryFindResource('CardStyle')
    $dock = New-Object System.Windows.Controls.DockPanel

    $chk = New-Object System.Windows.Controls.CheckBox
    $chk.Style = $script:Window.TryFindResource('SwitchStyle')
    $chk.Tag = $entry
    $chk.IsChecked = (-not $entry.Disabled)
    $chk.Margin = New-Object System.Windows.Thickness(14, 0, 0, 0)
    [System.Windows.Controls.DockPanel]::SetDock($chk, [System.Windows.Controls.Dock]::Right)
    [void]$dock.Children.Add($chk)

    $txt = New-Object System.Windows.Controls.StackPanel
    $txt.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    [void]$txt.Children.Add((New-Text $entry.Name '#F1F5F9' 13 'SemiBold'))
    $cmd = $entry.Cmd
    if ($cmd.Length -gt 90) { $cmd = $cmd.Substring(0, 90) + '...' }
    $loc = if ($entry.Loc -eq 'Folder') { (T 'Carpeta Inicio' 'Startup folder') } else { $entry.Loc }
    $desc = New-Text "$loc · $cmd" '#8B99AE' 10.5 'Normal' $true
    $desc.Margin = New-Object System.Windows.Thickness(0, 2, 0, 0)
    [void]$txt.Children.Add($desc)
    [void]$dock.Children.Add($txt)
    $card.Child = $dock

    Register-Card 'PanelStartup' (T 'Programas que arrancan con Windows' 'Programs that start with Windows') $card "$($entry.Name) $($entry.Cmd) $($entry.Loc)"
    [void]$script:Controls['PanelStartup'].Children.Add($card)
    $script:StartupCards += @{ El = $card; Chk = $chk }

    $chk.Add_Click({
        param($sender, $e)
        $entry = $sender.Tag
        $on = [bool]$sender.IsChecked
        if ($script:Preview) {
            $act = if ($on) { (T 'REACTIVAR' 'RE-ENABLE') } else { (T 'DESACTIVAR' 'DISABLE') }
            Set-Status "[VISTA PREVIA] $act : $($entry.Name) ($($entry.Loc)) $(T '(no se ha aplicado nada).' '(nothing applied).')"
            return
        }
        $res = Set-StartupEnabled $entry $on
        if ($res -ne 'OK') {
            Set-Status $res
            Refresh-StartupPanel
            return
        }
        Write-TempLog "Inicio '$($entry.Name)' ($($entry.Loc)) -> $on."
        Refresh-StartupPanel
        $word = if ($on) { (T 'reactivado' 're-enabled') } else { (T 'desactivado' 'disabled') }
        Set-Status "$($entry.Name) $word. $(T 'El respaldo permite recuperarlo desde este mismo interruptor.' 'The backup lets you recover it from this same switch.')"
    })
}

function Refresh-StartupPanel {
    foreach ($sc in $script:StartupCards) { $sc.El.Visibility = 'Collapsed' }
    $script:Controls['PanelStartup'].Children.Clear()
    $script:StartupCards = @()
    $entries = Get-StartupEntries
    if ($entries.Count -eq 0) {
        $tb = New-Text (T 'No se encontraron programas de inicio.' 'No startup programs found.') '#8B99AE' 11.5 'Normal' $true
        [void]$script:Controls['PanelStartup'].Children.Add($tb)
        return
    }
    foreach ($en in $entries) { Add-StartupCard $en }
    Invoke-SearchFilter $script:Controls['TxtSearch'].Text.Trim().ToLower()
}

function Build-Panels {
    foreach ($it  in $Items)  { $p = $script:CatPanels[$it.Cat];   if ($p) { Add-ToggleCard $p $it } }
    foreach ($act in $Actions) { $p = $script:CatPanels[$act.Cat]; if ($p) { Add-ActionCard $p $act } }
    foreach ($preset in $Presets) { Add-PresetCard $preset }
    Refresh-StartupPanel
}

# ---------------- Navegación y búsqueda --------------------------------------
$script:NavMap = @(
    @{ Btn='NavHome';     Panel='PanelHome';     Title=@{ES='Resumen';EN='Summary'};     Desc=@{ES='Estado del equipo y acciones rápidas';EN='System status and quick actions'} }
    @{ Btn='NavPerf';     Panel='PanelPerf';     Title=@{ES='Rendimiento';EN='Performance'}; Desc=@{ES='CPU, memoria, efectos visuales, servicios y red';EN='CPU, memory, visual effects, services and network'} }
    @{ Btn='NavGames';    Panel='PanelGames';    Title=@{ES='Juegos';EN='Gaming'};      Desc=@{ES='Anti-cheats, Xbox, captura, latencia y audio';EN='Anti-cheats, Xbox, capture, latency and audio'} }
    @{ Btn='NavPriv';     Panel='PanelPriv';     Title=@{ES='Privacidad';EN='Privacy'};  Desc=@{ES='Telemetría, historial, anuncios y datos personales';EN='Telemetry, history, ads and personal data'} }
    @{ Btn='NavClean';    Panel='PanelClean';    Title=@{ES='Limpieza';EN='Cleanup'};    Desc=@{ES='Archivos temporales, caché y mantenimiento';EN='Temp files, cache and maintenance'} }
    @{ Btn='NavStartup';  Panel='PanelStartup'; Title=@{ES='Inicio';EN='Startup'};     Desc=@{ES='Programas que arrancan con Windows';EN='Programs that start with Windows'} }
    @{ Btn='NavProfiles'; Panel='PanelProfiles'; Title=@{ES='Perfiles';EN='Profiles'};  Desc=@{ES='Perfiles de un clic, deshacer y copia de seguridad';EN='One-click profiles, undo and backups'} }
)

function Show-Panel([string]$btnName) {
    foreach ($n in $script:NavMap) {
        $active = ($n.Btn -eq $btnName)
        $script:Controls[$n.Btn].IsChecked = $active
        if ($active) {
            $script:Controls[$n.Panel].Visibility = 'Visible'
            $script:Controls['TxtSectionTitle'].Text = L $n.Title
            $script:Controls['TxtSectionDesc'].Text = L $n.Desc
        } else {
            $script:Controls[$n.Panel].Visibility = 'Collapsed'
        }
    }
    Invoke-SearchFilter $script:Controls['TxtSearch'].Text.Trim().ToLower()
}

function Invoke-SearchFilter([string]$q) {
    $q = (Remove-Accents $q).ToLower()
    foreach ($c in $script:AllCards) {
        $match = [string]::IsNullOrEmpty($q) -or $c.Text.Contains($q)
        $c.El.Visibility = if ($match) { 'Visible' } else { 'Collapsed' }
    }
    foreach ($g in $script:AllGroups.Values) {
        $any = $false
        foreach ($c in $g.Cards) { if ($c.El.Visibility -eq 'Visible') { $any = $true; break } }
        $g.Header.Visibility = if ($any) { 'Visible' } else { 'Collapsed' }
    }
}

# ---------------- Estado y refresco ------------------------------------------
function Refresh-LiveStats {
    $os = Get-CimInstance Win32_OperatingSystem -EA 0
    if ($os) {
        $usedGB = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB, 1)
        $totGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
        $script:Controls['TxtLiveRam'].Text = "RAM $usedGB / $totGB GB"
    }
    $script:Controls['TxtLiveProc'].Text = "$(T 'Proc' 'Proc') $((Get-Process -EA 0).Count)"
}

function Update-Summary {
    if ($script:PendingReboot) {
        $script:Controls['TxtSumReboot'].Text = T 'Sí - reinicia para aplicar los cambios' 'Yes - reboot to apply the changes'
        $script:Controls['TxtSumReboot'].Foreground = Get-Br '#FCD34D'
        $script:Controls['BadgePending'].Visibility = 'Visible'
    } else {
        $script:Controls['TxtSumReboot'].Text = T 'Ninguno' 'None'
        $script:Controls['TxtSumReboot'].Foreground = Get-Br '#6EE7B7'
        $script:Controls['BadgePending'].Visibility = 'Collapsed'
    }
    foreach ($pair in @( @('vg','TxtSumVg'), @('fac','TxtSumFac') )) {
        $it = $script:ItemMap[$pair[0]]
        $cur = & $it.Get
        $tb = $script:Controls[$pair[1]]
        if ($null -eq $cur)      { $tb.Text = (T 'No instalado' 'Not installed'); $tb.Foreground = Get-Br '#8B99AE' }
        elseif ($cur)            { $tb.Text = (T 'Activado' 'Enabled');     $tb.Foreground = Get-Br '#6EE7B7' }
        else                     { $tb.Text = (T 'Desactivado' 'Disabled');  $tb.Foreground = Get-Br '#F87171' }
    }
}

function Refresh-AllStates {
    foreach ($it in $script:Items) {
        $chk = $script:ItemControls[$it.Id]
        if (-not $chk) { continue }
        $cur = & $it.Get
        if ($null -eq $cur) { $chk.IsEnabled = $false; $chk.IsChecked = $false }
        else { $chk.IsEnabled = $true; $chk.IsChecked = [bool]$cur }
    }
    Update-Summary
}

function Set-Status([string]$msg) {
    if ($script:PendingReboot) {
        $script:Controls['BorderStatus'].Background = Get-Br '#291F11'
        $script:Controls['BorderStatus'].BorderBrush = Get-Br '#D97706'
        $script:Controls['TxtStatus'].Foreground = Get-Br '#FDE68A'
        $script:Controls['TxtStatus'].Text = "$msg  [$(T 'REINICIO PENDIENTE' 'PENDING REBOOT')]"
    } else {
        $script:Controls['BorderStatus'].Background = Get-Br '#141821'
        $script:Controls['BorderStatus'].BorderBrush = Get-Br '#252B38'
        $script:Controls['TxtStatus'].Foreground = Get-Br '#CBD5E1'
        $script:Controls['TxtStatus'].Text = $msg
    }
}

function Initialize-SysInfo {
    $cpu = (Get-CimInstance Win32_Processor -EA 0 | Select-Object -First 1).Name
    if ($cpu) { $script:Controls['TxtSysCpu'].Text = ($cpu -replace '\s+', ' ').Trim() }
    $gpus = (Get-CimInstance Win32_VideoController -EA 0 | ForEach-Object { $_.Name }) -join ' + '
    if ($gpus) { $script:Controls['TxtSysGpu'].Text = $gpus }
    $cs = Get-CimInstance Win32_ComputerSystem -EA 0
    if ($cs) { $script:Controls['TxtSysRam'].Text = "$([math]::Round($cs.TotalPhysicalMemory / 1GB, 1)) GB" }
    $osC = Get-CimInstance Win32_OperatingSystem -EA 0
    if ($osC) {
        $dv = Get-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' 'DisplayVersion'
        $script:Controls['TxtSysOs'].Text = if ($dv) { "$($osC.Caption) - $dv" } else { $osC.Caption }
    }
    $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" -EA 0
    if ($disk) {
        $freeGB = [math]::Round($disk.FreeSpace / 1GB, 1)
        $totGB = [math]::Round($disk.Size / 1GB, 1)
        $script:Controls['TxtSysDisk'].Text = (T "$freeGB GB libres de $totGB GB" "$freeGB GB free of $totGB GB")
    }
}

function Initialize-Diagnostics {
    # Salud del disco (SMART via MSStorageDriver o predicción de fallos)
    $health = $null
    try {
        $phys = Get-CimInstance -Namespace 'root\wmi' -ClassName MSStorageDriver_FailurePredictStatus -EA 0
        if ($phys) {
            $ok = @($phys | Where-Object { $_.PredictFailure -eq $false }).Count
            $bad = @($phys | Where-Object { $_.PredictFailure -eq $true }).Count
            if ($bad -gt 0) { $health = T 'Atención: SMART predice fallo' 'Warning: SMART predicts failure' }
            else { $health = T "Correcto ($ok discos consultados)" "OK ($ok drives queried)" }
        }
    } catch {}
    if (-not $health) { $health = T 'No disponible (sin datos SMART)' 'Unavailable (no SMART data)' }
    $script:Controls['TxtDiskHealth'].Text = $health
    if ($health -like '*Atención*' -or $health -like '*Warning*') { $script:Controls['TxtDiskHealth'].Foreground = Get-Br '#F87171' }
    else { $script:Controls['TxtDiskHealth'].Foreground = Get-Br '#E2E8F0' }

    # Batería (solo en equipos portátiles)
    $bat = $null
    try {
        $batStats = Get-CimInstance -Namespace 'root\wmi' -ClassName BatteryStatus -EA 0
        if (-not $batStats) { $batStats = Get-CimInstance Win32_Battery -EA 0 }
        if ($batStats) {
            $est = Get-CimInstance -Namespace 'root\wmi' -ClassName BatteryStaticData -EA 0
            $pct = $null
            if ($est) {
                $full = $est.DesignedCapacity
                if ($full -gt 0) {
                    $now = (Get-CimInstance -Namespace 'root\wmi' -ClassName BatteryFullChargedCapacity -EA 0).FullChargedCapacity
                    if ($now) { $pct = [math]::Round(100 * $now / $full, 0) }
                }
            }
            if (-not $pct) { $pct = (Get-CimInstance Win32_Battery -EA 0).EstimatedChargeRemaining }
            if ($pct) { $bat = T "Salud ~$pct% de la capacidad de fábrica" "Health ~$pct% of design capacity" }
        }
    } catch {}
    if (-not $bat) { $bat = T 'No hay batería (equipo de escritorio)' 'No battery (desktop system)' }
    $script:Controls['TxtBattery'].Text = $bat

    # Servicios en ejecución
    $runSvc = (Get-Service -EA 0 | Where-Object { $_.Status -eq 'Running' }).Count
    if (-not $runSvc) { $runSvc = 0 }
    $script:Controls['TxtServices'].Text = "$runSvc $(T 'servicios activos' 'services running')"

    # Top 5 procesos por RAM
    $top = Get-Process -EA 0 | Sort-Object WorkingSet64 -Descending | Select-Object -First 5
    if ($top) {
        $parts = @()
        foreach ($p in $top) { $parts += "$($p.Name) ($([math]::Round($p.WorkingSet64 / 1MB, 0)) MB)" }
        $script:Controls['TxtTopRam'].Text = "$(T 'Top RAM' 'Top RAM'): " + ($parts -join ' · ')
    }
}

# ---------------- Idioma: aplicar en vivo ------------------------------------
function Save-LanguageCfg([string]$lang) {
    try {
        @{ Lang = $lang } | ConvertTo-Json | Set-Content -Path $script:CfgPath -Encoding UTF8
    } catch {
        Write-TempLog "No se pudo guardar el idioma: $($_.Exception.Message)"
    }
}

function Apply-Language([string]$lang) {
    $script:Lang = $lang
    Save-LanguageCfg $lang

    # Controles con texto fijo
    $script:Controls['TxtSidebarSub'].Text = T 'Optimización local · sin descargas' 'Local optimization · no downloads'
    $script:Controls['TxtPendingBadge'].Text = T 'Reinicio pendiente' 'Pending reboot'
    $script:Controls['BtnRefreshAll'].Content = T 'Refrescar estados' 'Refresh states'
    $script:Controls['NavHomeTxt'].Text = T 'Resumen' 'Summary'
    $script:Controls['NavPerfTxt'].Text = T 'Rendimiento' 'Performance'
    $script:Controls['NavGamesTxt'].Text = T 'Juegos' 'Gaming'
    $script:Controls['NavPrivTxt'].Text = T 'Privacidad' 'Privacy'
    $script:Controls['NavCleanTxt'].Text = T 'Limpieza' 'Cleanup'
    $script:Controls['NavStartupTxt'].Text = T 'Inicio' 'Startup'
    $script:Controls['NavProfilesTxt'].Text = T 'Perfiles' 'Profiles'
    $script:Controls['GrpSysInfo'].Text = T 'EQUIPO' 'SYSTEM'
    $script:Controls['GrpDiag'].Text = T 'DIAGNÓSTICO' 'DIAGNOSTICS'
    $script:Controls['GrpState'].Text = T 'ESTADO' 'STATUS'
    $script:Controls['GrpQuick'].Text = T 'ACCIONES RÁPIDAS' 'QUICK ACTIONS'
    $script:Controls['LblCpu'].Text = T 'Procesador' 'Processor'
    $script:Controls['LblGpu'].Text = T 'Gráfica' 'Graphics'
    $script:Controls['LblRam'].Text = T 'Memoria' 'Memory'
    $script:Controls['LblOs'].Text = T 'Sistema' 'OS'
    $script:Controls['LblDisk'].Text = T 'Disco C:' 'Disk C:'
    $script:Controls['LblHealth'].Text = T 'Salud del disco' 'Disk health'
    $script:Controls['LblBattery'].Text = T 'Batería' 'Battery'
    $script:Controls['LblServices'].Text = T 'Servicios en ejecución' 'Services running'
    $script:Controls['LblReboot'].Text = T 'Cambios sin reiniciar' 'Pending reboots'
    $script:Controls['LblVg'].Text = T 'Riot Vanguard' 'Riot Vanguard'
    $script:Controls['LblFac'].Text = T 'FACEIT' 'FACEIT'
    $script:Controls['TxtSearchHint'].Text = T 'Buscar ajuste...' 'Search setting...'
    $script:Controls['BtnReboot'].Content = T 'Reiniciar PC' 'Restart PC'
    $script:Controls['BtnQuickTemp'].Content = T 'Limpiar TEMP' 'Clean TEMP'
    $script:Controls['BtnQuickDeep'].Content = T 'Limpieza profunda' 'Deep cleanup'
    $script:Controls['BtnQuickPlan'].Content = T 'Plan Ultimate' 'Ultimate plan'
    $script:Controls['BtnQuickUndo'].Content = T 'Deshacer último' 'Undo last'
    $script:Controls['BtnQuickShortcut'].Content = T 'Acceso en Escritorio' 'Desktop shortcut'
    $script:Window.Title = T 'OptiLite v1.1.0 · Optimizador de Windows 10/11' 'OptiLite v1.1.0 · Windows 10/11 optimizer'

    # Reconstruir paneles con textos del nuevo idioma
    foreach ($p in @('PanelPerf','PanelGames','PanelPriv','PanelClean','PanelProfiles','PanelStartup')) {
        $script:Controls[$p].Children.Clear()
    }
    $script:AllCards = @()
    $script:AllGroups = @{}
    $script:StartupCards = @()
    Build-Panels

    Show-Panel 'NavHome'
    Refresh-AllStates
    Set-Status (T 'Idioma cambiado a español. La preferencia queda guardada en optilite.json.' 'Language switched to English. The preference is stored in optilite.json.')
}

# ---------------- Manejadores de eventos -------------------------------------
foreach ($n in $script:NavMap) {
    $script:Controls[$n.Btn].Add_Click({ param($sender, $e) Show-Panel $sender.Name })
}

$script:Controls['BtnRefreshAll'].Add_Click({
    param($sender, $e)
    Refresh-AllStates
    Refresh-LiveStats
    Refresh-StartupPanel
    Set-Status (T 'Estados actualizados.' 'States refreshed.')
})

$script:Controls['BtnReboot'].Add_Click({
    param($sender, $e)
    $ans = [System.Windows.MessageBox]::Show((T '¿Reiniciar la PC ahora para aplicar los cambios pendientes?' 'Restart the PC now to apply pending changes?'), (T 'OptiLite - Reiniciar PC' 'OptiLite - Restart PC'), 'YesNo', 'Question')
    if ($ans -eq 'Yes') {
        Write-TempLog 'Reinicio iniciado desde OptiLite.'
        Restart-Computer -Force
    }
})

$script:Controls['TxtSearch'].Add_TextChanged({
    param($sender, $e)
    $script:Controls['TxtSearchHint'].Visibility = if ([string]::IsNullOrEmpty($sender.Text)) { 'Visible' } else { 'Collapsed' }
    Invoke-SearchFilter $sender.Text.Trim().ToLower()
})

$script:Controls['BtnPreview'].Add_Click({
    param($sender, $e)
    $script:Preview = [bool]$sender.IsChecked
    if ($script:Preview) {
        Set-Status (T 'Vista previa ACTIVADA: los clics muestran qué cambiarían sin aplicar nada.' 'Preview ON: clicks show what would change without applying anything.')
    } else {
        Set-Status (T 'Vista previa desactivada: los clics vuelven a aplicar cambios reales.' 'Preview off: clicks apply real changes again.')
    }
})

$script:Controls['CmbLang'].Add_SelectionChanged({
    param($sender, $e)
    if ($script:LangLoading) { return }
    $sel = $sender.SelectedItem
    if (-not $sel) { return }
    $txt = $sel.Content
    if ($txt -ne $script:Lang) { Apply-Language $txt }
})

$script:Controls['BtnQuickTemp'].Add_Click({
    param($sender, $e)
    Set-Status (T 'Limpiando temporales...' 'Cleaning temp files...')
    Update-UiNow
    $freed = Invoke-TempClean $false
    Refresh-LiveStats
    Set-Status (T "Limpieza rápida completada (~$freed MB liberados)." "Quick cleanup done (~$freed MB freed).")
})

$script:Controls['BtnQuickDeep'].Add_Click({
    param($sender, $e)
    Set-Status (T 'Ejecutando limpieza profunda (puede tardar un poco)...' 'Running deep cleanup (may take a while)...')
    Update-UiNow
    $freed = Invoke-TempClean $true
    Refresh-LiveStats
    Set-Status (T "Limpieza profunda completada (~$freed MB liberados)." "Deep cleanup done (~$freed MB freed).")
})

$script:Controls['BtnQuickPlan'].Add_Click({
    param($sender, $e)
    Set-Status (T 'Activando plan de energía Gaming Ultimate...' 'Activating Gaming Ultimate power plan...')
    Update-UiNow
    Ensure-GamingPowerPlan
    Set-Status (T 'Plan Gaming Ultimate Performance activo (Core Parking 0%).' 'Gaming Ultimate Performance plan active (Core Parking 0%).')
})

$script:Controls['BtnQuickUndo'].Add_Click({
    param($sender, $e)
    $msg = Undo-Last
    Refresh-AllStates
    Set-Status $msg
})

$script:Controls['BtnQuickShortcut'].Add_Click({
    param($sender, $e)
    $sc = Create-DesktopShortcut
    if ($sc) { Set-Status (T "Acceso directo 'OptiLite' creado en el Escritorio." "Shortcut 'OptiLite' created on the Desktop.") }
    else { Set-Status (T 'No se pudo crear el acceso: ejecuta OptiLite desde su archivo .ps1.' 'Could not create the shortcut: run OptiLite from its .ps1 file.') }
})

# ---------------- Inicio ------------------------------------------------------
Write-Host ''
Write-Host "  OptiLite v$($script:Version) - optimizador local de Windows 10/11" -ForegroundColor Cyan
Write-Host "  $(T 'Sin descargas, sin instalaciones, sin telemetría.' 'No downloads, no installs, no telemetry.')" -ForegroundColor DarkGray
Write-Host "  $(T 'Registro y punto de restauración: %LOCALAPPDATA%\OptiLite' 'Log and restore point: %LOCALAPPDATA%\OptiLite')" -ForegroundColor DarkGray
Write-Host "  $(T 'Abriendo la interfaz...' 'Opening the interface...')" -ForegroundColor DarkGray
Write-Host ''

$script:LangLoading = $true
$script:Controls['CmbLang'].SelectedIndex = if ($script:Lang -eq 'EN') { 1 } else { 0 }
$script:LangLoading = $false

Initialize-UndoStack
Build-Panels
Initialize-SysInfo
Initialize-Diagnostics
Show-Panel 'NavHome'
Refresh-AllStates
Refresh-LiveStats

$script:Timer = New-Object System.Windows.Threading.DispatcherTimer
$script:Timer.Interval = [TimeSpan]::FromSeconds(5)
$script:Timer.Add_Tick({ Refresh-LiveStats })
$script:Timer.Start()

Write-TempLog "OptiLite v$($script:Version) iniciado (idioma $($script:Lang))."
[void]$window.ShowDialog()
