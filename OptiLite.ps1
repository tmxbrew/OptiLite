#requires -version 5.1
# ============================================================================
#
#   ██████╗  ██████╗  ████████╗ ██╗ ██╗      ██╗ ████████╗ ███████╗
#  ██╔═══██╗ ██╔══██╗ ╚══██╔══╝ ██║ ██║      ██╗ ╚══██╔══╝ ██╔════╝
#  ██║   ██║ ██████╔╝    ██║    ██║ ██║      ██╗    ██║    █████╗
#  ██║   ██╗ ██╔═══╝     ██║    ██║ ██║      ██╗    ██║    ██╔══╝
#  ╚██████╔╝ ██║         ██║    ██║ ███████╗ ██╗    ██║    ███████╗
#   ╚═════╝  ╚═╝         ╚═╝    ╚═╝ ╚══════╝ ╚═╝    ╚═╝    ╚══════╝
#
#  OptiLite v2.0.0 · Optimizador local de Windows 10/11 con interfaz gráfica
#  --------------------------------------------------------------------------
#  - 100% local: sin descargas, sin instalaciones, sin telemetría, sin red.
#  - Paneles: Resumen | Rendimiento | Juegos | Privacidad | Red | Limpieza
#    | Navegadores | Paneles clásicos | Inicio | Perfiles.
#  - Interfaz ES/EN conmutable EN VIVO en la pestaña activa (no salta al
#    Resumen) + tema CLARO/OSCURO conmutable en vivo; preferencias
#    persistidas en optilite.json.
#  - Descripciones como tooltip al pasar el mouse: interfaz más limpia.
#  - DNS: Google (8.8.8.8/8.8.4.4) o Cloudflare (1.1.1.1/1.0.0.1),
#    con respaldo automático del DNS previo para restaurarlo.
#  - Paneles clásicos de Windows (God Mode, panel de control clásico...),
#    acceso directo "Panel clásico", menú contextual Win11 clásico.
#  - Debloat de navegadores: Microsoft Edge, Brave, Firefox
#    (políticas de telemetría/planes/features del navegador, sin borrarlos).
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
$script:Version = '2.0.0'
$script:AppDir = Join-Path $env:LOCALAPPDATA 'OptiLite'
$script:LogPath = Join-Path $script:AppDir 'optilite.log'
$script:BackupPath = Join-Path $script:AppDir 'optilite-restore.json'
$script:CfgPath = Join-Path $script:AppDir 'optilite.json'
$script:UndoPath = Join-Path $script:AppDir 'optilite-undo.json'
$script:DisabledDir = Join-Path $script:AppDir 'disabled-startup'
if (-not (Test-Path $script:AppDir)) { New-Item -Path $script:AppDir -ItemType Directory -Force | Out-Null }
$script:ScriptPath = $PSCommandPath

# ---------------- Idioma y tema (persistidos en optilite.json) ---------------
$script:Lang = 'ES'
$script:Theme = 'Dark'
try {
    if (Test-Path $script:CfgPath) {
        $cfg = Get-Content -Path $script:CfgPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($cfg.Lang -eq 'EN') { $script:Lang = 'EN' }
        if ($cfg.Theme -eq 'Light') { $script:Theme = 'Light' }
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

# ---------------- Paleta de colores (tema OSCURO / CLARO) --------------------
# Un único lugar define todos los colores: los estilos XAML se construyen a
# partir de esta tabla, así el tema se cambia en vivo sin recargar la ventana.
$script:Palette = @{
    Dark = @{
        WinBg     = '#0B0E14'; Sidebar = '#0D1118'; Border = '#1B2333'; BorderSoft = '#1E2735'
        Card      = '#12161F'; Card2 = '#131926'; Chip = '#131926'; ChipB = '#253048'
        NavIdle   = '#9AA6B8'; NavHover = '#141B27'; NavSelBg = '#182536'; NavSelFg = '#7DD3FC'
        Title     = '#F1F5F9'; Sub = '#7C8AA0'; Text = '#E2E8F0'; Muted = '#8FA0B8'; Dim = '#8B99AE'
        Accent    = '#38BDF8'; Ok = '#6EE7B7'; Warn = '#FCD34D'; WarnB = '#D97706'; Err = '#F87171'
        BtnBg     = '#1C2431'; BtnB = '#2C3A50'; Track = '#232B3A'; TrackB = '#33405A'; Thumb = '#94A3B8'
        StatusBg  = '#141821'; StatusB = '#252B38'; StatusFg = '#CBD5E1'
        StatusBgW = '#291F11'; ScrollBg = '#10141D'; ScrollFg = '#2A3547'
        Section   = '#0F141D'
    }
    Light = @{
        WinBg     = '#F3F5F9'; Sidebar = '#FFFFFF'; Border = '#D9DEE8'; BorderSoft = '#DCE1EA'
        Card      = '#FFFFFF'; Card2 = '#F4F6FA'; Chip = '#EEF1F6'; ChipB = '#D9DEE8'
        NavIdle   = '#5A6A82'; NavHover = '#EDF0F5'; NavSelBg = '#E2E9F5'; NavSelFg = '#1D7FB8'
        Title     = '#141B27'; Sub = '#6A7890'; Text = '#22293A'; Muted = '#7A8798'; Dim = '#77839A'
        Accent    = '#0E8FD6'; Ok = '#12967C'; Warn = '#B45309'; WarnB = '#D97706'; Err = '#DC2626'
        BtnBg     = '#EDF0F5'; BtnB = '#C9D0DC'; Track = '#D6DBE4'; TrackB = '#B9C0CD'; Thumb = '#FFFFFF'
        StatusBg  = '#EDEFF4'; StatusB = '#D3D8E2'; StatusFg = '#3A4354'
        StatusBgW = '#FCEFD2'; ScrollBg = '#EDF0F5'; ScrollFg = '#B9C0CD'
        Section   = '#FFFFFF'
    }
}

function C([string]$name) {
    # Color del tema activo
    $t = $script:Palette[$script:Theme]
    return $t[$name]
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

function Remove-Reg([string]$path, [string]$name) {
    try { Remove-ItemProperty -Path $path -Name $name -EA 0 } catch {}
}

# ---------------- Helpers de servicios --------------------------------------
# Tareas programadas via COM (Schedule.Service): instantaneo y disponible en
# PS 5.1 y 7 sin cargar el modulo ScheduledTasks (Get-ScheduledTask puede
# tardar muchisimo o colgarse en sesiones elevadas, congelando el arranque).
$script:TaskPaths = @(
    '\Microsoft\Windows\Customer Experience Improvement Program\',
    '\Microsoft\Windows\Application Experience\',
    '\Microsoft\Windows\DiskDiagnostic\'
)

function Get-TelemetryTasksDisabled {
    # Devuelve $true si las tareas CEIP/Aappraiser estan deshabilitadas,
    # $null si no se pueden leer. Usa el COM directo (rapido y seguro).
    try {
        $svc = New-Object -ComObject Schedule.Service
        $svc.Connect()
        $checked = 0; $disabled = 0
        $folder = $svc.GetFolder('\Microsoft\Windows\Customer Experience Improvement Program\')
        $tasks = $folder.GetTasks(0)
        foreach ($t in $tasks) {
            $checked++
            if ($t.State -eq 4) { $disabled++ }
        }
        if ($checked -eq 0) { return $null }
        return ($disabled -ge 3)
    } catch { return $null }
}

function Set-TelemetryTasksDisabled([bool]$on) {
    try {
        $svc = New-Object -ComObject Schedule.Service
        $svc.Connect()
        foreach ($p in $script:TaskPaths) {
            try {
                $folder = $svc.GetFolder($p)
                $tasks = $folder.GetTasks(0)
                foreach ($t in $tasks) {
                    if ($on) { $t.Enabled = $false } else { $t.Enabled = $true }
                }
            } catch {}
        }
    } catch { Write-TempLog "No se pudieron tocar las tareas de telemetria: $($_.Exception.Message)" }
}
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

# ---------------- DNS: Google / Cloudflare con respaldo ---------------------
# El respaldo guarda el DNS previo por adaptador en HKLM:\SOFTWARE\OptiLite\DnsBackup
# para que "Restaurar DNS automático" devuelva exactamente lo que había antes.
function Get-DnsBackup([string]$ifaceId) {
    return (Get-Reg 'HKLM:\SOFTWARE\OptiLite\DnsBackup' $ifaceId)
}

function Set-DnsBackup([string]$ifaceId, [string]$servers) {
    Set-Reg 'HKLM:\SOFTWARE\OptiLite\DnsBackup' $ifaceId $servers 'String'
}

function Get-ActiveDnsServers($nic) {
    # $nic: objeto NetworkInterface; devuelve "ip1,ip2" (vacío = automático)
    try {
        $real = @()
        foreach ($a in $nic.GetIPProperties().DnsAddresses) { $real += $a.IPAddressToString }
        return ($real -join ',')
    } catch { return '' }
}

function Get-DnsProvider {
    # $true = Google, $false = Cloudflare, $null = otro/automático
    $nics = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() |
        Where-Object { $_.OperationalStatus -eq 'Up' -and ($_.NetworkInterfaceType -ne [System.Net.NetworkInformation.NetworkInterfaceType]::Loopback) }
    $found = $null
    foreach ($nic in $nics) {
        $dns = Get-ActiveDnsServers $nic
        if ($dns -eq '8.8.8.8,8.8.4.4' -or $dns -eq '8.8.4.4,8.8.8.8' -or $dns -eq '8.8.8.8' -or $dns -eq '8.8.4.4') { $found = $true }
        elseif ($dns -eq '1.1.1.1,1.0.0.1' -or $dns -eq '1.0.0.1,1.1.1.1' -or $dns -eq '1.1.1.1' -or $dns -eq '1.0.0.1') { if ($null -eq $found) { $found = $false } }
    }
    return $found
}

function Set-DnsProvider([bool]$google) {
    $nics = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() |
        Where-Object { $_.OperationalStatus -eq 'Up' -and ($_.NetworkInterfaceType -ne [System.Net.NetworkInformation.NetworkInterfaceType]::Loopback) }
    $applied = 0
    $primary, $secondary = if ($google) { '8.8.8.8', '8.8.4.4' } else { '1.1.1.1', '1.0.0.1' }
    foreach ($nic in $nics) {
        $cur = Get-ActiveDnsServers $nic
        if (-not (Get-DnsBackup $nic.Id)) { Set-DnsBackup $nic.Id ($cur) }
        $proc = Start-Process -FilePath netsh.exe -ArgumentList @(
            'interface', 'ipv4', 'set', 'dnsservers', "name=`"$($nic.Name)`"", 'static', $primary, 'primary'
        ) -PassThru -WindowStyle Hidden -EA 0
        $null = Start-Process -FilePath netsh.exe -ArgumentList @(
            'interface', 'ipv4', 'add', 'dnsservers', "name=`"$($nic.Name)`"", $secondary, 'index=2'
        ) -WindowStyle Hidden -EA 0
        $applied++
    }
    if ($applied -eq 0) { return (T 'No hay adaptadores activos donde aplicar el DNS.' 'No active adapters found to set DNS on.') }
    Clear-DnsClientCache -EA 0
    $who = if ($google) { 'Google (8.8.8.8 / 8.8.4.4)' } else { 'Cloudflare (1.1.1.1 / 1.0.0.1)' }
    Write-TempLog "DNS -> $who ($applied adaptadores)."
    return (T "DNS $who aplicado a $applied adaptador(es). El DNS anterior quedó respaldado: usa 'Restaurar DNS automático' para volver." "DNS $who applied to $applied adapter(s). Previous DNS was backed up: use 'Restore automatic DNS' to go back.")
}

function Restore-DnsAuto {
    $nics = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() |
        Where-Object { $_.OperationalStatus -eq 'Up' -and ($_.NetworkInterfaceType -ne [System.Net.NetworkInformation.NetworkInterfaceType]::Loopback) }
    $restored = 0
    foreach ($nic in $nics) {
        $bak = Get-DnsBackup $nic.Id
        if ($bak) {
            $servers = @($bak -split ',' | Where-Object { $_ })
            for ($i = 0; $i -lt [Math]::Min($servers.Count, 2); $i++) {
                $verb = if ($i -eq 0) { 'set' } else { 'add' }
                $idx = if ($i -eq 0) { 'primary' } else { 'index=2' }
                $null = Start-Process -FilePath netsh.exe -ArgumentList @(
                    'interface', 'ipv4', $verb, 'dnsservers', "name=`"$($nic.Name)`"", $servers[$i], $idx
                ) -WindowStyle Hidden -EA 0
            }
        } else {
            $null = Start-Process -FilePath netsh.exe -ArgumentList @(
                'interface', 'ipv4', 'set', 'dnsservers', "name=`"$($nic.Name)`"", 'dhcp'
            ) -WindowStyle Hidden -EA 0
        }
        $restored++
    }
    Remove-Reg 'HKLM:\SOFTWARE\OptiLite\DnsBackup' 'CLEARED'
    foreach ($p in (Get-ItemProperty -Path 'HKLM:\SOFTWARE\OptiLite\DnsBackup' -EA 0).PSObject.Properties) {
        if ($p.Name -notmatch '^PS') { Remove-Reg 'HKLM:\SOFTWARE\OptiLite\DnsBackup' $p.Name }
    }
    Clear-DnsClientCache -EA 0
    Write-TempLog "DNS restaurado ($restored adaptadores)."
    return (T "DNS restaurado en $restored adaptador(es) al valor anterior/automático." "DNS restored on $restored adapter(s) to previous/automatic value.")
}

# ---------------- Debloat de navegadores (Edge / Brave / Firefox) -----------
# Enfoque: NO se desinstala nada. Se aplican POLÍTICAS de registro que
# desactivan telemetría, planes/features de fondo y anuncios del navegador.
# "OFF" (predeterminado de Windows) elimina las políticas de OptiLite.
function Remove-PolicyTree([string]$path) {
    if (Test-Path $path) { Remove-Item -Path $path -Recurse -Force -EA 0 }
}

# ---- Edge (HKLM\SOFTWARE\Policies\Microsoft\Edge) ----
function Set-EdgeDebloat([bool]$on) {
    $p = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
    if ($on) {
        Set-Reg $p 'EdgeShoppingAssistantEnabled' 0                # compras/bing shopping
        Set-Reg $p 'PersonalizationReportingEnabled' 0             # personalización
        Set-Reg $p 'SpotlightExperiencesAndRewardsEnabled' 0        # fondos/spotlight
        Set-Reg $p 'ShowMicrosoftRewardsPromotion' 0                # promos rewards
        Set-Reg $p 'ShowRecommendationsEnabled' 0                   # recomendaciones
        Set-Reg $p 'HubsSidebarEnabled' 0                           # barra lateral (copilot/hub)
        Set-Reg $p 'BackgroundModeEnabled' 0                        # correr en 2do plano
        Set-Reg $p 'ComponentUpdatesEnabled' 0                      # experimentos remotos
        Set-Reg $p 'DefaultBrowserSettingEnabled' 0                # no insistir en default
        Set-Reg $p 'NewSmartScreenLibraryEnabled' 0                 # experimento smart screen
        Set-Reg $p 'SyncDisabled' 1                                 # sync MS account
        Set-Reg $p 'MetricsReportingEnabled' 0                      # telemetría
        Set-Reg $p 'SearchSuggestEnabled' 0                         # sugerencias a bing
        Set-Reg $p 'DefaultSearchProviderSearchURL' 'https://www.google.com/search?q={searchTerms'   # no forzar bing
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Edge\Recommended' 'MetricsReportingEnabled' 0
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Edge' 'StartupBoostEnabled' 0
    } else {
        Remove-PolicyTree $p
        Remove-PolicyTree 'HKCU:\SOFTWARE\Microsoft\Edge\Recommended'
        Set-Reg 'HKCU:\SOFTWARE\Microsoft\Edge' 'StartupBoostEnabled' 1
    }
    return $true
}
function Get-EdgeDebloat {
    $v = Get-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'HubsSidebarEnabled'
    if ($null -eq $v) { return $false }
    return ($v -eq 0)
}

# ---- Brave (HKCU\Software\Policies\BraveSoftware\Brave) ----
function Set-BraveDebloat([bool]$on) {
    $p = 'HKCU:\Software\Policies\BraveSoftware\Brave'
    if ($on) {
        Set-Reg $p 'BraveRewardsDisabled' 1
        Set-Reg $p 'BraveWalletDisabled' 1
        Set-Reg $p 'BraveVPNDisabled' 1
        Set-Reg $p 'BraveAIChatEnabled' 0
        Set-Reg $p 'TorDisabled' 1
        Set-Reg $p 'BraveNewsDisabled' 1
        Set-Reg $p 'StatsReportingDisabled' 1                       # P3A telemetría
        Set-Reg $p 'MetricsReportingDisabled' 1
    } else {
        Remove-PolicyTree $p
    }
    return $true
}
function Get-BraveDebloat {
    $v = Get-Reg 'HKCU:\Software\Policies\BraveSoftware\Brave' 'StatsReportingDisabled'
    if ($null -eq $v) { return $false }
    return ($v -eq 1)
}

# ---- Firefox (HKLM\SOFTWARE\Policies\Mozilla\Firefox, HKCU\...\Firefox) ----
function Set-FirefoxDebloat([bool]$on) {
    $pL = 'HKLM:\SOFTWARE\Policies\Mozilla\Firefox'
    $pU = 'HKCU:\SOFTWARE\Policies\Mozilla\Firefox'
    if ($on) {
        foreach ($p in @($pL, $pU)) {
            Set-Reg $p 'DisableTelemetry' 1
            Set-Reg $p 'DisableFeedbackCommands' 1
            Set-Reg $p 'DisablePocket' 1
            Set-Reg $p 'DisableFirefoxAccounts' 1
            Set-Reg $p 'DisableFirefoxScreenshots' 1
            Set-Reg $p 'DontCheckDefaultBrowser' 1
            Set-Reg $p 'PromptForSubmitURL' 0
            Set-Reg $p 'OverrideFirstRunPage' 'about:blank'
        }
    } else {
        Remove-PolicyTree $pL
        Remove-PolicyTree $pU
    }
    return $true
}
function Get-FirefoxDebloat {
    $v = Get-Reg 'HKCU:\SOFTWARE\Policies\Mozilla\Firefox' 'DisableTelemetry'
    if ($null -eq $v) { return $false }
    return ($v -eq 1)
}

# ---------------- Paneles clásicos de Windows (estilo WinUtil) --------------
# WinUtil crea accesos a las herramientas clásicas {GUID} de control panel
# shell::: ; aquí generamos los mismos accesos en el escritorio (uno por uno
# o el "Panel clásico" que los agrupa). Nada se descarga: son GUID del shell.
$script:ClassicPanels = @(
    @{ Id='god';     Name='God Mode'                  ; Guid='{ED7BA470-8E54-465E-825C-99712043E43C}'
       Desc=@{ES='Panel maestro con ~50 categorías del Panel de control clásico.'
              EN='Master panel with ~50 classic Control Panel categories.'} }
    @{ Id='legacycp'; Name='Panel de control clásico' ; Guid='{26EE0668-A00A-44D7-9371-BEB064C98683}'
       Desc=@{ES='El panel de control clásico (vista por categorías, como en Win7).'
              EN='The classic Control Panel (category view, like Win7).'} }
    @{ Id='admintools'; Name='Herramientas administrativas' ; Guid='{D20EA4E1-3957-11D2-A40B-0C5020524153}'
       Desc=@{ES='Servicios, directivas, visor de eventos, administrador de discos...'
              EN='Services, policies, Event Viewer, Disk Management...'} }
    @{ Id='network'; Name='Conexiones de red clásicas' ; Guid='{7007ACC7-3202-11D2-A610-1DA443E6BF87}'
       Desc=@{ES='La vista clásica de adaptadores y conexiones de red.'
              EN='Classic view of network adapters and connections.'} }
    @{ Id='printers'; Name='Dispositivos e impresoras clásicos' ; Guid='{2227A280-3AEA-1069-A2DE-08002B30309D}'
       Desc=@{ES='La ventana clásica de impresoras y dispositivos.'
              EN='Classic Printers and Devices window.'} }
    @{ Id='defaultgp'; Name='Configuración predeterminada clásica' ; Guid='{17CD9488-1228-4D2F-883F-DA0531E8BECA}'
       Desc=@{ES='Asociaciones de archivos y apps predeterminadas clásicas.'
              EN='Classic default apps and file associations.'} }
    @{ Id='users';    Name='Cuentas de usuario clásicas' ; Guid='{60632754-C523-425F-8F5C-C2A9AC2E49D4}'
       Desc=@{ES='Panel clásico de cuentas de usuario (netplwiz).'
              EN='Classic user accounts panel (netplwiz).'} }
    @{ Id='tasksch';  Name='Programador de tareas clásico' ; Guid='{D6277990-4C6A-11CF-8D87-00AA0060F5BF}'
       Desc=@{ES='Vista clásica del Programador de tareas.'
              EN='Classic Task Scheduler view.'} }
)

function New-ClassicShortcut([string]$name, [string]$guid) {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $scPath = Join-Path $desktop "$name.lnk"
    $wsh = New-Object -ComObject WScript.Shell
    $sc = $wsh.CreateShortcut($scPath)
    $sc.TargetPath = '%SystemRoot%\explorer.exe'
    $sc.Arguments = "shell:::$guid"
    $sc.IconLocation = '%SystemRoot%\System32\imageres.dll,-1023'
    $sc.Description = 'OptiLite - ' + $name
    $sc.Save()
    return $scPath
}

function New-ClassicControlFolder {
    # Crea una carpeta "Panel clasico" en el escritorio con todos los paneles.
    $desktop = [Environment]::GetFolderPath('Desktop')
    $folderName = T 'Panel clásico' 'Classic Panel'
    $dir = Join-Path $desktop $folderName
    if (Test-Path $dir) {
        Get-ChildItem -Path $dir -Filter '*.lnk' | Remove-Item -Force -EA 0
    } else {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }
    $wsh = New-Object -ComObject WScript.Shell
    foreach ($p in $script:ClassicPanels) {
        $nm = $p.Name
        $scPath = Join-Path $dir "$nm.lnk"
        $sc = $wsh.CreateShortcut($scPath)
        $sc.TargetPath = '%SystemRoot%\explorer.exe'
        $sc.Arguments = "shell:::$($p.Guid)"
        $sc.IconLocation = '%SystemRoot%\System32\imageres.dll,-1023'
        $sc.Description = 'OptiLite - ' + $nm
        $sc.Save()
    }
    return $dir
}

# ---------------- Menú contextual clásico de Win11 ----------------------------
function Get-ClassicMenuOn {
    $v = Get-Reg 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' '(Default)'
    if ($null -eq $v -and (Test-Path 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32')) { return $true }
    return $false
}

function Set-ClassicMenu([bool]$on) {
    $k = 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32'
    if ($on) {
        if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
        Set-ItemProperty -Path $k -Name '(Default)' -Value '' -EA 0
    } else {
        Remove-Item -Path $k -Recurse -Force -EA 0
    }
    # reinicio de explorer para aplicarlo al momento
    Stop-Process -Name explorer -Force -EA 0
    return $true
}

# ============================================================================
#  FUNCIONES HEREDADAS DE v1.1 (probadas) — servicios específicos, limpieza,
#  energía, punto de restauración, pila de deshacer, export/import, inicio
# ============================================================================
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
        }
    } else {
        $vanguard = Get-ItemProperty -Path $runKey -Name 'Riot Vanguard' -EA 0
        if ($vanguard) {
            Set-ItemProperty -Path $bakKey -Name 'RiotVanguardRun' -Value $vanguard.'Riot Vanguard' -EA 0
            Remove-ItemProperty -Path $runKey -Name 'Riot Vanguard' -EA 0
        }
        Set-ServiceMode 'vgk' 4 $true $false | Out-Null
        Set-ServiceMode 'vgc' 4 $true $false | Out-Null
    }
}

function Set-FaceitState([bool]$enable) {
    $a = Get-ServiceStartMode 'FACEIT'
    $b = Get-ServiceStartMode 'FACEITService'
    if ($a -eq -1 -and $b -eq -1) { return }
    if ($enable) {
        Set-ServiceMode 'FACEIT' 3 $false $true | Out-Null
        Set-ServiceMode 'FACEITService' 3 $false $true | Out-Null
    } else {
        Set-ServiceMode 'FACEIT' 4 $true $false | Out-Null
        Set-ServiceMode 'FACEITService' 4 $true $false | Out-Null
    }
}

function Set-XboxState([bool]$enable) {
    $svcs = @('XblAuthManager','XblGameSave','XboxGipSvc','XboxNetApiSvc','GamingServices','GamingServicesRuntime')
    foreach ($s in $svcs) {
        if ($enable) { Set-ServiceMode $s 3 $false $false | Out-Null } else { Set-ServiceMode $s 4 $true $false | Out-Null }
    }
}

function Set-AudioDawState([bool]$enable) {
    $p = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
    if ($enable) {
        Set-Reg $p 'SystemResponsiveness' 10
        Set-Reg $p 'NoLazyMode' 1
    } else {
        Set-Reg $p 'SystemResponsiveness' 0
        Set-Reg $p 'NoLazyMode' 0
    }
}

function Set-VbsState([bool]$enable) {
    if ($enable) { Remove-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'EnableVirtualizationBasedSecurity' }
    else { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard' 'EnableVirtualizationBasedSecurity' 0 }
}

# ---------------- Red avanzada (heredado v1.1) -------------------------------
function Set-NagleState([bool]$enable) {
    $nics = Get-NetAdapter -EA 0 | Where-Object { $_.Status -eq 'Up' }
    if (-not $nics) { $nics = @(Get-Item 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\*' -EA 0) }
    foreach ($nic in $nics) {
        $key = $nic | Get-ItemProperty -EA 0
        $ipKey = $nic.PSPath
        if (-not $ipKey) { $ipKey = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$($nic.PSChildName)" }
        Set-Reg $ipKey 'TcpAckFrequency' $(if ($enable) { 1 } else { 0 }) 'DWord' | Out-Null
        Set-Reg $ipKey 'TCPNoDelay' $(if ($enable) { 1 } else { 0 }) 'DWord' | Out-Null
    }
}

function Get-NagleEnabled {
    $vals = @(Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces' -EA 0 | ForEach-Object {
        (Get-ItemProperty -Path $_.PSPath -Name 'TcpAckFrequency' -EA 0).TcpAckFrequency })
    if ($vals.Count -eq 0) { return $false }
    return ($vals -notcontains 1)
}

function Get-TcpAutotuningOn {
    # netsh en español no dice "Auto-Tuning"; se consulta el nivel real al
    # SDK: devuelto por Get-NetTCPSetting cuando está disponible (WIN8+) y
    # como fallback el texto de netsh en cualquier idioma.
    try {
        $s = Get-NetTCPSetting -EA 0 | Select-Object -First 1
        if ($s -and $s.AutoTimingLevel -ne $null) { return ($s.AutoTimingLevel -eq 0) }
    } catch {}
    try {
        $line = (netsh.exe interface tcp show global) | Select-String 'Auto-Tuning' | Out-String
        return ($line -match 'normal')
    } catch { return $true }
}

function Set-TcpAutotuning([bool]$enable) {
    if ($enable) { netsh.exe interface tcp set global autotuning=normal | Out-Null }
    else { netsh.exe interface tcp set global autotuning=disabled | Out-Null }
}

# ---------------- Acciones de limpieza y mantenimiento -----------------------
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
#  DEFINICION DE AJUSTES v2.0 (motor data-driven, estilo WinUtil/WinHance)
#  Cada item:  Id, Cat, Grp (ES/EN), Name/Desc (ES/EN — Desc se muestra como
#  TOOLTIP al pasar el mouse: interfaz limpia), Reboot, Get (estado actual),
#  Set (aplica $true/$false).  $null en Get = "no instalado" (interruptor gris).
#  Categorías: Perf | Games | Priv | Net | Browsers | Panels
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

    @{ Id='endure'; Cat='Perf'; Grp=@{ES='Seguridad y servicios';EN='Security & services'}; Reboot=$false
       Name=@{ES='Endurecimiento de seguridad (SMBv1, LLMNR)';EN='Security hardening (SMBv1, LLMNR)'}
       Desc=@{ES='ON desactiva SMBv1 y LLMNR (protocolos viejos usados en ataques de red local) y bloquea el asistente de búsqueda de impresoras por mDNS. Reversible.'
              EN='ON disables SMBv1 and LLMNR (legacy protocols used in LAN attacks) and blocks mDNS printer discovery. Reversible.'}
       Get={ (Get-Reg 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' 'SMB1') -eq 0 -and (Get-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\NetworkConnectivityStatusIndicator' 'NoMulticast') -eq 1 }
       Set={ param($on) if ($on) { Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' 'SMB1' 0; Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\NetworkConnectivityStatusIndicator' 'NoMulticast' 1; Disable-NetAdapterBinding -Name '*' -ComponentID ms_mDNS -EA 0 | Out-Null } else { Remove-Reg 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' 'SMB1'; Remove-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\NetworkConnectivityStatusIndicator' 'NoMulticast'; Enable-NetAdapterBinding -Name '*' -ComponentID ms_mDNS -EA 0 | Out-Null } } }

    @{ Id='telemetrytasks'; Cat='Perf'; Grp=@{ES='Seguridad y servicios';EN='Security & services'}; Reboot=$false
       Name=@{ES='Tareas programadas de telemetría';EN='Telemetry scheduled tasks'}
       Desc=@{ES='ON deshabilita las tareas de Consolidator, KernelCeipTask, UsbCeip y compatible telemetry (Microsoft Compatibility Appraiser). Ahoran CPU y disco en segundo plano.'
              EN='ON disables Consolidator, KernelCeipTask, UsbCeip and compatible telemetry tasks (Microsoft Compatibility Appraiser). Saves background CPU and disk.'}
       Get={ Get-TelemetryTasksDisabled }
       Set={ param($on) Set-TelemetryTasksDisabled $on } }

    # ---------------- RED (DNS / Nagle / autotuning) -------------------------
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

    # ---------------- DNS: Google / Cloudflare (panel Red) ------------------
    @{ Id='dnsg'; Cat='Net'; Grp=@{ES='DNS';EN='DNS'}; Reboot=$false
       Name=@{ES='DNS de Google (8.8.8.8 / 8.8.4.4)';EN='Google DNS (8.8.8.8 / 8.8.4.4)'}
       Desc=@{ES='Aplica el DNS público de Google a todos los adaptadores activos. El DNS anterior queda respaldado para restaurarlo. Filtrado de contenido: ninguno; registro: sí.'
              EN='Applies Google public DNS to every active adapter. The previous DNS is backed up for restore. Content filtering: none; logging: yes.'}
       Get={ (Get-DnsProvider) -eq $true }
       Set={ param($on) if ($on) { Set-DnsProvider $true | Out-Null } else { Restore-DnsAuto | Out-Null } } }

    @{ Id='dnsc'; Cat='Net'; Grp=@{ES='DNS';EN='DNS'}; Reboot=$false
       Name=@{ES='DNS de Cloudflare (1.1.1.1 / 1.0.0.1)';EN='Cloudflare DNS (1.1.1.1 / 1.0.0.1)'}
       Desc=@{ES='Aplica el DNS público de Cloudflare. El anterior queda respaldado. Filtrado de malware: 1.1.1.2 disponible manualmente; privacidad: mejor que Google.'
              EN='Applies Cloudflare public DNS. Previous DNS is backed up. Malware filtering: 1.1.1.2 available manually; privacy: better than Google.'}
       Get={ (Get-DnsProvider) -eq $false }
       Set={ param($on) if ($on) { Set-DnsProvider $false | Out-Null } else { Restore-DnsAuto | Out-Null } } }

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

    @{ Id='copilot'; Cat='Priv'; Grp=@{ES='Personalización y anuncios';EN='Personalization & ads'}; Reboot=$false
       Name=@{ES='Copilot y Bing en Windows';EN='Copilot and Bing in Windows'}
       Desc=@{ES='ON desactiva Copilot/ Bing Chat, su entrada en el Edge sidebar y el botón del teclado (dónde exista). No borra nada: se reactiva igual.'
              EN='ON disables Copilot/Bing Chat, its Edge sidebar entry and the keyboard button (where present). Deletes nothing: re-enables the same way.'}
       Get={ (Get-Reg 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot') -eq 1 }
       Set={ param($on) $v = if ($on) { 1 } else { 0 }; Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' $v; Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' $v; Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' 'AllowCopilotBingChat' $v } }

    @{ Id='bings'; Cat='Priv'; Grp=@{ES='Personalización y anuncios';EN='Personalization & ads'}; Reboot=$false
       Name=@{ES='Búsqueda web de Bing en el menú Inicio';EN='Bing web search in the Start menu'}
       Desc=@{ES='Los resultados de búsqueda del menú Inicio solo listan apps locales; sin llamada a Bing desde el Inicio. No afecta a Edge.'
              EN='Start menu search results list local apps only; no Bing call from Start. Does not affect Edge.'}
       Get={ (Get-Reg 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions') -eq 1 }
       Set={ param($on) Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' $(if($on){1}else{0}) } }

    @{ Id='widgets'; Cat='Priv'; Grp=@{ES='Personalización y anuncios';EN='Personalization & ads'}; Reboot=$false
       Name=@{ES='Widgets y contenido de la pantalla de bloqueo';EN='Widgets and lock screen content'}
       Desc=@{ES='ON quita el tablero de Widgets del Inicio/Win+W y el fondo/feed de la pantalla de bloqueo (noticias, clima). Reversible.'
              EN='ON removes the Widgets board from Start/Win+W and the lock screen background/feed (news, weather). Reversible.'}
       Get={ (Get-Reg 'HKCU:\Software\Policies\Microsoft\Dsh' 'AllowNewsAndInterests') -eq 0 }
       Set={ param($on) $v = if ($on) { 0 } else { 1 }; Set-Reg 'HKCU:\Software\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' $v; Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' $v } }

    @{ Id='lockscr'; Cat='Priv'; Grp=@{ES='Personalización y anuncios';EN='Personalization & ads'}; Reboot=$false
       Name=@{ES='Contenido destacado en pantalla de bloqueo';EN='Spotlight content on the lock screen'}
       Desc=@{ES='Noticias, consejos y datos en la pantalla de bloqueo. OFF = imagen fija. Reversible.'
              EN='News, tips and data on the lock screen. OFF = plain picture. Reversible.'}
       Get={ (Get-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lock Screen' 'RotatingLockScreenOverlayEnabled') -ne 0 }
       Set={ param($on) Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lock Screen' 'RotatingLockScreenOverlayEnabled' $(if($on){0}else{1}) } }

    # ---------------------------- NAVEGADORES (debloat) ----------------------
    @{ Id='edgedb'; Cat='Browsers'; Grp=@{ES='Microsoft Edge';EN='Microsoft Edge'}; Reboot=$false
       Name=@{ES='Debloat de Edge';EN='Edge debloat'}
       Desc=@{ES='Políticas locales que desactivan telemetría, sidebar/Hub, shopping, sync forzado, arranque rápido y procesos en 2do plano de Edge. No desinstala el navegador; reversible.'
              EN='Local policies disabling Edge telemetry, sidebar/hub, shopping, forced sync, startup boost and background processes. Does not uninstall the browser; reversible.'}
       Get={ Get-EdgeDebloat }
       Set={ param($on) Set-EdgeDebloat $on | Out-Null } }

    @{ Id='bravedb'; Cat='Browsers'; Grp=@{ES='Brave';EN='Brave'}; Reboot=$false
       Name=@{ES='Debloat de Brave';EN='Brave debloat'}
       Desc=@{ES='Desactiva Rewards, Wallet, VPN, Leo AI, Brave News, Tor rápido y la telemetría P3A. Solo actúa si Brave está instalado; no lo borra.'
              EN='Disables Rewards, Wallet, VPN, Leo AI, Brave News, quick Tor and P3A telemetry. Only applies if Brave is installed; does not remove it.'}
       Get={ $v = Get-BraveDebloat; if ((Test-Path "$env:LOCALAPPDATA\BraveSoftware") -or (Test-Path 'C:\Program Files\BraveSoftware')) { $v } else { $null } }
       Set={ param($on) Set-BraveDebloat $on | Out-Null } }

    @{ Id='firefoxdb'; Cat='Browsers'; Grp=@{ES='Mozilla Firefox';EN='Mozilla Firefox'}; Reboot=$false
       Name=@{ES='Debloat de Firefox';EN='Firefox debloat'}
       Desc=@{ES='Políticas oficiales de Mozilla: sin telemetría, sin Pocket, sin capturas integradas, sin primera página promocional. No borra nada.'
              EN='Official Mozilla policies: no telemetry, no Pocket, no built-in screenshots, no promotional first run. Deletes nothing.'}
       Get={ $v = Get-FirefoxDebloat; if ((Test-Path 'C:\Program Files\Mozilla Firefox') -or (Test-Path "$env:LOCALAPPDATA\Mozilla Firefox")) { $v } else { $null } }
       Set={ param($on) Set-FirefoxDebloat $on | Out-Null } }

    # --------------------- PANELES CLÁSICOS / MENÚ WIN11 --------------------
    @{ Id='classicmenu'; Cat='Panels'; Grp=@{ES='Menú y paneles clásicos';EN='Classic menu and panels'}; Reboot=$false
       Name=@{ES='Menú contextual clásico (Win11)';EN='Classic context menu (Win11)'}
       Desc=@{ES='ON restaura el menú de clic derecho de Windows 10 (completo, sin "Mostrar más opciones"). Reinicia Explorer al momento; reversible.'
              EN='ON restores the Windows 10 right-click menu (full, no "Show more options"). Restarts Explorer instantly; reversible.'}
       Get={ Get-ClassicMenuOn }
       Set={ param($on) Set-ClassicMenu $on | Out-Null } }
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
    @{ Id='dnsflush'; Cat='Clean'; Grp=@{ES='Archivos y caché';EN='Files & cache'}; Name=@{ES='Vaciar caché DNS';EN='Flush DNS cache'}; Btn=@{ES='Vaciar';EN='Flush'}
       Desc=@{ES='Útil tras cambiar de red o DNS: obliga a resolver nombres de nuevo.'
              EN='Useful after changing network or DNS: forces name resolution again.'}
       Run={ Clear-DnsClientCache -EA 0; T 'Caché DNS vaciada.' 'DNS cache flushed.' } }
    @{ Id='plan';   Cat='Perf';  Grp=@{ES='Energía';EN='Power'}; Name=@{ES='Plan de energía Gaming Ultimate';EN='Gaming Ultimate power plan'}; Btn=@{ES='Activar';EN='Activate'}
       Desc=@{ES='Duplica el plan Ultimate Performance, desactiva Core Parking y pone min. CPU al 100% (enchufado).'
              EN='Duplicates Ultimate Performance, disables Core Parking and sets min. CPU at 100% (on AC).'}
       Run={ Ensure-GamingPowerPlan; T 'Plan Gaming Ultimate Performance activo (Core Parking 0%).' 'Gaming Ultimate Performance plan active (Core Parking 0%).' } }

    @{ Id='dnsreset'; Cat='Net'; Grp=@{ES='DNS';EN='DNS'}; Name=@{ES='Restaurar DNS automático';EN='Restore automatic DNS'}; Btn=@{ES='Restaurar';EN='Restore'}
       Desc=@{ES='Devuelve cada adaptador al DNS anterior (respaldado al aplicar Google/Cloudflare) o a DHCP automático si no había respaldo.'
              EN='Returns each adapter to its previous DNS (backed up when Google/Cloudflare was applied) or to automatic DHCP if none was stored.'}
       Run={ Restore-DnsAuto } }

    @{ Id='legacypanel'; Cat='Panels'; Grp=@{ES='Paneles clásicos';EN='Classic panels'}; Name=@{ES='Carpeta "Panel clásico" en el Escritorio';EN='"Classic Panel" folder on the Desktop'}; Btn=@{ES='Crear';EN='Create'}
       Desc=@{ES='Crea una carpeta en el Escritorio con accesos a los 8 paneles clásicos (God Mode, Panel de control clásico, Herramientas administrativas, Red, Impresoras, Apps predeterminadas, Cuentas y Programador de tareas).'
              EN='Creates a Desktop folder with shortcuts to the 8 classic panels (God Mode, classic Control Panel, Administrative Tools, Network, Printers, Default Apps, User Accounts and Task Scheduler).'}
       Run={ $d = New-ClassicControlFolder; T "Carpeta creada: $d (8 paneles clásicos)." "Folder created: $d (8 classic panels)." } }
    @{ Id='godmode'; Cat='Panels'; Grp=@{ES='Paneles clásicos';EN='Classic panels'}; Name=@{ES='Acceso directo "God Mode"';EN='"God Mode" shortcut'}; Btn=@{ES='Crear';EN='Create'}
       Desc=@{ES='El panel maestro clásico: ~50 categorías de todas las herramientas de configuración de Windows en una sola ventana.'
              EN='The classic master panel: ~50 categories with every Windows configuration tool in a single window.'}
       Run={ $p = New-ClassicShortcut 'God Mode' '{ED7BA470-8E54-465E-825C-99712043E43C}'; T "Acceso 'God Mode' creado en el Escritorio." "'God Mode' shortcut created on the Desktop." } }

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
       Desc=@{ES='Devuelve TODOS los ajustes a valores por defecto de Windows (telemetría, efectos, servicios, DVR, ratón, DNS y menú Win11...). Los anti-cheats no se tocan.'
              EN='Returns ALL settings to Windows defaults (telemetry, effects, services, DVR, mouse, DNS and Win11 menu...). Anti-cheats are untouched.'}
       States=@{ vbs=$true; fx=$false; sysmain=$true; wsearch=$true; hiber=$true; bgapps=$true; net=$true; autotcp=$true; nagle=$true; xbox=$true; gamemode=$true; dvr=$true; fso=$true; ptr=$true; mpo=$true; daw=$false; tele=$true; diag=$true; act=$true; adid=$true; sugg=$true; ink=$true; fb=$true; lang=$true; copilot=$false; bings=$false; widgets=$false; lockscr=$false; dnsg=$false; dnsc=$false; classicmenu=$false; edgedb=$false; bravedb=$false; firefoxdb=$false; endure=$false; telemetrytasks=$false } }
)

# ============================================================================
#  INTERFAZ (WPF) - sidebar + tarjetas + tooltips al pasar el mouse
#  El XAML usa recursos con nombre en vez de colores fijos: el tema
#  claro/oscuro se re-aplica en vivo cambiando esos recursos (sin recargar
#  la ventana ni perder la pestaña activa).
# ============================================================================
$xamlText = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="OptiLite v2.0.0 · Optimizador de Windows 10/11"
        Height="700" Width="1020" MinHeight="640" MinWidth="900"
        WindowStartupLocation="CenterScreen"
        Background="{DynamicResource ResWinBg}" FontFamily="Segoe UI">
    <Window.Resources>
        <!-- Colores base (se redefinen al cambiar tema; -1 valores iniciales) -->
        <SolidColorBrush x:Key="ResWinBg" Color="#0B0E14"/>
        <SolidColorBrush x:Key="ResSidebar" Color="#0D1118"/>
        <SolidColorBrush x:Key="ResCard" Color="#12161F"/>
        <SolidColorBrush x:Key="ResChip" Color="#131926"/>
        <SolidColorBrush x:Key="ResBorder" Color="#1B2333"/>
        <SolidColorBrush x:Key="ResBorderSoft" Color="#1E2735"/>
        <SolidColorBrush x:Key="ResChipB" Color="#253048"/>
        <SolidColorBrush x:Key="ResTitle" Color="#F1F5F9"/>
        <SolidColorBrush x:Key="ResSub" Color="#7C8AA0"/>
        <SolidColorBrush x:Key="ResText" Color="#E2E8F0"/>
        <SolidColorBrush x:Key="ResMuted" Color="#8FA0B8"/>
        <SolidColorBrush x:Key="ResDim" Color="#8B99AE"/>
        <SolidColorBrush x:Key="ResAccent" Color="#38BDF8"/>
        <SolidColorBrush x:Key="ResOk" Color="#6EE7B7"/>
        <SolidColorBrush x:Key="ResWarn" Color="#FCD34D"/>
        <SolidColorBrush x:Key="ResWarnB" Color="#D97706"/>
        <SolidColorBrush x:Key="ResErr" Color="#F87171"/>
        <SolidColorBrush x:Key="ResBtnBg" Color="#1C2431"/>
        <SolidColorBrush x:Key="ResBtnB" Color="#2C3A50"/>
        <SolidColorBrush x:Key="ResTrack" Color="#232B3A"/>
        <SolidColorBrush x:Key="ResTrackB" Color="#33405A"/>
        <SolidColorBrush x:Key="ResThumb" Color="#94A3B8"/>
        <SolidColorBrush x:Key="ResStatusBg" Color="#141821"/>
        <SolidColorBrush x:Key="ResStatusB" Color="#252B38"/>
        <SolidColorBrush x:Key="ResStatusFg" Color="#CBD5E1"/>
        <SolidColorBrush x:Key="ResSection" Color="#0F141D"/>
        <SolidColorBrush x:Key="ResScrollBg" Color="#10141D"/>
        <SolidColorBrush x:Key="ResScrollFg" Color="#2A3547"/>
        <SolidColorBrush x:Key="ResNavIdle" Color="#9AA6B8"/>
        <SolidColorBrush x:Key="ResNavHover" Color="#141B27"/>
        <SolidColorBrush x:Key="ResNavSelBg" Color="#182536"/>
        <SolidColorBrush x:Key="ResNavSelFg" Color="#7DD3FC"/>
        <SolidColorBrush x:Key="ResWhite" Color="#FFFFFF"/>

        <!-- Tooltip estilo OptiLite (no el default de Windows) -->
        <Style x:Key="TipStyle" TargetType="ToolTip">
            <Setter Property="Foreground" Value="{DynamicResource ResText}"/>
            <Setter Property="Background" Value="{DynamicResource ResCard}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource ResAccent}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="11,8"/>
            <Setter Property="FontSize" Value="11"/>
            <Setter Property="MaxWidth" Value="420"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ToolTip">
                        <Border Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="8" Padding="{TemplateBinding Padding}"
                                SnapsToDevicePixels="True">
                            <StackPanel>
                                <TextBlock x:Name="TipTitle" FontSize="11.5" FontWeight="Bold"
                                           Foreground="{DynamicResource ResAccent}"
                                           Text="{Binding Tag, RelativeSource={RelativeSource TemplatedParent}}"/>
                                <TextBlock x:Name="TipBody" FontSize="11" TextWrapping="Wrap"
                                           Foreground="{TemplateBinding Foreground}"
                                           Margin="0,4,0,0" Text="{Binding Content, RelativeSource={RelativeSource TemplatedParent}}"/>
                            </StackPanel>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="CardStyle" TargetType="Border">
            <Setter Property="Background" Value="{DynamicResource ResCard}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource ResBorderSoft}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="CornerRadius" Value="10"/>
            <Setter Property="Padding" Value="14,12"/>
            <Setter Property="Margin" Value="0,0,0,10"/>
        </Style>
        <Style x:Key="GrpHeader" TargetType="TextBlock">
            <Setter Property="Foreground" Value="{DynamicResource ResMuted}"/>
            <Setter Property="FontSize" Value="10.5"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="Margin" Value="2,2,0,8"/>
        </Style>
        <Style x:Key="ChipBorder" TargetType="Border">
            <Setter Property="Background" Value="{DynamicResource ResChip}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource ResChipB}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="CornerRadius" Value="6"/>
            <Setter Property="Padding" Value="9,4"/>
        </Style>
        <Style x:Key="BtnStyle" TargetType="Button">
            <Setter Property="Foreground" Value="{DynamicResource ResText}"/>
            <Setter Property="Background" Value="{DynamicResource ResBtnBg}"/>
            <Setter Property="BorderBrush" Value="{DynamicResource ResBtnB}"/>
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
            <Setter Property="Foreground" Value="{DynamicResource ResNavIdle}"/>
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
                                <Setter TargetName="nav" Property="Background" Value="{DynamicResource ResNavHover}"/>
                            </Trigger>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="nav" Property="Background" Value="{DynamicResource ResNavSelBg}"/>
                                <Setter Property="Foreground" Value="{DynamicResource ResNavSelFg}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <!-- Interruptor custom (no checkbox de Windows) -->
        <Style x:Key="SwitchStyle" TargetType="CheckBox">
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Focusable" Value="False"/>
            <Setter Property="VerticalAlignment" Value="Center"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="CheckBox">
                        <Border x:Name="track" Width="44" Height="24" CornerRadius="12"
                                Background="{DynamicResource ResTrack}"
                                BorderBrush="{DynamicResource ResTrackB}" BorderThickness="1">
                            <Ellipse x:Name="thumb" Width="16" Height="16" Fill="{DynamicResource ResThumb}"
                                     HorizontalAlignment="Left" Margin="3,0,0,0" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="track" Property="Background" Value="{DynamicResource ResAccent}"/>
                                <Setter TargetName="track" Property="BorderBrush" Value="{DynamicResource ResAccent}"/>
                                <Setter TargetName="thumb" Property="Fill" Value="{DynamicResource ResWhite}"/>
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
        <!-- Botón redondo pequeño para idioma/tema (íconos custom) -->
        <Style x:Key="RoundBtn" TargetType="ToggleButton">
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Focusable" Value="False"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ToggleButton">
                        <Border x:Name="rnd" Width="32" Height="32" CornerRadius="16"
                                Background="{DynamicResource ResChip}"
                                BorderBrush="{DynamicResource ResChipB}" BorderThickness="1">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="rnd" Property="Background" Value="{DynamicResource ResBtnBg}"/>
                                <Setter TargetName="rnd" Property="BorderBrush" Value="{DynamicResource ResAccent}"/>
                            </Trigger>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="rnd" Property="BorderBrush" Value="{DynamicResource ResAccent}"/>
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
        <Border Grid.Column="0" Background="{DynamicResource ResSidebar}" BorderBrush="{DynamicResource ResBorder}" BorderThickness="0,0,1,0">
            <DockPanel>
                <StackPanel DockPanel.Dock="Top" Margin="16,18,14,14">
                    <StackPanel Orientation="Horizontal">
                        <!-- Logo custom: rayo dentro de un óvalo (Path dibujado, no un ícono de Windows) -->
                        <Border Width="26" Height="26" CornerRadius="14"
                                Background="{DynamicResource ResChip}" BorderBrush="{DynamicResource ResAccent}" BorderThickness="1.4"
                                VerticalAlignment="Center" Margin="0,0,8,0">
                            <Path Data="M11.5,4.5 L7.5,13.5 L10.6,13.5 L9.2,21 L14.8,11.2 L11.6,11.2 Z"
                              Fill="{DynamicResource ResAccent}" Stretch="Uniform" Margin="4"
                              VerticalAlignment="Center" HorizontalAlignment="Center"/>
                        </Border>
                        <TextBlock Text="OPTILITE" Foreground="{DynamicResource ResAccent}" FontSize="15" FontWeight="Bold" VerticalAlignment="Center"/>
                    </StackPanel>
                    <StackPanel Orientation="Horizontal" Margin="0,6,0,0">
                        <Border Width="7" Height="7" CornerRadius="4" Background="{DynamicResource ResOk}" VerticalAlignment="Center" Margin="0,0,6,0"/>
                        <TextBlock x:Name="TxtSidebarSub" Text="Optimización local · sin descargas" Foreground="{DynamicResource ResSub}" FontSize="10"/>
                    </StackPanel>
                </StackPanel>

                <Border DockPanel.Dock="Bottom" Background="{DynamicResource ResSection}" BorderBrush="{DynamicResource ResBorder}" BorderThickness="0,1,0,0" Padding="12,10">
                    <StackPanel>
                        <StackPanel Orientation="Horizontal" HorizontalAlignment="Center">
                            <Border Style="{StaticResource ChipBorder}" Margin="0,0,6,0">
                                <TextBlock x:Name="TxtLiveRam" Text="RAM --" Foreground="{DynamicResource ResOk}" FontSize="10.5" FontWeight="SemiBold"/>
                            </Border>
                            <Border Style="{StaticResource ChipBorder}">
                                <TextBlock x:Name="TxtLiveProc" Text="Proc --" Foreground="{DynamicResource ResAccent}" FontSize="10.5" FontWeight="SemiBold"/>
                            </Border>
                        </StackPanel>
                        <Button x:Name="BtnRefreshAll" Content="Refrescar estados" Style="{StaticResource BtnStyle}" Margin="0,8,0,0" FontSize="10.5" Padding="0,5"/>
                        <Border x:Name="BadgePending" Visibility="Collapsed" Background="#2A1F0E" BorderBrush="#D97706" BorderThickness="1" CornerRadius="6" Padding="8,4" Margin="0,8,0,0">
                            <TextBlock x:Name="TxtPendingBadge" Text="Reinicio pendiente" Foreground="{DynamicResource ResWarn}" FontSize="10.5" FontWeight="Bold" HorizontalAlignment="Center"/>
                        </Border>
                    </StackPanel>
                </Border>

                <!-- Navegación con ícono custom por pestaña (Paths minimalistas) -->
                <ScrollViewer VerticalScrollBarVisibility="Hidden" Margin="0,6,0,10">
                    <StackPanel>
                        <ToggleButton x:Name="NavHome" Style="{StaticResource NavBtn}" IsChecked="True">
                            <StackPanel Orientation="Horizontal">
                                <Canvas Width="22" Height="22" VerticalAlignment="Center">
                                    <Path Data="M3,11 L11,4 L19,11" Stroke="{DynamicResource ResAccent}" StrokeThickness="2" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
                                    <Path Data="M5.5,9.5 L5.5,19 L16.5,19 L16.5,9.5" Stroke="{DynamicResource ResAccent}" StrokeThickness="2" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
                                </Canvas>
                                <TextBlock x:Name="NavHomeTxt" Text="Resumen" Margin="9,0,0,0" VerticalAlignment="Center"/>
                            </StackPanel>
                        </ToggleButton>
                        <ToggleButton x:Name="NavPerf" Style="{StaticResource NavBtn}">
                            <StackPanel Orientation="Horizontal">
                                <Canvas Width="22" Height="22" VerticalAlignment="Center">
                                    <Path Data="M3,18 L7,10 L11,14 L15,4 L19,18" Stroke="#F59E0B" StrokeThickness="2" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeDashCap="Round" Fill="{x:Null}"/>
                                </Canvas>
                                <TextBlock x:Name="NavPerfTxt" Text="Rendimiento" Margin="9,0,0,0" VerticalAlignment="Center"/>
                            </StackPanel>
                        </ToggleButton>
                        <ToggleButton x:Name="NavGames" Style="{StaticResource NavBtn}">
                            <StackPanel Orientation="Horizontal">
                                <Canvas Width="22" Height="22" VerticalAlignment="Center">
                                    <Path Data="M5,10 L7.2,10 L8.5,7.5 L13.5,7.5 L14.8,10 L17,10 L18,17 L4,17 Z" Stroke="#8B5CF6" StrokeThickness="1.8" StrokeStartLineCap="Round" StrokeEndLineCap="Round" Fill="{x:Null}"/>
                                    <Ellipse Width="2.6" Height="2.6" Fill="#8B5CF6" Canvas.Left="13" Canvas.Top="12"/>
                                    <Path Data="M7,13.3 L9.6,13.3 M8.3,12 L8.3,14.6" Stroke="#8B5CF6" StrokeThickness="1.5" StrokeStartLineCap="Round"/>
                                </Canvas>
                                <TextBlock x:Name="NavGamesTxt" Text="Juegos" Margin="9,0,0,0" VerticalAlignment="Center"/>
                            </StackPanel>
                        </ToggleButton>
                        <ToggleButton x:Name="NavPriv" Style="{StaticResource NavBtn}">
                            <StackPanel Orientation="Horizontal">
                                <Canvas Width="22" Height="22" VerticalAlignment="Center">
                                    <Path Data="M11,3.5 C7,3.5 4,5.5 4,5.5 L4,11 C4,15.8 11,18.5 11,18.5 C11,18.5 18,15.8 18,11 L18,5.5 C18,5.5 15,3.5 11,3.5 Z" Stroke="#10B981" StrokeThickness="1.8" Fill="{x:Null}" StrokeStartLineCap="Round"/>
                                    <Path Data="M8,10.5 L10.2,12.6 L14.5,8.2" Stroke="#10B981" StrokeThickness="1.8" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
                                </Canvas>
                                <TextBlock x:Name="NavPrivTxt" Text="Privacidad" Margin="9,0,0,0" VerticalAlignment="Center"/>
                            </StackPanel>
                        </ToggleButton>
                        <ToggleButton x:Name="NavNet" Style="{StaticResource NavBtn}">
                            <StackPanel Orientation="Horizontal">
                                <Canvas Width="22" Height="22" VerticalAlignment="Center">
                                    <Ellipse Width="3.4" Height="3.4" Fill="#22D3EE" Canvas.Left="9.3" Canvas.Top="14.5"/>
                                    <Path Data="M6.5,12.5 A6.5,6.5 0 0 1 15.5,12.5" Stroke="#22D3EE" StrokeThickness="1.8" Fill="{x:Null}" StrokeStartLineCap="Round"/>
                                    <Path Data="M3.5,9.5 A10,10 0 0 1 18.5,9.5" Stroke="#22D3EE" StrokeThickness="1.8" Fill="{x:Null}" StrokeStartLineCap="Round"/>
                                </Canvas>
                                <TextBlock x:Name="NavNetTxt" Text="Red y DNS" Margin="9,0,0,0" VerticalAlignment="Center"/>
                            </StackPanel>
                        </ToggleButton>
                        <ToggleButton x:Name="NavClean" Style="{StaticResource NavBtn}">
                            <StackPanel Orientation="Horizontal">
                                <Canvas Width="22" Height="22" VerticalAlignment="Center">
                                    <Path Data="M4.5,6.5 L17.5,6.5 M6,6.5 L6,17.5 L16,17.5 L16,6.5 M8.8,6.5 L8.8,4 L13.2,4 L13.2,6.5 M9.2,9.5 L9.2,14.5 M12.8,9.5 L12.8,14.5" Stroke="#22D3EE" StrokeThickness="1.8" StrokeStartLineCap="Round" StrokeEndLineCap="Round" Fill="{x:Null}"/>
                                </Canvas>
                                <TextBlock x:Name="NavCleanTxt" Text="Limpieza" Margin="9,0,0,0" VerticalAlignment="Center"/>
                            </StackPanel>
                        </ToggleButton>
                        <ToggleButton x:Name="NavBrowsers" Style="{StaticResource NavBtn}">
                            <StackPanel Orientation="Horizontal">
                                <Canvas Width="22" Height="22" VerticalAlignment="Center">
                                    <Ellipse Width="16" Height="16" Stroke="#F472B6" StrokeThickness="1.8" Fill="{x:Null}" Canvas.Left="3" Canvas.Top="3"/>
                                    <Path Data="M3.2,11 L18.8,11 M11,3 C8.2,6.5 8.2,15.5 11,19 M11,3 C13.8,6.5 13.8,15.5 11,19" Stroke="#F472B6" StrokeThickness="1.4" Fill="{x:Null}"/>
                                </Canvas>
                                <TextBlock x:Name="NavBrowsersTxt" Text="Navegadores" Margin="9,0,0,0" VerticalAlignment="Center"/>
                            </StackPanel>
                        </ToggleButton>
                        <ToggleButton x:Name="NavPanels" Style="{StaticResource NavBtn}">
                            <StackPanel Orientation="Horizontal">
                                <Canvas Width="22" Height="22" VerticalAlignment="Center">
                                    <Path Data="M3,6.5 L8.5,6.5 M3,11 L8.5,11 M3,15.5 L8.5,15.5" Stroke="#FB923C" StrokeThickness="1.8" StrokeStartLineCap="Round"/>
                                    <Path Data="M11.5,5 L19,5 L19,17 L11.5,17 Z" Stroke="#FB923C" StrokeThickness="1.8" Fill="{x:Null}"/>
                                </Canvas>
                                <TextBlock x:Name="NavPanelsTxt" Text="Paneles clásicos" Margin="9,0,0,0" VerticalAlignment="Center"/>
                            </StackPanel>
                        </ToggleButton>
                        <ToggleButton x:Name="NavStartup" Style="{StaticResource NavBtn}">
                            <StackPanel Orientation="Horizontal">
                                <Canvas Width="22" Height="22" VerticalAlignment="Center">
                                    <Path Data="M11,7.5 C8,7.5 5.5,10 5.5,10 L3,10 L3,18 L19,18 L19,10 L16.5,10 C16.5,10 14,7.5 11,7.5 Z M11,7.5 L11,4 M8.5,4 L13.5,4" Stroke="#FB923C" StrokeThickness="1.8" Fill="{x:Null}" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
                                </Canvas>
                                <TextBlock x:Name="NavStartupTxt" Text="Inicio" Margin="9,0,0,0" VerticalAlignment="Center"/>
                            </StackPanel>
                        </ToggleButton>
                        <ToggleButton x:Name="NavProfiles" Style="{StaticResource NavBtn}">
                            <StackPanel Orientation="Horizontal">
                                <Canvas Width="22" Height="22" VerticalAlignment="Center">
                                    <Path Data="M11,2.5 L13.6,8.2 L19.8,9 L15.2,13.4 L16.4,19.5 L11,16.5 L5.6,19.5 L6.8,13.4 L2.2,9 L8.4,8.2 Z" Stroke="#F472B6" StrokeThickness="1.6" Fill="{x:Null}" StrokeStartLineCap="Round"/>
                                </Canvas>
                                <TextBlock x:Name="NavProfilesTxt" Text="Perfiles" Margin="9,0,0,0" VerticalAlignment="Center"/>
                            </StackPanel>
                        </ToggleButton>
                    </StackPanel>
                </ScrollViewer>
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
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <StackPanel Grid.Column="0">
                    <TextBlock x:Name="TxtSectionTitle" Text="Resumen" Foreground="{DynamicResource ResTitle}" FontSize="17" FontWeight="Bold"/>
                    <TextBlock x:Name="TxtSectionDesc" Text="Estado del equipo y acciones rápidas" Foreground="{DynamicResource ResSub}" FontSize="11" Margin="0,2,0,0"/>
                </StackPanel>
                <ToggleButton x:Name="BtnPreview" Grid.Column="1" Style="{StaticResource NavBtn}" Margin="0,0,8,0" Padding="10,6" FontSize="11">
                    <StackPanel Orientation="Horizontal">
                        <Canvas Width="22" Height="18" VerticalAlignment="Center">
                            <Path Data="M1,9 C3.5,4.8 6.5,3 11,3 C15.5,3 18.5,4.8 21,9 C18.5,13.2 15.5,15 11,15 C6.5,15 3.5,13.2 1,9 Z" Stroke="{DynamicResource ResWarnB}" StrokeThickness="1.8" Fill="{x:Null}"/>
                            <Ellipse Width="4.5" Height="4.5" Fill="{DynamicResource ResWarnB}" Canvas.Left="8.75" Canvas.Top="6.75"/>
                        </Canvas>
                        <TextBlock x:Name="BtnPreviewTxt" Text="Vista previa" Margin="6,0,0,0" VerticalAlignment="Center"/>
                    </StackPanel>
                </ToggleButton>
                <Grid Grid.Column="2" Width="200" VerticalAlignment="Center" Margin="0,0,8,0">
                    <Border Background="{DynamicResource ResCard}" BorderBrush="{DynamicResource ResBorderSoft}" BorderThickness="1" CornerRadius="7">
                        <TextBox x:Name="TxtSearch" Background="Transparent" BorderThickness="0" Padding="10,6" Foreground="{DynamicResource ResText}" FontSize="11.5" VerticalContentAlignment="Center"/>
                    </Border>
                    <TextBlock x:Name="TxtSearchHint" Text="Buscar ajuste..." Foreground="{DynamicResource ResSub}" FontSize="11.5" Margin="12,0,0,0" VerticalAlignment="Center" HorizontalAlignment="Left" IsHitTestVisible="False"/>
                </Grid>
                <!-- Botón idioma custom (globo ES/EN, NO ComboBox default de Windows) -->
                <ToggleButton x:Name="BtnLang" Grid.Column="3" Style="{StaticResource RoundBtn}" Margin="0,0,8,0" ToolTipService.InitialShowDelay="300">
                    <TextBlock x:Name="BtnLangTxt" Text="ES" FontSize="10.5" FontWeight="Bold" Foreground="{DynamicResource ResAccent}" VerticalAlignment="Center" HorizontalAlignment="Center"/>
                </ToggleButton>
                <!-- Botón tema custom (sol/luna dibujados, NO ícono default) -->
                <ToggleButton x:Name="BtnTheme" Grid.Column="4" Style="{StaticResource RoundBtn}">
                    <Canvas Width="22" Height="22" VerticalAlignment="Center" HorizontalAlignment="Center">
                        <Path x:Name="IconMoon" Data="M13,3.2 C9,3.6 6,7 6,11.5 C6,16 9,19.5 13,19.8 C9.5,17.5 8,15 8,11.5 C8,8 9.5,4.6 13,3.2 Z" Fill="{DynamicResource ResAccent}"/>
                        <Path x:Name="IconSun" Data="M11,6.5 A4.5,4.5 0 1 0 11,15.5 A4.5,4.5 0 1 0 11,6.5 Z M11,2.5 L11,4.5 M11,17.5 L11,19.5 M4.5,11 L2.5,11 M19.5,11 L17.5,11 M5.2,5.2 L6.6,6.6 M15.4,15.4 L16.8,16.8 M16.8,5.2 L15.4,6.6 M6.6,15.4 L5.2,16.8" Stroke="{DynamicResource ResWarnB}" StrokeThickness="1.8" Fill="{x:Null}" Visibility="Collapsed"/>
                    </Canvas>
                </ToggleButton>
            </Grid>

            <ScrollViewer Grid.Row="1" x:Name="MainScroll" VerticalScrollBarVisibility="Auto" Padding="0,0,4,0">
                <ScrollViewer.Resources>
                    <!-- Scrollbar CUSTOM: pista fina redondeada + thumb redondeado del tema -->
                    <Style TargetType="ScrollBar">
                        <Setter Property="Width" Value="9"/>
                        <Setter Property="Background" Value="Transparent"/>
                        <Setter Property="Template">
                            <Setter.Value>
                                <ControlTemplate TargetType="ScrollBar">
                                    <Grid Background="Transparent">
                                        <Border x:Name="trackBg" Background="{DynamicResource ResScrollBg}" CornerRadius="4" Margin="2.5,1"/>
                                        <Track x:Name="PART_Track" IsDirectionReversed="True">
                                            <Track.DecreaseRepeatButton>
                                                <RepeatButton Command="ScrollBar.PageUpCommand" Opacity="0" Focusable="False"/>
                                            </Track.DecreaseRepeatButton>
                                            <Track.IncreaseRepeatButton>
                                                <RepeatButton Command="ScrollBar.PageDownCommand" Opacity="0" Focusable="False"/>
                                            </Track.IncreaseRepeatButton>
                                            <Track.Thumb>
                                                <Thumb>
                                                    <Thumb.Template>
                                                        <ControlTemplate TargetType="Thumb">
                                                            <Border x:Name="thumbBg" Background="{DynamicResource ResScrollFg}" CornerRadius="4" Margin="1.5,0"/>
                                                        </ControlTemplate>
                                                    </Thumb.Template>
                                                </Thumb>
                                            </Track.Thumb>
                                        </Track>
                                    </Grid>
                                </ControlTemplate>
                            </Setter.Value>
                        </Setter>
                        <Style.Triggers>
                            <Trigger Property="Orientation" Value="Horizontal">
                                <Setter Property="Width" Value="Auto"/>
                                <Setter Property="Height" Value="9"/>
                            </Trigger>
                        </Style.Triggers>
                    </Style>
                </ScrollViewer.Resources>
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
                                    <TextBlock x:Name="LblCpu" Grid.Row="0" Grid.Column="0" Text="Procesador" Foreground="{DynamicResource ResSub}" FontSize="11.5" Margin="0,3"/>
                                    <TextBlock x:Name="TxtSysCpu" Grid.Row="0" Grid.Column="1" Text="--" Foreground="{DynamicResource ResText}" FontSize="11.5" FontWeight="SemiBold" Margin="0,3"/>
                                    <TextBlock x:Name="LblGpu" Grid.Row="1" Grid.Column="0" Text="Gráfica" Foreground="{DynamicResource ResSub}" FontSize="11.5" Margin="0,3"/>
                                    <TextBlock x:Name="TxtSysGpu" Grid.Row="1" Grid.Column="1" Text="--" Foreground="{DynamicResource ResText}" FontSize="11.5" FontWeight="SemiBold" Margin="0,3"/>
                                    <TextBlock x:Name="LblRam" Grid.Row="2" Grid.Column="0" Text="Memoria" Foreground="{DynamicResource ResSub}" FontSize="11.5" Margin="0,3"/>
                                    <TextBlock x:Name="TxtSysRam" Grid.Row="2" Grid.Column="1" Text="--" Foreground="{DynamicResource ResText}" FontSize="11.5" FontWeight="SemiBold" Margin="0,3"/>
                                    <TextBlock x:Name="LblOs" Grid.Row="3" Grid.Column="0" Text="Sistema" Foreground="{DynamicResource ResSub}" FontSize="11.5" Margin="0,3"/>
                                    <TextBlock x:Name="TxtSysOs" Grid.Row="3" Grid.Column="1" Text="--" Foreground="{DynamicResource ResText}" FontSize="11.5" FontWeight="SemiBold" Margin="0,3"/>
                                    <TextBlock x:Name="LblDisk" Grid.Row="4" Grid.Column="0" Text="Disco C:" Foreground="{DynamicResource ResSub}" FontSize="11.5" Margin="0,3"/>
                                    <TextBlock x:Name="TxtSysDisk" Grid.Row="4" Grid.Column="1" Text="--" Foreground="{DynamicResource ResText}" FontSize="11.5" FontWeight="SemiBold" Margin="0,3"/>
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
                                    <TextBlock x:Name="LblHealth" Grid.Row="0" Grid.Column="0" Text="Salud del disco" Foreground="{DynamicResource ResSub}" FontSize="11.5" Margin="0,3"/>
                                    <TextBlock x:Name="TxtDiskHealth" Grid.Row="0" Grid.Column="1" Text="--" Foreground="{DynamicResource ResText}" FontSize="11.5" FontWeight="SemiBold" Margin="0,3"/>
                                    <TextBlock x:Name="LblBattery" Grid.Row="1" Grid.Column="0" Text="Batería" Foreground="{DynamicResource ResSub}" FontSize="11.5" Margin="0,3"/>
                                    <TextBlock x:Name="TxtBattery" Grid.Row="1" Grid.Column="1" Text="--" Foreground="{DynamicResource ResText}" FontSize="11.5" FontWeight="SemiBold" Margin="0,3"/>
                                    <TextBlock x:Name="LblServices" Grid.Row="2" Grid.Column="0" Text="Servicios en ejecución" Foreground="{DynamicResource ResSub}" FontSize="11.5" Margin="0,3"/>
                                    <TextBlock x:Name="TxtServices" Grid.Row="2" Grid.Column="1" Text="--" Foreground="{DynamicResource ResText}" FontSize="11.5" FontWeight="SemiBold" Margin="0,3"/>
                                </Grid>
                                <TextBlock x:Name="TxtTopRam" Text="--" Foreground="{DynamicResource ResDim}" FontSize="11" TextTrimming="CharacterEllipsis" Margin="0,6,0,0"/>
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
                                    <TextBlock x:Name="LblReboot" Grid.Row="0" Grid.Column="0" Text="Cambios sin reiniciar" Foreground="{DynamicResource ResSub}" FontSize="11.5" Margin="0,3"/>
                                    <TextBlock x:Name="TxtSumReboot" Grid.Row="0" Grid.Column="1" Text="--" Foreground="{DynamicResource ResOk}" FontSize="11.5" FontWeight="SemiBold" Margin="0,3"/>
                                    <TextBlock x:Name="LblVg" Grid.Row="1" Grid.Column="0" Text="Riot Vanguard" Foreground="{DynamicResource ResSub}" FontSize="11.5" Margin="0,3"/>
                                    <TextBlock x:Name="TxtSumVg" Grid.Row="1" Grid.Column="1" Text="--" Foreground="{DynamicResource ResText}" FontSize="11.5" FontWeight="SemiBold" Margin="0,3"/>
                                    <TextBlock x:Name="LblFac" Grid.Row="2" Grid.Column="0" Text="FACEIT" Foreground="{DynamicResource ResSub}" FontSize="11.5" Margin="0,3"/>
                                    <TextBlock x:Name="TxtSumFac" Grid.Row="2" Grid.Column="1" Text="--" Foreground="{DynamicResource ResText}" FontSize="11.5" FontWeight="SemiBold" Margin="0,3"/>
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
                    <StackPanel x:Name="PanelNet" Visibility="Collapsed"/>
                    <StackPanel x:Name="PanelClean" Visibility="Collapsed"/>
                    <StackPanel x:Name="PanelBrowsers" Visibility="Collapsed"/>
                    <StackPanel x:Name="PanelPanels" Visibility="Collapsed"/>
                    <StackPanel x:Name="PanelStartup" Visibility="Collapsed"/>
                    <StackPanel x:Name="PanelProfiles" Visibility="Collapsed"/>
                </Grid>
            </ScrollViewer>

            <Grid Grid.Row="2" Margin="0,10,0,0">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <Border x:Name="BorderStatus" Grid.Column="0" Background="{DynamicResource ResStatusBg}" BorderBrush="{DynamicResource ResStatusB}" BorderThickness="1" CornerRadius="6" Padding="10,7" Margin="0,0,8,0">
                    <TextBlock x:Name="TxtStatus" Text="Listo. Los interruptores se aplican al instante; pasa el mouse sobre cada tarjeta para ver su descripción." Foreground="{DynamicResource ResStatusFg}" FontSize="11" TextTrimming="CharacterEllipsis"/>
                </Border>
                <Button x:Name="BtnReboot" Grid.Column="1" Content="Reiniciar PC" Style="{StaticResource BtnStyle}" Background="#2B2112" BorderBrush="#F59E0B" Foreground="#FCD34D" Padding="14,7"/>
            </Grid>
        </Grid>
    </Grid>
</Window>
"@

try {
    try {
    $window = [Windows.Markup.XamlReader]::Parse($xamlText)
} catch {
    $errDetail = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
    Write-TempLog "ERROR XAML: $errDetail"
    [void][System.Windows.MessageBox]::Show("Error al cargar la interfaz XAML:`n`n$errDetail", 'OptiLite - Error XAML', 'OK', 'Error')
    exit 1
}
} catch {
    $errDetail = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
    Write-TempLog "ERROR XAML: $errDetail"
    [void][System.Windows.MessageBox]::Show("Error al cargar la interfaz XAML:`n`n$errDetail", 'OptiLite - Error XAML', 'OK', 'Error')
    exit 1
}

# ---------------- Referencias de controles -----------------------------------
$script:Window = $window
$script:Controls = @{}
foreach ($n in @('TxtSectionTitle','TxtSectionDesc','PanelHome','PanelPerf','PanelGames','PanelPriv','PanelNet','PanelClean','PanelBrowsers','PanelPanels','PanelStartup','PanelProfiles','TxtLiveRam','TxtLiveProc','BtnRefreshAll','BadgePending','TxtPendingBadge','BorderStatus','TxtStatus','BtnReboot','TxtSearch','TxtSearchHint','TxtSysCpu','TxtSysGpu','TxtSysRam','TxtSysOs','TxtSysDisk','TxtDiskHealth','TxtBattery','TxtServices','TxtTopRam','TxtSumReboot','TxtSumVg','TxtSumFac','BtnQuickTemp','BtnQuickDeep','BtnQuickPlan','BtnQuickUndo','BtnQuickShortcut','NavHome','NavPerf','NavGames','NavPriv','NavNet','NavClean','NavBrowsers','NavPanels','NavStartup','NavProfiles','NavHomeTxt','NavPerfTxt','NavGamesTxt','NavPrivTxt','NavNetTxt','NavCleanTxt','NavBrowsersTxt','NavPanelsTxt','NavStartupTxt','NavProfilesTxt','TxtSidebarSub','BtnLang','BtnLangTxt','BtnTheme','IconMoon','IconSun','BtnPreview','BtnPreviewTxt','GrpSysInfo','GrpDiag','GrpState','GrpQuick','LblCpu','LblGpu','LblRam','LblOs','LblDisk','LblHealth','LblBattery','LblServices','LblReboot','LblVg','LblFac','MainScroll')) {
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

# ---------------- Tema claro/oscuro EN VIVO ----------------------------------
# Se actualizan los recursos de color de la ventana: todos los controles usan
# DynamicResource y se re-pintan solos SIN recargar nada y SIN perder la
# pestaña activa.
function Save-Cfg {
    try {
        @{ Lang = $script:Lang; Theme = $script:Theme } | ConvertTo-Json |
            Set-Content -Path $script:CfgPath -Encoding UTF8
    } catch {
        Write-TempLog "No se pudo guardar la configuración: $($_.Exception.Message)"
    }
}

function Apply-Theme([string]$theme) {
    $script:Theme = $theme
    Save-Cfg
    $t = $script:Palette[$theme]
    $map = @{
        ResWinBg='WinBg'; ResSidebar='Sidebar'; ResCard='Card'; ResChip='Chip'; ResChipB='ChipB'
        ResBorder='Border'; ResBorderSoft='BorderSoft'; ResTitle='Title'; ResSub='Sub'; ResText='Text'
        ResMuted='Muted'; ResDim='Dim'; ResAccent='Accent'; ResOk='Ok'; ResWarn='Warn'; ResWarnB='WarnB'
        ResErr='Err'; ResBtnBg='BtnBg'; ResBtnB='BtnB'; ResTrack='Track'; ResTrackB='TrackB'; ResThumb='Thumb'
        ResStatusBg='StatusBg'; ResStatusB='StatusB'; ResStatusFg='StatusFg'; ResSection='Section'
        ResScrollBg='ScrollBg'; ResScrollFg='ScrollFg'; ResNavIdle='NavIdle'; ResNavHover='NavHover'
        ResNavSelBg='NavSelBg'; ResNavSelFg='NavSelFg'
    }
    foreach ($k in $map.Keys) {
        $script:Window.Resources[$k] = Get-Br $t[$map[$k]]
    }
    # Ícono de tema: sol en claro, luna en oscuro
    if ($theme -eq 'Dark') {
        $script:Controls['IconMoon'].Visibility = 'Visible'
        $script:Controls['IconSun'].Visibility = 'Collapsed'
    } else {
        $script:Controls['IconMoon'].Visibility = 'Collapsed'
        $script:Controls['IconSun'].Visibility = 'Visible'
    }
    $msgTheme = if ($theme -eq 'Dark') { T "Tema oscuro activado (guardado en optilite.json)." "Dark theme active (saved to optilite.json)." } else { T "Tema claro activado (guardado en optilite.json)." "Light theme active (saved to optilite.json)." }
    Set-Status $msgTheme
}

# ---------------- Construcción de tarjetas -----------------------------------
$script:ItemMap = @{}
foreach ($it in $Items) { $script:ItemMap[$it.Id] = $it }
$script:ItemControls = @{}
$script:AllCards = @()
$script:AllGroups = @{}
$script:StartupCards = @()
$script:CurrentPanel = 'NavHome'   # pestaña activa para el cambio de idioma

$script:CatPanels = @{
    'Perf'     = 'PanelPerf';     'Games'   = 'PanelGames'; 'Priv' = 'PanelPriv'
    'Net'      = 'PanelNet';      'Clean'   = 'PanelClean'; 'Browsers' = 'PanelBrowsers'
    'Panels'   = 'PanelPanels';   'Profiles' = 'PanelProfiles'
}
$script:PanelWords = @{
    'PanelPerf'     = 'rendimiento cpu energia red efectos servicios seguridad performance power network'
    'PanelGames'    = 'juegos gaming anti-cheat fps latencia games'
    'PanelPriv'     = 'privacidad telemetria anuncios datos copilot bing widgets privacy telemetry ads'
    'PanelNet'      = 'dns google cloudflare red servidor red network server'
    'PanelClean'    = 'limpieza disco cache temporales papelera cleanup disk temp dns flush'
    'PanelBrowsers' = 'navegadores edge brave firefox debloat browsers'
    'PanelPanels'   = 'paneles clasicos god mode control panel menu contextual win11 classic legacy'
    'PanelStartup'  = 'inicio arranque programas autostart boot startup programs'
    'PanelProfiles' = 'perfil preset rapido restauracion backup deshacer undo copia exportar importar profile'
}

function New-Text([string]$text, [string]$hexOrRes, [double]$size, [string]$weight = 'SemiBold', [bool]$wrap = $false) {
    $t = New-Object System.Windows.Controls.TextBlock
    $t.Text = $text
    if ($hexOrRes.StartsWith('#')) {
        $t.Foreground = Get-Br $hexOrRes
    } else {
        $t.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $hexOrRes)
    }
    $t.FontSize = $size
    switch ($weight) {
        'SemiBold' { $t.FontWeight = [System.Windows.FontWeights]::SemiBold }
        'Bold'     { $t.FontWeight = [System.Windows.FontWeights]::Bold }
        default    { $t.FontWeight = [System.Windows.FontWeights]::Normal }
    }
    if ($wrap) { $t.TextWrapping = [System.Windows.TextWrapping]::Wrap }
    return $t
}

# Tooltip custom estilo OptiLite (aparece al ACERCAR el mouse a la tarjeta)
function New-Tip([string]$title, [string]$body) {
    $tip = New-Object System.Windows.Controls.ToolTip
    $tip.Style = $script:Window.TryFindResource('TipStyle')
    $tip.Tag = $title
    $tip.Content = $body
    $tip.Placement = [System.Windows.Controls.Primitives.PlacementMode]::Top
    $tip.HorizontalOffset = 0
    $tip.VerticalOffset = -6
    $tip.HasDropShadow = $false
    return $tip
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
    $nameTb = New-Text (L $item.Name) 'ResTitle' 13 'SemiBold'
    [void]$txt.Children.Add($nameTb)
    # v2.0: la descripción YA NO va debajo del nombre; va en el TOOLTIP
    # al pasar el mouse sobre la tarjeta (interfaz más limpia).
    $card.ToolTip = New-Tip (L $item.Name) (L $item.Desc)
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
    [void]$txt.Children.Add((New-Text (L $act.Name) 'ResTitle' 13 'SemiBold'))
    # v2.0: descripción en tooltip, no debajo
    $card.ToolTip = New-Tip (L $act.Name) (L $act.Desc)
    [void]$dock.Children.Add($txt)
    $card.Child = $dock

    Register-Card $panel (L $act.Grp) $card "$((L $act.Name)) $((L $act.Desc))"
    [void]$script:Controls[$panel].Children.Add($card)

    $btn.Add_Click({
        param($sender, $e)
        $act = $sender.Tag
        if ($script:Preview) {
            Set-Status "[VISTA PREVIA] $((L $act.Name)): $(T 'se ejecutaría al pulsar sin vista previa (no se ha hecho nada).' 'it would run with preview off (nothing was done).')"
            return
        }
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
    $desc = New-Text (L $preset.Desc) 'ResDim' 11 'Normal' $true
    $desc.Margin = New-Object System.Windows.Thickness(0, 3, 0, 0)
    [void]$txt.Children.Add($desc)
    [void]$dock.Children.Add($txt)
    $card.Child = $dock
    # Los presets SÍ muestran su resumen (es su función) + tooltip completo
    $card.ToolTip = New-Tip $preset.Name (L $preset.Desc)

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

# ---------------- Panel Inicio (v1.1, heredado) --------------------------------
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
    [void]$txt.Children.Add((New-Text $entry.Name 'ResTitle' 13 'SemiBold'))
    $cmd = $entry.Cmd
    if ($cmd.Length -gt 90) { $cmd = $cmd.Substring(0, 90) + '...' }
    $loc = if ($entry.Loc -eq 'Folder') { (T 'Carpeta Inicio' 'Startup folder') } else { $entry.Loc }
    $desc = New-Text "$loc · $cmd" 'ResDim' 10.5 'Normal' $true
    $desc.Margin = New-Object System.Windows.Thickness(0, 2, 0, 0)
    [void]$txt.Children.Add($desc)
    [void]$dock.Children.Add($txt)
    $card.Child = $dock
    $card.ToolTip = New-Tip $entry.Name "$($entry.Name) · $loc`n$($entry.Cmd)"

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
        $tb = New-Text (T 'No se encontraron programas de inicio.' 'No startup programs found.') 'ResDim' 11.5 'Normal' $true
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
    @{ Btn='NavPerf';     Panel='PanelPerf';     Title=@{ES='Rendimiento';EN='Performance'}; Desc=@{ES='CPU, memoria, efectos visuales, servicios, seguridad y red';EN='CPU, memory, visual effects, services, security and network'} }
    @{ Btn='NavGames';    Panel='PanelGames';    Title=@{ES='Juegos';EN='Gaming'};      Desc=@{ES='Anti-cheats, Xbox, captura, latencia y audio';EN='Anti-cheats, Xbox, capture, latency and audio'} }
    @{ Btn='NavPriv';     Panel='PanelPriv';     Title=@{ES='Privacidad';EN='Privacy'};  Desc=@{ES='Telemetría, historial, anuncios, Copilot y Bing';EN='Telemetry, history, ads, Copilot and Bing'} }
    @{ Btn='NavNet';      Panel='PanelNet';      Title=@{ES='Red y DNS';EN='Network & DNS'}; Desc=@{ES='DNS de Google/Cloudflare y limpieza de caché';EN='Google/Cloudflare DNS and cache flushing'} }
    @{ Btn='NavClean';    Panel='PanelClean';    Title=@{ES='Limpieza';EN='Cleanup'};    Desc=@{ES='Archivos temporales, caché y mantenimiento';EN='Temp files, cache and maintenance'} }
    @{ Btn='NavBrowsers'; Panel='PanelBrowsers'; Title=@{ES='Navegadores';EN='Browsers'}; Desc=@{ES='Debloat de Edge, Brave y Firefox';EN='Edge, Brave and Firefox debloat'} }
    @{ Btn='NavPanels';   Panel='PanelPanels';   Title=@{ES='Paneles clásicos';EN='Classic panels'}; Desc=@{ES='God Mode y paneles clásicos de Windows';EN='God Mode and classic Windows panels'} }
    @{ Btn='NavStartup';  Panel='PanelStartup'; Title=@{ES='Inicio';EN='Startup'};     Desc=@{ES='Programas que arrancan con Windows';EN='Programs that start with Windows'} }
    @{ Btn='NavProfiles'; Panel='PanelProfiles'; Title=@{ES='Perfiles';EN='Profiles'};  Desc=@{ES='Perfiles de un clic, deshacer y copia de seguridad';EN='One-click profiles, undo and backups'} }
)

function Show-Panel([string]$btnName) {
    foreach ($n in $script:NavMap) {
        $active = ($n.Btn -eq $btnName)
        $script:Controls[$n.Btn].IsChecked = $active
        if ($active) {
            $script:CurrentPanel = $btnName        # recordar pestaña para idioma/tema
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
        $cur = $null
        try { $cur = & $it.Get } catch { $cur = $null }
        if ($null -eq $cur) { $chk.IsEnabled = $false; $chk.IsChecked = $false }
        else { $chk.IsEnabled = $true; $chk.IsChecked = [bool]$cur }
    }
    Update-Summary
}

# Set-Status v2: opcionalmente colorea el fondo según tema (claro/oscuro)
function Set-Status([string]$msg) {
    if ($script:PendingReboot) {
        $script:Controls['BorderStatus'].Background = Get-Br (C 'StatusBgW')
        $script:Controls['BorderStatus'].BorderBrush = Get-Br (C 'WarnB')
        $script:Controls['TxtStatus'].Foreground = Get-Br '#FDE68A'
        $script:Controls['TxtStatus'].Text = "$msg  [$(T 'REINICIO PENDIENTE' 'PENDING REBOOT')]"
    } else {
        $script:Controls['BorderStatus'].Background = Get-Br (C 'StatusBg')
        $script:Controls['BorderStatus'].BorderBrush = Get-Br (C 'StatusB')
        $script:Controls['TxtStatus'].Foreground = Get-Br (C 'StatusFg')
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

# ---------------- Idioma: aplicar EN VIVO en la pestaña activa (v2.0) ---------
# v2.0: al cambiar el idioma NO se vuelve a "Resumen". Se reconstruyen los
# paneles y se re-muestra la pestaña en la que estabas ($script:CurrentPanel).
# En el ARRANQUE se llama con -Rebuild:$false: los paneles todavía no existen
# (Build-Panels los crea después, ya en el idioma guardado), así que no hay
# doble pasada de tarjetas ni de lecturas de estado al abrir.
function Apply-Language([string]$lang, [bool]$rebuild = $true) {
    $script:Lang = $lang
    Save-Cfg

    # Controles con texto fijo
    $script:Controls['TxtSidebarSub'].Text = T 'Optimización local · sin descargas' 'Local optimization · no downloads'
    $script:Controls['TxtPendingBadge'].Text = T 'Reinicio pendiente' 'Pending reboot'
    $script:Controls['BtnRefreshAll'].Content = T 'Refrescar estados' 'Refresh states'
    $script:Controls['NavHomeTxt'].Text = T 'Resumen' 'Summary'
    $script:Controls['NavPerfTxt'].Text = T 'Rendimiento' 'Performance'
    $script:Controls['NavGamesTxt'].Text = T 'Juegos' 'Gaming'
    $script:Controls['NavPrivTxt'].Text = T 'Privacidad' 'Privacy'
    $script:Controls['NavNetTxt'].Text = T 'Red y DNS' 'Network & DNS'
    $script:Controls['NavCleanTxt'].Text = T 'Limpieza' 'Cleanup'
    $script:Controls['NavBrowsersTxt'].Text = T 'Navegadores' 'Browsers'
    $script:Controls['NavPanelsTxt'].Text = T 'Paneles clásicos' 'Classic panels'
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
    $script:Controls['BtnPreviewTxt'].Text = T 'Vista previa' 'Preview'
    $script:Controls['BtnLangTxt'].Text = $script:Lang
    $script:Controls['BtnReboot'].Content = T 'Reiniciar PC' 'Restart PC'
    $script:Controls['BtnQuickTemp'].Content = T 'Limpiar TEMP' 'Clean TEMP'
    $script:Controls['BtnQuickDeep'].Content = T 'Limpieza profunda' 'Deep cleanup'
    $script:Controls['BtnQuickPlan'].Content = T 'Plan Ultimate' 'Ultimate plan'
    $script:Controls['BtnQuickUndo'].Content = T 'Deshacer último' 'Undo last'
    $script:Controls['BtnQuickShortcut'].Content = T 'Acceso en Escritorio' 'Desktop shortcut'
    $script:Window.Title = T 'OptiLite v2.0.0 · Optimizador de Windows 10/11' 'OptiLite v2.0.0 · Windows 10/11 optimizer'

    # Reconstruir paneles con textos del nuevo idioma (solo cuando ya existían:
    # es un cambio de idioma en caliente, no el arranque)
    if ($rebuild) {
        foreach ($p in @('PanelPerf','PanelGames','PanelPriv','PanelNet','PanelClean','PanelBrowsers','PanelPanels','PanelProfiles','PanelStartup')) {
            $script:Controls[$p].Children.Clear()
        }
        $script:AllCards = @()
        $script:AllGroups = @{}
        $script:StartupCards = @()
        Build-Panels
    }

    # v2.0: volver a la MISMA pestaña donde estaba el usuario (no a Resumen)
    $prev = $script:CurrentPanel
    if (-not $prev) { $prev = 'NavHome' }
    Show-Panel $prev
    Refresh-AllStates
    Refresh-LiveStats
    if ($rebuild) {
        Set-Status (T 'Idioma cambiado a español. La preferencia queda guardada en optilite.json.' 'Language switched to English. The preference is stored in optilite.json.')
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

# --- Botón de idioma CUSTOM (globo): ES <-> EN al instante y en la misma pestaña
$script:Controls['BtnLang'].Add_Click({
    param($sender, $e)
    $new = if ($script:Lang -eq 'ES') { 'EN' } else { 'ES' }
    Apply-Language $new
    $sender.IsChecked = $false   # botón momentáneo, no queda "presionado"
})

# --- Botón de tema CUSTOM (sol/luna): claro <-> oscuro al instante
$script:Controls['BtnTheme'].Add_Click({
    param($sender, $e)
    $new = if ($script:Theme -eq 'Dark') { 'Light' } else { 'Dark' }
    Apply-Theme $new
    $sender.IsChecked = $false
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
    Refresh-StartupPanel
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

# Arranque protegido paso a paso: si una etapa falla en tu equipo, verás
# exactamente CUÁL fue y por qué (ventana con el detalle + queda en el log),
# en vez de quedarse colgado en silencio.
function Invoke-StartupStep([string]$name, [scriptblock]$body) {
    try {
        & $body
    } catch {
        $detail = $_.Exception.Message
        Write-TempLog "FALLO en arranque [$name]: $detail"
        Write-Host "  [!] Fallo en: $name -> $detail" -ForegroundColor Red
        try {
            [void][System.Windows.MessageBox]::Show(
                "Fallo al inicializar: $name`n`n$detail`n`n$(T 'OptiLite seguirá abriendo con las funciones que sí funcionen.' 'OptiLite will still open with the features that do work.')",
                "OptiLite - $(T 'error de arranque' 'startup error')",
                'OK', 'Warning')
        } catch {}
        return $false
    }
    return $true
}

$null = Invoke-StartupStep 'Undo stack'      { Initialize-UndoStack }
$null = Invoke-StartupStep 'Interfaz'        { Build-Panels }
$null = Invoke-StartupStep 'Info del equipo' { Initialize-SysInfo }
$null = Invoke-StartupStep 'Diagnóstico'     { Initialize-Diagnostics }
$null = Invoke-StartupStep 'Paneles'         { Show-Panel 'NavHome'; Refresh-AllStates; Refresh-LiveStats }
$null = Invoke-StartupStep 'Idioma/tema'    { Apply-Language $script:Lang $false; Apply-Theme $script:Theme }

$script:Timer = New-Object System.Windows.Threading.DispatcherTimer
$script:Timer.Interval = [TimeSpan]::FromSeconds(5)
$script:Timer.Add_Tick({ Refresh-LiveStats })
$script:Timer.Start()

Write-TempLog "OptiLite v$($script:Version) iniciado (idioma $($script:Lang), tema $($script:Theme))."
try {
    [void]$window.ShowDialog()
} catch {
    $detail = $_.Exception.Message
    Write-TempLog "La ventana no pudo abrirse: $detail"
    [void][System.Windows.MessageBox]::Show(
        "La ventana no pudo abrirse: $detail",
        'OptiLite', 'OK', 'Error')
}
