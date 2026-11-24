#requires -version 5.1
# ============================================================================
#
#   ██████╗  ██████╗  ████████╗ ██╗ ██╗      ██╗ ████████╗ ███████╗
#  ██╔═══██╗ ██╔══██╗ ╚══██╔══╝ ██║ ██║      ██║ ╚══██╔══╝ ██╔════╝
#  ██║   ██║ ██████╔╝    ██║    ██║ ██║      ██║    ██║    █████╗  
#  ██║   ██║ ██╔═══╝     ██║    ██║ ██║      ██║    ██║    ██╔══╝  
#  ╚██████╔╝ ██║         ██║    ██║ ███████╗ ██║    ██║    ███████╗
#   ╚═════╝  ╚═╝         ╚═╝    ╚═╝ ╚══════╝ ╚═╝    ╚═╝    ╚══════╝
#
#  OptiLite v1.0.0 · Optimizador local de Windows 10/11 con interfaz gráfica
#  --------------------------------------------------------------------------
#  - 100% local: sin descargas, sin instalaciones, sin telemetría, sin red.
#  - Paneles: Resumen | Rendimiento | Juegos | Privacidad | Limpieza | Perfiles
#  - Punto de restauración propio + preset "Restaurar Windows": todo reversible.
#  - Registro y copia de seguridad en %LOCALAPPDATA%\OptiLite\
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
$script:Version = '1.0.0'
$script:AppDir = Join-Path $env:LOCALAPPDATA 'OptiLite'
$script:LogPath = Join-Path $script:AppDir 'optilite.log'
$script:BackupPath = Join-Path $script:AppDir 'optilite-restore.json'
if (-not (Test-Path $script:AppDir)) { New-Item -Path $script:AppDir -ItemType Directory -Force | Out-Null }
$script:ScriptPath = $PSCommandPath

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
        return 'No se pudo crear el punto de restauración (revisa los permisos de %LOCALAPPDATA%\OptiLite).'
    }
    Write-TempLog "Punto de restauracion creado ($($states.Count) ajustes)."
    return "Punto de restauración creado: $($states.Count) ajustes guardados en optilite-restore.json."
}

function Restore-RestorePoint {
    if (-not (Test-Path $script:BackupPath)) { return 'Todavía no hay ningún punto de restauración guardado.' }
    try {
        $point = Get-Content -Path $script:BackupPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return 'El punto de restauración está dañado; crea uno nuevo con "Crear punto de restauración".'
    }
    if (-not $point.States) { return 'El punto de restauración está vacío; crea uno nuevo.' }
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
    $extra = if ($reboot) { ' (reinicia para aplicar)' } else { '' }
    return "Punto del $($point.Date) restaurado: $changed ajustes revertidos$extra."
}
# ============================================================================
#  DEFINICION DE AJUSTES  (motor data-driven, estilo WinUtil/WinHance)
#  Cada item:  Id, Cat (Perf/Games/Priv), Grp (subgrupo), Name, Desc,
#  Reboot (si cambia → pide reinicio), Get (estado actual: $true/$false/$null),
#  Set (aplica $true/$false).  $null en Get = "no instalado" (interruptor gris).
# ============================================================================

$Items = @(
    # ------------------------------ RENDIMIENTO ------------------------------
    @{ Id='vbs'; Cat='Perf'; Grp='Sistema y energía'; Reboot=$true
       Name='VBS / Integridad de memoria'
       Desc='Aisla el kernel con virtualización. Desactivado gana ~5-8% de FPS en la mayoría de equipos; Vanguard y FACEIT funcionan igual sin él.'
       Get={ (Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'EnableVirtualizationBasedSecurity') -eq 1 }
       Set={ param($on) Set-VbsState $on | Out-Null } }

    @{ Id='fx'; Cat='Perf'; Grp='Sistema y energía'; Reboot=$false
       Name='Efectos visuales en modo rendimiento'
       Desc='ON = animaciones y transparencias al mínimo (más FPS libres). OFF = Windows decide (aspecto por defecto).'
       Get={ (Get-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting') -eq 2 }
       Set={ param($on) Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' $(if($on){2}else{0}) } }

    @{ Id='sysmain'; Cat='Perf'; Grp='Sistema y energía'; Reboot=$false
       Name='SysMain (Superfetch)'
       Desc='Precarga apps frecuentes en RAM. Con SSD y RAM suficiente su beneficio es bajo: desactívalo para liberar disco y CPU.'
       Get={ $m = Get-ServiceStartMode 'SysMain'; if ($m -eq -1) { $null } else { $m -ne 4 } }
       Set={ param($on) if ($on) { Set-ServiceMode 'SysMain' 2 $false $true | Out-Null } else { Set-ServiceMode 'SysMain' 4 $true $false | Out-Null } } }

    @{ Id='wsearch'; Cat='Perf'; Grp='Sistema y energía'; Reboot=$false
       Name='Windows Search (indexación)'
       Desc='Indexa archivos en segundo plano. Desactivado ahorra CPU/disco constante; el buscador será más lento.'
       Get={ $m = Get-ServiceStartMode 'WSearch'; if ($m -eq -1) { $null } else { $m -ne 4 } }
       Set={ param($on) if ($on) { Set-ServiceMode 'WSearch' 2 $false $true | Out-Null } else { Set-ServiceMode 'WSearch' 4 $true $false | Out-Null } } }

    @{ Id='hiber'; Cat='Perf'; Grp='Sistema y energía'; Reboot=$false
       Name='Hibernación e Inicio rápido'
       Desc='OFF libera ~6-13 GB del SSD (hiberfil.sys) y evita raridades de drivers al arrancar. ON restaura ambos.'
       Get={ Test-Path 'C:\hiberfil.sys' }
       Set={ param($on) if ($on) { powercfg.exe /h on | Out-Null } else { powercfg.exe /h off | Out-Null } } }

    @{ Id='bgapps'; Cat='Perf'; Grp='Sistema y energía'; Reboot=$false
       Name='Apps en segundo plano'
       Desc='Permite que apps UWP sigan ejecutándose cerradas. OFF reduce consumo de RAM y CPU (no afecta programas de escritorio).'
       Get={ (Get-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled') -ne 1 }
       Set={ param($on) Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' $(if($on){0}else{1}) } }

    @{ Id='net'; Cat='Perf'; Grp='Red'; Reboot=$true
       Name='Límite de red multimedia (throttling)'
       Desc='Windows limita el tráfico de red a 10 paquetes/ms. OFF elimina el límite → menos latencia y mejor online.'
       Get={ $v = Get-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex'; ($v -ne -1 -and $v -ne 4294967295) }
       Set={ param($on) $val = if ($on) { 10 } else { 0xFFFFFFFF }; Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex' $val } }

    # --------------------------------- JUEGOS --------------------------------
    @{ Id='vg'; Cat='Games'; Grp='Anti-cheats'; Reboot=$true
       Name='Riot Vanguard (Valorant)'
       Desc='Driver kernel vgk.sys + servicio vgc. Si Valorant no lo exige, mantenlo OFF para arrancar más rápido y sin procesos en kernel.'
       Get={ $a = Get-ServiceStartMode 'vgk'; $b = Get-ServiceStartMode 'vgc'; if ($a -eq -1 -and $b -eq -1) { $null } elseif ($a -ne 4) { $true } else { $false } }
       Set={ param($on) Set-VanguardState $on | Out-Null } }

    @{ Id='fac'; Cat='Games'; Grp='Anti-cheats'; Reboot=$false
       Name='FACEIT Anti-Cheat (CS2)'
       Desc='Controlador FACEIT + servicio auxiliar. Se activa y desactiva al instante, sin reiniciar.'
       Get={ $a = Get-ServiceStartMode 'FACEIT'; $b = Get-ServiceStartMode 'FACEITService'; if ($a -eq -1 -and $b -eq -1) { $null } elseif (($a -ne 4 -and $a -ne -1) -or ($b -ne 4 -and $b -ne -1)) { $true } else { $false } }
       Set={ param($on) Set-FaceitState $on | Out-Null } }

    @{ Id='xbox'; Cat='Games'; Grp='Servicios de juego'; Reboot=$false
       Name='Servicios Xbox y Cloud Gaming'
       Desc='Xbox Live Auth, NetApi, GameSave, GamingServices y soporte de mandos. OFF si no usas Game Pass / juegos de la Store.'
       Get={ $m = Get-ServiceStartMode 'XblAuthManager'; if ($m -eq -1) { $null } else { $m -ne 4 } }
       Set={ param($on) Set-XboxState $on | Out-Null } }

    @{ Id='gamemode'; Cat='Games'; Grp='Captura y pantalla'; Reboot=$false
       Name='Modo Juego (Game Mode)'
       Desc='Da prioridad de CPU/GPU al juego en primer plano. Recomendado: ON.'
       Get={ (Get-Reg 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled') -ne 0 }
       Set={ param($on) $v = if ($on) { 1 } else { 0 }; Set-Reg 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' $v; Set-Reg 'HKCU:\Software\Microsoft\GameBar' 'AllowAutoGameMode' $v } }

    @{ Id='dvr'; Cat='Games'; Grp='Captura y pantalla'; Reboot=$false
       Name='Game Bar y DVR (grabación de fondo)'
       Desc='Graba clips en segundo plano y puede bajar FPS. Recomendado: OFF (las capturas con OBS no se ven afectadas).'
       Get={ (Get-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled') -ne 0 -and (Get-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled') -ne 0 }
       Set={ param($on) $v = if ($on) { 1 } else { 0 }; Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' $v; Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' $v; Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' $v } }

    @{ Id='fso'; Cat='Games'; Grp='Captura y pantalla'; Reboot=$false
       Name='Optimizaciones de pantalla completa (FSO)'
       Desc='ON = compatibilidad por defecto de Windows. OFF = exclusiva real → menos latencia y stutter; actívalo si un juego antiguo falla.'
       Get={ (Get-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_FSEBehaviorMode') -ne 2 }
       Set={ param($on) if ($on) { Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_FSEBehaviorMode' 0; Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_HonorUserFSEBehaviorMode' 0; Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_DXGIHonorFSEWindowsCompatible' 0 } else { Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_FSEBehaviorMode' 2; Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_HonorUserFSEBehaviorMode' 1; Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_DXGIHonorFSEWindowsCompatible' 1; Set-Reg 'HKCU:\System\GameConfigStore' 'GameDVR_EFSEFeatureFlags' 0 } } }

    @{ Id='ptr'; Cat='Games'; Grp='Precisión y hardware'; Reboot=$false
       Name='Aceleración del puntero (precisión mejorada)'
       Desc='Curva de aceleración del ratón. OFF = movimiento 1:1 constante, estándar competitivo (CS2 / Valorant).'
       Get={ (Get-Reg 'HKCU:\Control Panel\Mouse' 'MouseSpeed') -ne 0 }
       Set={ param($on) if ($on) { Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseSpeed' 1 'String'; Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseThreshold1' 6 'String'; Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseThreshold2' 10 'String' } else { Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseSpeed' 0 'String'; Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseThreshold1' 0 'String'; Set-Reg 'HKCU:\Control Panel\Mouse' 'MouseThreshold2' 0 'String' } } }

    @{ Id='mpo'; Cat='Games'; Grp='Precisión y hardware'; Reboot=$true
       Name='MPO (Multi-Plane Overlay)'
       Desc='Conocido por causar microstutter y flashes en las GPU AMD Polaris (serie RX 400/500). OFF suele estabilizar el frametime.'
       Get={ (Get-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm' 'OverlayTestMode') -ne 5 }
       Set={ param($on) if ($on) { Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm' -Name 'OverlayTestMode' -EA 0 } else { Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm' 'OverlayTestMode' 5 } } }

    @{ Id='daw'; Cat='Games'; Grp='Precisión y hardware'; Reboot=$false
       Name='Modo DAW (audio prioritario)'
       Desc='ON protege el buffer de audio para Ableton/FL (SystemResponsiveness=10). OFF = modo gaming (=0, máx. FPS).'
       Get={ (Get-Reg 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'SystemResponsiveness') -eq 10 }
       Set={ param($on) Set-AudioDawState $on | Out-Null } }

    # ------------------------------- PRIVACIDAD ------------------------------
    @{ Id='tele'; Cat='Priv'; Grp='Datos y telemetría'; Reboot=$false
       Name='Telemetría y datos de diagnóstico'
       Desc='Datos que Windows envía a Microsoft. OFF = nivel mínimo (en las ediciones LTSC se respeta el nivel Seguridad). Recomendado: OFF.'
       Get={ (Get-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry') -ne 0 }
       Set={ param($on) Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' $(if($on){1}else{0}) } }

    @{ Id='diag'; Cat='Priv'; Grp='Datos y telemetría'; Reboot=$false
       Name='Servicio DiagTrack (experiencias conectadas)'
       Desc='El servicio que sube la telemetría. Desactivarlo complementa el ajuste anterior; se aplica al instante.'
       Get={ $m = Get-ServiceStartMode 'DiagTrack'; if ($m -eq -1) { $null } else { $m -ne 4 } }
       Set={ param($on) if ($on) { Set-ServiceMode 'DiagTrack' 2 $false $true | Out-Null } else { Set-ServiceMode 'DiagTrack' 4 $true $false | Out-Null } } }

    @{ Id='act'; Cat='Priv'; Grp='Datos y telemetría'; Reboot=$false
       Name='Historial de actividad'
       Desc='Registro de apps y archivos usados que puede sincronizarse con la nube. Recomendado: OFF.'
       Get={ (Get-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableActivityFeed') -ne 0 }
       Set={ param($on) $v = if ($on) { 1 } else { 0 }; Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'EnableActivityFeed' $v; Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'PublishUserActivities' $v; Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' 'UploadUserActivities' $v } }

    @{ Id='adid'; Cat='Priv'; Grp='Personalización y anuncios'; Reboot=$false
       Name='Identificador de publicidad'
       Desc='ID anonimo que las apps usan para personalizar anuncios. Recomendado: OFF.'
       Get={ (Get-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled') -ne 0 }
       Set={ param($on) Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' $(if($on){1}else{0}) } }

    @{ Id='sugg'; Cat='Priv'; Grp='Personalización y anuncios'; Reboot=$false
       Name='Sugerencias, consejos y apps promocionadas'
       Desc='Recomendaciones en el menú Inicio y descargas automáticas de apps sugeridas. Recomendado: OFF.'
       Get={ (Get-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SystemPaneSuggestionsEnabled') -ne 0 }
       Set={ param($on) $v = if ($on) { 1 } else { 0 }; $p = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'; foreach ($n in @('SystemPaneSuggestionsEnabled','SilentInstalledAppsEnabled','SubscribedContent-338388Enabled','SubscribedContent-338389Enabled','SubscribedContent-353698Enabled','SubscribedContent-310093Enabled')) { Set-Reg $p $n $v } } }

    @{ Id='ink'; Cat='Priv'; Grp='Personalización y anuncios'; Reboot=$false
       Name='Recolección de escritura y tinta'
       Desc='Envía lo que escribes/tecleas para "mejorar sugerencias". Recomendado: OFF.'
       Get={ (Get-Reg 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection') -ne 1 }
       Set={ param($on) $v = if ($on) { 0 } else { 1 }; Set-Reg 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' $v; Set-Reg 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' $v; Set-Reg 'HKCU:\Software\Microsoft\Personalization\Settings' 'AcceptedPrivacyPolicy' $(if($on){1}else{0}) } }

    @{ Id='fb'; Cat='Priv'; Grp='Personalización y anuncios'; Reboot=$false
       Name='Notificaciones de comentarios (Feedback)'
       Desc='Encuestas "¿Qué te parece Windows?" que aparecen de vez en cuando. Recomendado: OFF.'
       Get={ (Get-Reg 'HKCU:\Software\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod') -ne 0 }
       Set={ param($on) Set-Reg 'HKCU:\Software\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod' $(if($on){1}else{0}) } }

    @{ Id='lang'; Cat='Priv'; Grp='Personalización y anuncios'; Reboot=$false
       Name='Enviar idioma local a los sitios web'
       Desc='Los sitios pueden pedir tu lista de idiomas para fingerprinting leve. Recomendado: OFF.'
       Get={ (Get-Reg 'HKCU:\Control Panel\International\User Profile' 'HttpAcceptLanguageOptOut') -ne 1 }
       Set={ param($on) Set-Reg 'HKCU:\Control Panel\International\User Profile' 'HttpAcceptLanguageOptOut' $(if($on){0}else{1}) } }
)

# --------------------------- Acciones (botones) -----------------------------
$Actions = @(
    @{ Id='quick';  Cat='Clean'; Grp='Archivos y caché'; Name='Limpieza rápida'; Btn='Limpiar'
       Desc='Borra tu %TEMP% y C:\Windows\Temp. Seguro y diario; libera espacio al momento.'
       Run={ Invoke-TempClean $false } }
    @{ Id='deep';   Cat='Clean'; Grp='Archivos y caché'; Name='Limpieza profunda'; Btn='Limpiar todo'
       Desc='Rápida + Prefetch + logs CBS + informes de errores (WER) + caché de Windows Update.'
       Run={ Invoke-TempClean $true } }
    @{ Id='bin';    Cat='Clean'; Grp='Archivos y caché'; Name='Vaciar papelera'; Btn='Vaciar'
       Desc='Elimina definitivamente los archivos de la Papelera de reciclaje.'
       Run={ Clear-RecycleBin -Force -EA 0; "Papelera vaciada." } }
    @{ Id='dns';    Cat='Clean'; Grp='Archivos y caché'; Name='Vaciar caché DNS'; Btn='Vaciar'
       Desc='Útil tras cambiar de red o DNS: obliga a resolver nombres de nuevo.'
       Run={ Clear-DnsClientCache -EA 0; "Caché DNS vaciada." } }
    @{ Id='plan';   Cat='Perf';  Grp='Energía'; Name='Plan de energía Gaming Ultimate'; Btn='Activar'
       Desc='Duplica el plan Ultimate Performance, desactiva Core Parking y pone min. CPU al 100% (enchufado).'
       Run={ Ensure-GamingPowerPlan; "Plan Gaming Ultimate Performance activo (Core Parking 0%)." } }

    @{ Id='rpoint'; Cat='Profiles'; Grp='Copia de seguridad'; Name='Crear punto de restauración'; Btn='Crear'
       Desc='Guarda en un JSON el estado actual de todos los ajustes. Se crea automáticamente antes de aplicar un perfil.'
       Run={ New-RestorePoint } }

    @{ Id='rrestore'; Cat='Profiles'; Grp='Copia de seguridad'; Name='Restaurar último punto'; Btn='Restaurar'
       Desc='Reaplica el último punto guardado y deshace todos los cambios hechos con OptiLite desde entonces.'
       Run={ Restore-RestorePoint } }
)

# ------------------------------ Perfiles ------------------------------------
$Presets = @(
    @{ Id='comp'; Name='COMPETITIVO'; Color='#34D399'
       Desc='Vanguard ON, FACEIT ON, Xbox OFF, VBS OFF, Game Mode ON, DVR OFF, FSO OFF, aceleración de ratón OFF, red sin límite, MPO OFF, audio gaming.'
       States=@{ vg=$true; fac=$true; xbox=$false; vbs=$false; gamemode=$true; dvr=$false; fso=$false; ptr=$false; net=$false; mpo=$false; daw=$false } }
    @{ Id='aaa'; Name='JUEGOS AAA'; Color='#60A5FA'
       Desc='Anti-cheats OFF, Xbox OFF, VBS OFF, efectos visuales al mínimo, SysMain OFF, DVR/FSO/ratón OFF, red sin límite, MPO OFF. Máximo FPS.'
       States=@{ vg=$false; fac=$false; xbox=$false; vbs=$false; fx=$true; sysmain=$false; gamemode=$true; dvr=$false; fso=$false; ptr=$false; net=$false; mpo=$false; daw=$false } }
    @{ Id='cloud'; Name='CLOUD / XBOX'; Color='#A78BFA'
       Desc='Xbox y Game Pass ON, anti-cheats OFF, VBS OFF, red sin límite para streaming, audio gaming.'
       States=@{ vg=$false; fac=$false; xbox=$true; vbs=$false; net=$false; daw=$false } }
    @{ Id='reset'; Name='RESTAURAR WINDOWS'; Color='#F59E0B'
       Desc='Devuelve TODOS los ajustes a valores por defecto de Windows (telemetría, efectos, servicios, DVR, ratón...). Los anti-cheats no se tocan.'
       States=@{ vbs=$true; fx=$false; sysmain=$true; wsearch=$true; hiber=$true; bgapps=$true; net=$true; xbox=$true; gamemode=$true; dvr=$true; fso=$true; ptr=$true; mpo=$true; daw=$false; tele=$true; diag=$true; act=$true; adid=$true; sugg=$true; ink=$true; fb=$true; lang=$true } }
)
# ============================================================================
#  INTERFAZ (WPF) - estilo WinHance: sidebar + tarjetas + interruptores
# ============================================================================
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="OptiLite v1.0.0 · Optimizador de Windows 10/11"
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
                        <TextBlock Text="Optimización local · sin descargas" Foreground="#5D6B80" FontSize="10"/>
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
                            <TextBlock Text="Reinicio pendiente" Foreground="#FCD34D" FontSize="10.5" FontWeight="Bold" HorizontalAlignment="Center"/>
                        </Border>
                    </StackPanel>
                </Border>

                <StackPanel Margin="0,6,0,10">
                    <ToggleButton x:Name="NavHome" Style="{StaticResource NavBtn}" IsChecked="True">
                        <StackPanel Orientation="Horizontal">
                            <Border Width="8" Height="8" CornerRadius="4" Background="#38BDF8" VerticalAlignment="Center"/>
                            <TextBlock Text="Resumen" Margin="10,0,0,0" VerticalAlignment="Center"/>
                        </StackPanel>
                    </ToggleButton>
                    <ToggleButton x:Name="NavPerf" Style="{StaticResource NavBtn}">
                        <StackPanel Orientation="Horizontal">
                            <Border Width="8" Height="8" CornerRadius="4" Background="#F59E0B" VerticalAlignment="Center"/>
                            <TextBlock Text="Rendimiento" Margin="10,0,0,0" VerticalAlignment="Center"/>
                        </StackPanel>
                    </ToggleButton>
                    <ToggleButton x:Name="NavGames" Style="{StaticResource NavBtn}">
                        <StackPanel Orientation="Horizontal">
                            <Border Width="8" Height="8" CornerRadius="4" Background="#8B5CF6" VerticalAlignment="Center"/>
                            <TextBlock Text="Juegos" Margin="10,0,0,0" VerticalAlignment="Center"/>
                        </StackPanel>
                    </ToggleButton>
                    <ToggleButton x:Name="NavPriv" Style="{StaticResource NavBtn}">
                        <StackPanel Orientation="Horizontal">
                            <Border Width="8" Height="8" CornerRadius="4" Background="#10B981" VerticalAlignment="Center"/>
                            <TextBlock Text="Privacidad" Margin="10,0,0,0" VerticalAlignment="Center"/>
                        </StackPanel>
                    </ToggleButton>
                    <ToggleButton x:Name="NavClean" Style="{StaticResource NavBtn}">
                        <StackPanel Orientation="Horizontal">
                            <Border Width="8" Height="8" CornerRadius="4" Background="#22D3EE" VerticalAlignment="Center"/>
                            <TextBlock Text="Limpieza" Margin="10,0,0,0" VerticalAlignment="Center"/>
                        </StackPanel>
                    </ToggleButton>
                    <ToggleButton x:Name="NavProfiles" Style="{StaticResource NavBtn}">
                        <StackPanel Orientation="Horizontal">
                            <Border Width="8" Height="8" CornerRadius="4" Background="#F472B6" VerticalAlignment="Center"/>
                            <TextBlock Text="Perfiles" Margin="10,0,0,0" VerticalAlignment="Center"/>
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
                </Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0">
                    <TextBlock x:Name="TxtSectionTitle" Text="Resumen" Foreground="#F1F5F9" FontSize="17" FontWeight="Bold"/>
                    <TextBlock x:Name="TxtSectionDesc" Text="Estado del equipo y acciones rápidas" Foreground="#7C8AA0" FontSize="11" Margin="0,2,0,0"/>
                </StackPanel>
                <Grid Grid.Column="1" Width="215" VerticalAlignment="Center">
                    <Border Background="#12161F" BorderBrush="#243043" BorderThickness="1" CornerRadius="7">
                        <TextBox x:Name="TxtSearch" Background="Transparent" BorderThickness="0" Padding="10,6" Foreground="#E2E8F0" FontSize="11.5" VerticalContentAlignment="Center"/>
                    </Border>
                    <TextBlock x:Name="TxtSearchHint" Text="Buscar ajuste..." Foreground="#5A6A82" FontSize="11.5" Margin="12,0,0,0" VerticalAlignment="Center" HorizontalAlignment="Left" IsHitTestVisible="False"/>
                </Grid>
            </Grid>

            <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Padding="0,0,4,0">
                <Grid>
                    <StackPanel x:Name="PanelHome">
                        <Border Style="{StaticResource CardStyle}">
                            <StackPanel>
                                <TextBlock Text="EQUIPO" Style="{StaticResource GrpHeader}"/>
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
                                    <TextBlock Grid.Row="0" Grid.Column="0" Text="Procesador" Foreground="#7C8AA0" FontSize="11.5" Margin="0,3"/>
                                    <TextBlock x:Name="TxtSysCpu" Grid.Row="0" Grid.Column="1" Text="--" Foreground="#E2E8F0" FontSize="11.5" FontWeight="SemiBold" Margin="0,3"/>
                                    <TextBlock Grid.Row="1" Grid.Column="0" Text="Gráfica" Foreground="#7C8AA0" FontSize="11.5" Margin="0,3"/>
                                    <TextBlock x:Name="TxtSysGpu" Grid.Row="1" Grid.Column="1" Text="--" Foreground="#E2E8F0" FontSize="11.5" FontWeight="SemiBold" Margin="0,3"/>
                                    <TextBlock Grid.Row="2" Grid.Column="0" Text="Memoria" Foreground="#7C8AA0" FontSize="11.5" Margin="0,3"/>
                                    <TextBlock x:Name="TxtSysRam" Grid.Row="2" Grid.Column="1" Text="--" Foreground="#E2E8F0" FontSize="11.5" FontWeight="SemiBold" Margin="0,3"/>
                                    <TextBlock Grid.Row="3" Grid.Column="0" Text="Sistema" Foreground="#7C8AA0" FontSize="11.5" Margin="0,3"/>
                                    <TextBlock x:Name="TxtSysOs" Grid.Row="3" Grid.Column="1" Text="--" Foreground="#E2E8F0" FontSize="11.5" FontWeight="SemiBold" Margin="0,3"/>
                                    <TextBlock Grid.Row="4" Grid.Column="0" Text="Disco C:" Foreground="#7C8AA0" FontSize="11.5" Margin="0,3"/>
                                    <TextBlock x:Name="TxtSysDisk" Grid.Row="4" Grid.Column="1" Text="--" Foreground="#E2E8F0" FontSize="11.5" FontWeight="SemiBold" Margin="0,3"/>
                                </Grid>
                            </StackPanel>
                        </Border>

                        <Border Style="{StaticResource CardStyle}">
                            <StackPanel>
                                <TextBlock Text="ESTADO" Style="{StaticResource GrpHeader}"/>
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
                                    <TextBlock Grid.Row="0" Grid.Column="0" Text="Cambios sin reiniciar" Foreground="#7C8AA0" FontSize="11.5" Margin="0,3"/>
                                    <TextBlock x:Name="TxtSumReboot" Grid.Row="0" Grid.Column="1" Text="--" Foreground="#6EE7B7" FontSize="11.5" FontWeight="SemiBold" Margin="0,3"/>
                                    <TextBlock Grid.Row="1" Grid.Column="0" Text="Riot Vanguard" Foreground="#7C8AA0" FontSize="11.5" Margin="0,3"/>
                                    <TextBlock x:Name="TxtSumVg" Grid.Row="1" Grid.Column="1" Text="--" Foreground="#E2E8F0" FontSize="11.5" FontWeight="SemiBold" Margin="0,3"/>
                                    <TextBlock Grid.Row="2" Grid.Column="0" Text="FACEIT" Foreground="#7C8AA0" FontSize="11.5" Margin="0,3"/>
                                    <TextBlock x:Name="TxtSumFac" Grid.Row="2" Grid.Column="1" Text="--" Foreground="#E2E8F0" FontSize="11.5" FontWeight="SemiBold" Margin="0,3"/>
                                </Grid>
                            </StackPanel>
                        </Border>

                        <Border Style="{StaticResource CardStyle}">
                            <StackPanel>
                                <TextBlock Text="ACCIONES RÁPIDAS" Style="{StaticResource GrpHeader}"/>
                                <WrapPanel>
                                    <Button x:Name="BtnQuickTemp" Content="Limpiar TEMP" Style="{StaticResource BtnStyle}" Margin="0,0,8,8"/>
                                    <Button x:Name="BtnQuickDeep" Content="Limpieza profunda" Style="{StaticResource BtnStyle}" Margin="0,0,8,8"/>
                                    <Button x:Name="BtnQuickPlan" Content="Plan Ultimate" Style="{StaticResource BtnStyle}" Margin="0,0,8,8"/>
                                    <Button x:Name="BtnQuickShortcut" Content="Acceso en Escritorio" Style="{StaticResource BtnStyle}" Margin="0,0,0,8"/>
                                </WrapPanel>
                            </StackPanel>
                        </Border>
                    </StackPanel>
                    <StackPanel x:Name="PanelPerf" Visibility="Collapsed"/>
                    <StackPanel x:Name="PanelGames" Visibility="Collapsed"/>
                    <StackPanel x:Name="PanelPriv" Visibility="Collapsed"/>
                    <StackPanel x:Name="PanelClean" Visibility="Collapsed"/>
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
foreach ($n in @('TxtSectionTitle','TxtSectionDesc','PanelHome','PanelPerf','PanelGames','PanelPriv','PanelClean','PanelProfiles','TxtLiveRam','TxtLiveProc','BtnRefreshAll','BadgePending','BorderStatus','TxtStatus','BtnReboot','TxtSearch','TxtSearchHint','TxtSysCpu','TxtSysGpu','TxtSysRam','TxtSysOs','TxtSysDisk','TxtSumReboot','TxtSumVg','TxtSumFac','BtnQuickTemp','BtnQuickDeep','BtnQuickPlan','BtnQuickShortcut','NavHome','NavPerf','NavGames','NavPriv','NavClean','NavProfiles')) {
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

$script:CatPanels   = @{ 'Perf' = 'PanelPerf'; 'Games' = 'PanelGames'; 'Priv' = 'PanelPriv'; 'Clean' = 'PanelClean'; 'Profiles' = 'PanelProfiles' }
$script:PanelWords  = @{ 'PanelPerf' = 'rendimiento cpu energia red efectos servicios'; 'PanelGames' = 'juegos gaming anti-cheat fps latencia'; 'PanelPriv' = 'privacidad telemetria anuncios datos'; 'PanelClean' = 'limpieza disco cache temporales'; 'PanelProfiles' = 'perfil preset rapido restauracion backup deshacer undo copia' }

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
    [void]$txt.Children.Add((New-Text $item.Name '#F1F5F9' 13 'SemiBold'))
    $desc = New-Text $item.Desc '#8B99AE' 11 'Normal' $true
    $desc.Margin = New-Object System.Windows.Thickness(0, 2, 0, 0)
    [void]$txt.Children.Add($desc)
    if ($item.Reboot) {
        $tag = New-Text 'PIDE REINICIO' '#D97706' 9 'Bold'
        $tag.Margin = New-Object System.Windows.Thickness(0, 4, 0, 0)
        [void]$txt.Children.Add($tag)
    }
    [void]$dock.Children.Add($txt)
    $card.Child = $dock

    Register-Card $panel $item.Grp $card "$($item.Name) $($item.Desc) $($item.Grp)"
    [void]$script:Controls[$panel].Children.Add($card)
    $script:ItemControls[$item.Id] = $chk

    $chk.Add_Click({
        param($sender, $e)
        $it = $sender.Tag
        $target = [bool]$sender.IsChecked
        $cur = & $it.Get
        if ($cur -eq $target) {
            Set-Status "$($it.Name): ya estaba en ese estado."
            return
        }
        & $it.Set $target
        if ($it.Reboot) { $script:PendingReboot = $true }
        Write-TempLog "Ajuste '$($it.Name)' -> $target."
        Refresh-AllStates
        $word = if ($target) { 'activado' } else { 'desactivado' }
        $extra = if ($it.Reboot) { ' (reinicia para aplicar)' } else { '' }
        Set-Status "$($it.Name) $word$extra."
    })
}

function Add-ActionCard([string]$panel, $act) {
    $card = New-Object System.Windows.Controls.Border
    $card.Style = $script:Window.TryFindResource('CardStyle')
    $dock = New-Object System.Windows.Controls.DockPanel

    $btn = New-Object System.Windows.Controls.Button
    $btn.Style = $script:Window.TryFindResource('BtnStyle')
    $btn.Content = $act.Btn
    $btn.Tag = $act
    $btn.Margin = New-Object System.Windows.Thickness(14, 0, 0, 0)
    $btn.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    [System.Windows.Controls.DockPanel]::SetDock($btn, [System.Windows.Controls.Dock]::Right)
    [void]$dock.Children.Add($btn)

    $txt = New-Object System.Windows.Controls.StackPanel
    $txt.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    [void]$txt.Children.Add((New-Text $act.Name '#F1F5F9' 13 'SemiBold'))
    $desc = New-Text $act.Desc '#8B99AE' 11 'Normal' $true
    $desc.Margin = New-Object System.Windows.Thickness(0, 2, 0, 0)
    [void]$txt.Children.Add($desc)
    [void]$dock.Children.Add($txt)
    $card.Child = $dock

    Register-Card $panel $act.Grp $card "$($act.Name) $($act.Desc)"
    [void]$script:Controls[$panel].Children.Add($card)

    $btn.Add_Click({
        param($sender, $e)
        $act = $sender.Tag
        Set-Status "Ejecutando: $($act.Name)..."
        Update-UiNow
        $res = & $act.Run
        Write-TempLog "Accion '$($act.Name)' ejecutada."
        Refresh-AllStates
        Refresh-LiveStats
        if ($res -is [ValueType]) { Set-Status "$($act.Name) completada (~$res MB liberados)." }
        elseif ($res) { Set-Status "$($act.Name): $res" }
        else { Set-Status "$($act.Name) completada." }
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
    $btn.Content = 'Aplicar perfil'
    $btn.Tag = $preset
    $btn.Margin = New-Object System.Windows.Thickness(14, 0, 0, 0)
    $btn.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    [System.Windows.Controls.DockPanel]::SetDock($btn, [System.Windows.Controls.Dock]::Right)
    [void]$dock.Children.Add($btn)

    $txt = New-Object System.Windows.Controls.StackPanel
    $txt.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    [void]$txt.Children.Add((New-Text $preset.Name $preset.Color 13.5 'Bold'))
    $desc = New-Text $preset.Desc '#8B99AE' 11 'Normal' $true
    $desc.Margin = New-Object System.Windows.Thickness(0, 3, 0, 0)
    [void]$txt.Children.Add($desc)
    [void]$dock.Children.Add($txt)
    $card.Child = $dock

    Register-Card 'PanelProfiles' 'Perfiles de un clic' $card "$($preset.Name) $($preset.Desc)"
    [void]$script:Controls['PanelProfiles'].Children.Add($card)

    $btn.Add_Click({
        param($sender, $e)
        $p = $sender.Tag
        Set-Status "Aplicando perfil $($p.Name)..."
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
                $changed++
                if ($it.Reboot) { $reboot = $true }
            }
        }
        if ($reboot) { $script:PendingReboot = $true }
        Write-TempLog "Perfil '$($p.Name)' aplicado ($changed ajustes)."
        Refresh-AllStates
        $msg = "Perfil $($p.Name) aplicado: $changed ajustes (punto de restauración actualizado)."
        if ($reboot) { $msg = $msg + ' Reinicia para aplicar los cambios de kernel/energía.' }
        Set-Status $msg
    })
}

function Build-Panels {
    foreach ($it  in $Items)  { $p = $script:CatPanels[$it.Cat];   if ($p) { Add-ToggleCard $p $it } }
    foreach ($act in $Actions) { $p = $script:CatPanels[$act.Cat]; if ($p) { Add-ActionCard $p $act } }
    foreach ($preset in $Presets) { Add-PresetCard $preset }
}

# ---------------- Navegación y búsqueda --------------------------------------
$script:NavMap = @(
    @{ Btn='NavHome';     Panel='PanelHome';     Title='Resumen';     Desc='Estado del equipo y acciones rápidas' }
    @{ Btn='NavPerf';     Panel='PanelPerf';     Title='Rendimiento'; Desc='CPU, memoria, efectos visuales, servicios y red' }
    @{ Btn='NavGames';    Panel='PanelGames';    Title='Juegos';      Desc='Anti-cheats, Xbox, captura, latencia y audio' }
    @{ Btn='NavPriv';     Panel='PanelPriv';     Title='Privacidad';  Desc='Telemetría, historial, anuncios y datos personales' }
    @{ Btn='NavClean';    Panel='PanelClean';    Title='Limpieza';    Desc='Archivos temporales, caché y mantenimiento' }
    @{ Btn='NavProfiles'; Panel='PanelProfiles'; Title='Perfiles';    Desc='Perfiles de un clic y punto de restauración' }
)

function Show-Panel([string]$btnName) {
    foreach ($n in $script:NavMap) {
        $active = ($n.Btn -eq $btnName)
        $script:Controls[$n.Btn].IsChecked = $active
        if ($active) {
            $script:Controls[$n.Panel].Visibility = 'Visible'
            $script:Controls['TxtSectionTitle'].Text = $n.Title
            $script:Controls['TxtSectionDesc'].Text = $n.Desc
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
    $script:Controls['TxtLiveProc'].Text = "Proc $((Get-Process -EA 0).Count)"
}

function Update-Summary {
    if ($script:PendingReboot) {
        $script:Controls['TxtSumReboot'].Text = 'Sí - reinicia para aplicar los cambios'
        $script:Controls['TxtSumReboot'].Foreground = Get-Br '#FCD34D'
        $script:Controls['BadgePending'].Visibility = 'Visible'
    } else {
        $script:Controls['TxtSumReboot'].Text = 'Ninguno'
        $script:Controls['TxtSumReboot'].Foreground = Get-Br '#6EE7B7'
        $script:Controls['BadgePending'].Visibility = 'Collapsed'
    }
    foreach ($pair in @( @('vg','TxtSumVg'), @('fac','TxtSumFac') )) {
        $it = $script:ItemMap[$pair[0]]
        $cur = & $it.Get
        $tb = $script:Controls[$pair[1]]
        if ($null -eq $cur)      { $tb.Text = 'No instalado'; $tb.Foreground = Get-Br '#8B99AE' }
        elseif ($cur)            { $tb.Text = 'Activado';     $tb.Foreground = Get-Br '#6EE7B7' }
        else                     { $tb.Text = 'Desactivado';  $tb.Foreground = Get-Br '#F87171' }
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
        $script:Controls['TxtStatus'].Text = "$msg  [REINICIO PENDIENTE]"
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
        $script:Controls['TxtSysDisk'].Text = "$freeGB GB libres de $totGB GB"
    }
}

# ---------------- Manejadores de eventos -------------------------------------
foreach ($n in $script:NavMap) {
    $script:Controls[$n.Btn].Add_Click({ param($sender, $e) Show-Panel $sender.Name })
}

$script:Controls['BtnRefreshAll'].Add_Click({
    param($sender, $e)
    Refresh-AllStates
    Refresh-LiveStats
    Set-Status 'Estados actualizados.'
})

$script:Controls['BtnReboot'].Add_Click({
    param($sender, $e)
    $ans = [System.Windows.MessageBox]::Show('¿Reiniciar la PC ahora para aplicar los cambios pendientes?', 'OptiLite - Reiniciar PC', 'YesNo', 'Question')
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

$script:Controls['BtnQuickTemp'].Add_Click({
    param($sender, $e)
    Set-Status 'Limpiando temporales...'
    Update-UiNow
    $freed = Invoke-TempClean $false
    Refresh-LiveStats
    Set-Status "Limpieza rápida completada (~$freed MB liberados)."
})

$script:Controls['BtnQuickDeep'].Add_Click({
    param($sender, $e)
    Set-Status 'Ejecutando limpieza profunda (puede tardar un poco)...'
    Update-UiNow
    $freed = Invoke-TempClean $true
    Refresh-LiveStats
    Set-Status "Limpieza profunda completada (~$freed MB liberados)."
})

$script:Controls['BtnQuickPlan'].Add_Click({
    param($sender, $e)
    Set-Status 'Activando plan de energía Gaming Ultimate...'
    Update-UiNow
    Ensure-GamingPowerPlan
    Set-Status 'Plan Gaming Ultimate Performance activo (Core Parking 0%).'
})

$script:Controls['BtnQuickShortcut'].Add_Click({
    param($sender, $e)
    $sc = Create-DesktopShortcut
    if ($sc) { Set-Status "Acceso directo 'OptiLite' creado en el Escritorio." }
    else { Set-Status 'No se pudo crear el acceso: ejecuta OptiLite desde su archivo .ps1.' }
})

# ---------------- Inicio ------------------------------------------------------
Write-Host ''
Write-Host "  OptiLite v$($script:Version) - optimizador local de Windows 10/11" -ForegroundColor Cyan
Write-Host '  Sin descargas, sin instalaciones, sin telemetria.' -ForegroundColor DarkGray
Write-Host '  Registro y punto de restauracion: %LOCALAPPDATA%\OptiLite' -ForegroundColor DarkGray
Write-Host '  Abriendo la interfaz...' -ForegroundColor DarkGray
Write-Host ''
Build-Panels
Initialize-SysInfo
Show-Panel 'NavHome'
Refresh-AllStates
Refresh-LiveStats

$script:Timer = New-Object System.Windows.Threading.DispatcherTimer
$script:Timer.Interval = [TimeSpan]::FromSeconds(5)
$script:Timer.Add_Tick({ Refresh-LiveStats })
$script:Timer.Start()

Write-TempLog "OptiLite v$($script:Version) iniciado."
[void]$window.ShowDialog()
