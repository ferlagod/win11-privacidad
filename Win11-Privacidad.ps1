#Requires -Version 5.1
<#
.SYNOPSIS
    Win11-Privacidad - Reduce la telemetría, mejora la privacidad y elimina bloatware
    de Windows 11 de forma SEGURA y REVERSIBLE.

.DESCRIPTION
    Medidas de seguridad:
      * Crea un punto de restauración del sistema antes del primer cambio.
      * Exporta a ficheros .reg las ramas del registro que se van a modificar.
      * Registra el valor ORIGINAL de cada clave, servicio y tarea que toca en
        C:\ProgramData\Win11Privacidad\cambios.json  -> la opción "Revertir" del
        menú lo deja todo como estaba.
      * Guarda un log completo de cada sesión en C:\ProgramData\Win11Privacidad\logs
      * Nada se elimina sin que lo elijas tú; las acciones delicadas piden escribir "SI".

    Lo que este script NO toca, a propósito:
      * Enlace Móvil / Phone Link, Dispositivos conectados (CDP) y portapapeles entre dispositivos.
      * Microsoft Store, winget, Windows Update, Defender, Firewall, SmartScreen.
      * Servicios de Xbox / Gaming Services, Xbox Identity Provider (necesarios para juegos).
      * WebView2 (lo usan launchers de juegos y muchas aplicaciones).
      * El archivo hosts ni el firewall (bloquear dominios de Microsoft rompe actualizaciones, Store y Xbox).

.NOTES
    Ejecutar como administrador:
      powershell -NoProfile -ExecutionPolicy Bypass -File .\Win11-Privacidad.ps1
    o haciendo doble clic en "Ejecutar.cmd".
#>

# ----------------------------------------------------------------------------
#  Elevación
# ----------------------------------------------------------------------------
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Se necesitan permisos de administrador. Solicitando elevación..." -ForegroundColor Yellow
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

$ScriptVersion = '0.1.0'
$ErrorActionPreference = 'Continue'
$Host.UI.RawUI.WindowTitle = "Win11-Privacidad v$ScriptVersion"

# ----------------------------------------------------------------------------
#  Rutas, log y diario de cambios
# ----------------------------------------------------------------------------
$BaseDir     = Join-Path $env:ProgramData 'Win11Privacidad'
$LogDir      = Join-Path $BaseDir 'logs'
$JournalFile = Join-Path $BaseDir 'cambios.json'
$AppsLogFile = Join-Path $BaseDir 'apps_eliminadas.txt'
New-Item -ItemType Directory -Force -Path $BaseDir, $LogDir | Out-Null
try { Start-Transcript -Path (Join-Path $LogDir ("sesion_{0:yyyyMMdd_HHmmss}.log" -f (Get-Date))) | Out-Null } catch {}

$script:SafetyDone = $false
$script:Journal    = New-Object System.Collections.ArrayList

if (Test-Path $JournalFile) {
    try {
        $raw = Get-Content -Path $JournalFile -Raw -Encoding UTF8
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            foreach ($e in @($raw | ConvertFrom-Json)) { [void]$script:Journal.Add($e) }
        }
    } catch {
        Write-Host "AVISO: no se pudo leer $JournalFile. Se renombra y se empieza uno nuevo." -ForegroundColor Yellow
        Rename-Item $JournalFile ("cambios_corrupto_{0:yyyyMMdd_HHmmss}.json" -f (Get-Date)) -ErrorAction SilentlyContinue
    }
}

# ----------------------------------------------------------------------------
#  Utilidades de salida y preguntas
# ----------------------------------------------------------------------------
function Write-Titulo([string]$t) { Write-Host ""; Write-Host "=== $t ===" -ForegroundColor Cyan }
function Write-Ok([string]$t)     { Write-Host "  [OK] $t" -ForegroundColor Green }
function Write-Info([string]$t)   { Write-Host "  [i]  $t" -ForegroundColor Gray }
function Write-Aviso([string]$t)  { Write-Host "  [!]  $t" -ForegroundColor Yellow }
function Write-Fallo([string]$t)  { Write-Host "  [X]  $t" -ForegroundColor Red }

function Ask-YesNo([string]$Pregunta, [bool]$PorDefecto = $true) {
    $suf = if ($PorDefecto) { '[S/n]' } else { '[s/N]' }
    $r = Read-Host "$Pregunta $suf"
    if ([string]::IsNullOrWhiteSpace($r)) { return $PorDefecto }
    return ($r.Trim().ToLower() -in @('s', 'si', 'sí', 'y', 'yes'))
}

function Confirm-Strong([string]$Mensaje) {
    Write-Host ""
    Write-Host $Mensaje -ForegroundColor Yellow
    $r = Read-Host "Escribe SI (en mayúsculas o minúsculas) para confirmar, cualquier otra cosa cancela"
    return ($r.Trim().ToUpper() -eq 'SI')
}

function Pause-Menu { Write-Host ""; [void](Read-Host "Pulsa Enter para volver al menú") }

# ----------------------------------------------------------------------------
#  Diario de cambios (permite revertir)
# ----------------------------------------------------------------------------
function Save-Journal {
    try {
        ConvertTo-Json -InputObject @($script:Journal.ToArray()) -Depth 5 |
            Set-Content -Path $JournalFile -Encoding UTF8
    } catch { Write-Fallo "No se pudo guardar el diario de cambios: $($_.Exception.Message)" }
}

function Test-Journaled([string]$Type, [string]$Path, [string]$Name) {
    foreach ($e in $script:Journal) {
        if ($e.Type -eq $Type -and $e.Path -eq $Path -and $e.Name -eq $Name) { return $true }
    }
    return $false
}

# Escribe un valor de registro guardando antes el valor original (solo la primera vez,
# así "Revertir" siempre vuelve al estado previo a usar el script).
function Set-Reg {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [ValidateSet('DWord', 'QWord', 'String', 'ExpandString', 'MultiString', 'Binary')]
        [string]$Type = 'DWord'
    )
    try {
        if (-not (Test-Journaled 'Reg' $Path $Name)) {
            $existed = $false; $old = $null; $oldKind = $null
            if (Test-Path -LiteralPath $Path) {
                $key = Get-Item -LiteralPath $Path
                if ($key.GetValueNames() -contains $Name) {
                    $existed = $true
                    $old     = $key.GetValue($Name, $null, 'DoNotExpandEnvironmentNames')
                    $oldKind = $key.GetValueKind($Name).ToString()
                }
            }
            [void]$script:Journal.Add([pscustomobject]@{
                Type = 'Reg'; Path = $Path; Name = $Name
                Existed = $existed; OldValue = $old; OldKind = $oldKind
                Date = (Get-Date).ToString('s')
            })
        }
        if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force | Out-Null }
        New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
    } catch {
        Write-Aviso "No se pudo establecer $Path\$Name : $($_.Exception.Message)"
    }
}

function Disable-Svc([string]$Name, [string]$Descripcion) {
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if (-not $svc) { Write-Info "Servicio $Name no existe en este equipo, se omite."; return }
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"
    if (-not (Test-Journaled 'Service' $regPath $Name)) {
        $p = Get-ItemProperty -LiteralPath $regPath -ErrorAction SilentlyContinue
        [void]$script:Journal.Add([pscustomobject]@{
            Type = 'Service'; Path = $regPath; Name = $Name
            OldStart = $p.Start; OldDelayed = $p.DelayedAutostart
            Date = (Get-Date).ToString('s')
        })
    }
    try {
        Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
        Set-Service -Name $Name -StartupType Disabled -ErrorAction Stop
        Write-Ok "Servicio desactivado: $Descripcion ($Name)"
    } catch { Write-Aviso "No se pudo desactivar $Name : $($_.Exception.Message)" }
}

function Disable-Task([string]$FullPath) {
    $taskPath = (Split-Path $FullPath -Parent).TrimEnd('\') + '\'
    $taskName = Split-Path $FullPath -Leaf
    $t = Get-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction SilentlyContinue
    if (-not $t) { return }
    if (-not (Test-Journaled 'Task' $taskPath $taskName)) {
        [void]$script:Journal.Add([pscustomobject]@{
            Type = 'Task'; Path = $taskPath; Name = $taskName
            WasEnabled = ($t.State -ne 'Disabled')
            Date = (Get-Date).ToString('s')
        })
    }
    try {
        Disable-ScheduledTask -InputObject $t -ErrorAction Stop | Out-Null
        Write-Ok "Tarea desactivada: $taskName"
    } catch { Write-Aviso "No se pudo desactivar la tarea $taskName : $($_.Exception.Message)" }
}

# ----------------------------------------------------------------------------
#  Seguridad: punto de restauración + copia del registro
# ----------------------------------------------------------------------------
function New-RestorePoint {
    Write-Titulo "Creando punto de restauración"
    $srKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    $prev  = (Get-ItemProperty -Path $srKey -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue).SystemRestorePointCreationFrequency
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop
        # Windows solo permite 1 punto cada 24 h por defecto; se levanta el límite temporalmente.
        New-ItemProperty -Path $srKey -Name SystemRestorePointCreationFrequency -Value 0 -PropertyType DWord -Force | Out-Null
        Checkpoint-Computer -Description ("Win11-Privacidad {0:yyyy-MM-dd HH:mm}" -f (Get-Date)) -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Write-Ok "Punto de restauración creado."
        return $true
    } catch {
        Write-Fallo "No se pudo crear el punto de restauración: $($_.Exception.Message)"
        return $false
    } finally {
        if ($null -eq $prev) { Remove-ItemProperty -Path $srKey -Name SystemRestorePointCreationFrequency -ErrorAction SilentlyContinue }
        else { New-ItemProperty -Path $srKey -Name SystemRestorePointCreationFrequency -Value $prev -PropertyType DWord -Force | Out-Null }
    }
}

function Backup-Registry {
    $dir = Join-Path $BaseDir ("registro_{0:yyyyMMdd_HHmmss}" -f (Get-Date))
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $keys = @(
        'HKLM\SOFTWARE\Policies',
        'HKCU\Software\Policies',
        'HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager',
        'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced',
        'HKCU\Software\Microsoft\Windows\CurrentVersion\Search',
        'HKCU\Software\Microsoft\Windows\CurrentVersion\SearchSettings',
        'HKCU\Software\Microsoft\Windows\CurrentVersion\Privacy',
        'HKCU\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo',
        'HKCU\Software\Microsoft\InputPersonalization'
    )
    foreach ($k in $keys) {
        $file = Join-Path $dir (($k -replace '[\\:]', '_') + '.reg')
        & reg.exe export $k $file /y 2>&1 | Out-Null
    }
    Write-Ok "Copia del registro guardada en: $dir"
}

function Ensure-Safety {
    if ($script:SafetyDone) { return $true }
    Write-Titulo "Medidas de seguridad previas"
    Backup-Registry
    if (Ask-YesNo "¿Crear un punto de restauración del sistema ahora? (muy recomendado)" $true) {
        if (-not (New-RestorePoint)) {
            Write-Info "Aun sin punto de restauración, los cambios de registro/servicios/tareas se pueden revertir desde el menú."
            if (-not (Ask-YesNo "¿Continuar de todos modos?" $false)) { return $false }
        }
    }
    $script:SafetyDone = $true
    return $true
}

# ----------------------------------------------------------------------------
#  1) Telemetría
# ----------------------------------------------------------------------------
function Invoke-Telemetry {
    Write-Titulo "Desactivando telemetría"

    # Datos de diagnóstico (en Pro, 0 equivale al mínimo permitido: "Requeridos")
    $dc = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection'
    Set-Reg $dc 'AllowTelemetry' 0
    Set-Reg $dc 'MaxTelemetryAllowed' 0
    Set-Reg $dc 'AllowDeviceNameInTelemetry' 0
    Set-Reg $dc 'DoNotShowFeedbackNotifications' 1
    Set-Reg $dc 'LimitDiagnosticLogCollection' 1
    Set-Reg $dc 'LimitDumpCollection' 1
    Set-Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' 'AllowTelemetry' 0
    Write-Ok "Nivel de datos de diagnóstico al mínimo."

    # Programa de mejora de la experiencia, inventario de aplicaciones, informes de errores
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows' 'CEIPEnable' 0
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat' 'AITEnable' 0
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat' 'DisableInventory' 1
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat' 'DisableUAR' 1
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting' 'Disabled' 1
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\TabletPC' 'PreventHandwritingDataSharing' 1
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\HandwritingErrorReports' 'PreventHandwritingErrorReports' 1
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\MRT' 'DontReportInfectionInformation' 1
    Write-Ok "CEIP, inventario, informes de errores y escritura a mano desactivados."

    # Encuestas de opinión (Feedback)
    Set-Reg 'HKCU:\Software\Microsoft\Siuf\Rules' 'NumberOfSIUFInPeriod' 0
    Write-Ok "Solicitudes de opinión desactivadas."

    # Optimización de distribución: descargas solo desde Microsoft, sin P2P con otros PCs de Internet
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0
    Write-Ok "Optimización de distribución sin P2P (Windows Update sigue funcionando)."

    # Telemetría de Office, PowerShell y .NET
    foreach ($p in 'HKCU:\Software\Policies\Microsoft\Office\16.0\Common\ClientTelemetry',
                   'HKCU:\Software\Policies\Microsoft\Office\Common\ClientTelemetry') {
        Set-Reg $p 'DisableTelemetry' 1
        Set-Reg $p 'SendTelemetry' 3
    }
    $envKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
    Set-Reg $envKey 'POWERSHELL_TELEMETRY_OPTOUT' '1' 'String'
    Set-Reg $envKey 'DOTNET_CLI_TELEMETRY_OPTOUT' '1' 'String'
    Write-Ok "Telemetría de Office, PowerShell y .NET desactivada."

    # Servicios de telemetría
    Disable-Svc 'DiagTrack'        'Experiencias del usuario y telemetría asociadas'
    Disable-Svc 'dmwappushservice' 'Enrutamiento de mensajes push WAP'

    # Tareas programadas de recopilación de datos
    $tasks = @(
        '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser',
        '\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser Exp',
        '\Microsoft\Windows\Application Experience\ProgramDataUpdater',
        '\Microsoft\Windows\Application Experience\MareBackup',
        '\Microsoft\Windows\Autochk\Proxy',
        '\Microsoft\Windows\Customer Experience Improvement Program\Consolidator',
        '\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip',
        '\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector',
        '\Microsoft\Windows\Feedback\Siuf\DmClient',
        '\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload',
        '\Microsoft\Windows\Windows Error Reporting\QueueReporting'
    )
    foreach ($t in $tasks) { Disable-Task $t }

    Save-Journal
    Write-Ok "Telemetría completada."
}

# ----------------------------------------------------------------------------
#  2) Privacidad, anuncios y sugerencias
# ----------------------------------------------------------------------------
function Invoke-Privacy {
    Write-Titulo "Privacidad, anuncios y sugerencias"

    # ID de publicidad
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo' 'DisabledByGroupPolicy' 1
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 0
    Write-Ok "ID de publicidad desactivado."

    # Experiencias personalizadas con datos de diagnóstico
    Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\CloudContent' 'DisableTailoredExperiencesWithDiagnosticData' 1
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 0
    Write-Ok "Experiencias personalizadas desactivadas."

    # Historial de actividad
    $sys = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System'
    Set-Reg $sys 'EnableActivityFeed' 0
    Set-Reg $sys 'PublishUserActivities' 0
    Set-Reg $sys 'UploadUserActivities' 0
    Write-Ok "Historial de actividad desactivado."

    # Escritura, entrada manuscrita y voz en línea
    Set-Reg 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' 1
    Set-Reg 'HKCU:\Software\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' 1
    Set-Reg 'HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore' 'HarvestContacts' 0
    Set-Reg 'HKCU:\Software\Microsoft\Personalization\Settings' 'AcceptedPrivacyPolicy' 0
    Set-Reg 'HKCU:\Software\Microsoft\Input\TIPC' 'Enabled' 0
    Set-Reg 'HKCU:\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' 'HasAccepted' 0
    Write-Ok "Recopilación de escritura/voz desactivada."

    # Sitios web y lista de idiomas
    Set-Reg 'HKCU:\Control Panel\International\User Profile' 'HttpAcceptLanguageOptOut' 1

    # Anuncios, apps instaladas en silencio y sugerencias (ContentDeliveryManager)
    $cdm = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    foreach ($n in 'SilentInstalledAppsEnabled', 'SystemPaneSuggestionsEnabled', 'SoftLandingEnabled',
                   'OemPreInstalledAppsEnabled', 'PreInstalledAppsEnabled', 'PreInstalledAppsEverEnabled',
                   'FeatureManagementEnabled', 'RotatingLockScreenOverlayEnabled',
                   'SubscribedContent-310093Enabled', 'SubscribedContent-338387Enabled',
                   'SubscribedContent-338388Enabled', 'SubscribedContent-338389Enabled',
                   'SubscribedContent-338393Enabled', 'SubscribedContent-353694Enabled',
                   'SubscribedContent-353696Enabled', 'SubscribedContent-353698Enabled') {
        Set-Reg $cdm $n 0
    }
    $cc = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
    Set-Reg $cc 'DisableWindowsConsumerFeatures' 1
    Set-Reg $cc 'DisableConsumerAccountStateContent' 1
    Set-Reg $cc 'DisableCloudOptimizedContent' 1
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' 'ScoobeSystemSettingEnabled' 0
    Write-Ok "Anuncios, sugerencias e instalación silenciosa de apps desactivados."

    # Menú Inicio y Explorador
    $adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    Set-Reg $adv 'Start_IrisRecommendations' 0
    Set-Reg $adv 'Start_AccountNotifications' 0
    Set-Reg $adv 'Start_TrackProgs' 0
    Set-Reg $adv 'ShowSyncProviderNotifications' 0
    Write-Ok "Recomendaciones del Inicio y anuncios del Explorador desactivados."

    # Búsqueda: sin Bing ni resultados web
    Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 1
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 0
    $ws = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'
    Set-Reg $ws 'AllowCloudSearch' 0
    Set-Reg $ws 'ConnectedSearchUseWeb' 0
    Set-Reg $ws 'DisableWebSearch' 1
    $ss = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings'
    Set-Reg $ss 'IsDynamicSearchBoxEnabled' 0
    Set-Reg $ss 'IsMSACloudSearchEnabled' 0
    Set-Reg $ss 'IsAADCloudSearchEnabled' 0
    Set-Reg $ss 'IsDeviceSearchHistoryEnabled' 0
    Write-Ok "Búsqueda local sin Bing ni contenido web."

    # Widgets / Noticias
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' 'AllowNewsAndInterests' 0
    Write-Ok "Widgets (noticias MSN) desactivados."

    # Opcional: ubicación
    Write-Host ""
    Write-Info "OPCIONAL: desactivar la ubicación rompe el tiempo local, la zona horaria automática y 'Encontrar mi dispositivo'."
    if (Ask-YesNo "¿Desactivar el servicio de ubicación para todo el sistema?" $false) {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors' 'DisableLocation' 1
        Write-Ok "Ubicación desactivada."
    }
    if (Ask-YesNo "¿Desactivar 'Encontrar mi dispositivo'?" $false) {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\FindMyDevice' 'AllowFindMyDevice' 0
        Write-Ok "'Encontrar mi dispositivo' desactivado."
    }

    Save-Journal
    Write-Info "Enlace Móvil, Dispositivos conectados y portapapeles entre dispositivos NO se han tocado."
    Write-Ok "Privacidad completada."
}

# ----------------------------------------------------------------------------
#  3) Copilot, Recall y funciones de IA
# ----------------------------------------------------------------------------
function Invoke-AI {
    Write-Titulo "Copilot, Recall y funciones de IA"
    Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 1
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'ShowCopilotButton' 0
    Write-Ok "Copilot de Windows desactivado (la app se puede quitar en el menú de bloatware)."

    $ai = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI'
    Set-Reg $ai 'DisableAIDataAnalysis' 1
    Set-Reg $ai 'AllowRecallEnablement' 0
    Set-Reg $ai 'DisableClickToDo' 1
    Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\WindowsAI' 'DisableAIDataAnalysis' 1
    Set-Reg 'HKCU:\Software\Policies\Microsoft\Windows\WindowsAI' 'DisableClickToDo' 1
    Write-Ok "Recall (capturas de pantalla) y Click to Do desactivados."

    $paint = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint'
    Set-Reg $paint 'DisableCocreator' 1
    Set-Reg $paint 'DisableGenerativeFill' 1
    Set-Reg $paint 'DisableImageCreator' 1
    Set-Reg 'HKLM:\SOFTWARE\Policies\WindowsNotepad' 'DisableAIFeatures' 1
    Write-Ok "Funciones de IA en la nube de Paint y Bloc de notas desactivadas."

    Save-Journal
}

# ----------------------------------------------------------------------------
#  4) Microsoft Edge
# ----------------------------------------------------------------------------
function Invoke-Edge {
    Write-Titulo "Microsoft Edge: telemetría y procesos en segundo plano"
    $e = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
    Set-Reg $e 'DiagnosticData' 0
    Set-Reg $e 'MetricsReportingEnabled' 0
    Set-Reg $e 'PersonalizationReportingEnabled' 0
    Set-Reg $e 'UserFeedbackAllowed' 0
    Set-Reg $e 'StartupBoostEnabled' 0
    Set-Reg $e 'BackgroundModeEnabled' 0
    Set-Reg $e 'HubsSidebarEnabled' 0
    Set-Reg $e 'EdgeShoppingAssistantEnabled' 0
    Set-Reg $e 'ShowRecommendationsEnabled' 0
    Set-Reg $e 'SpotlightExperiencesAndRecommendationsEnabled' 0
    Set-Reg $e 'ShowMicrosoftRewards' 0
    Set-Reg $e 'ConfigureDoNotTrack' 1
    Set-Reg $e 'HideFirstRunExperience' 1
    Save-Journal
    Write-Ok "Edge ya no envía telemetría ni se queda abierto en segundo plano."
    Write-Info "Edge mostrará 'Administrado por tu organización': es normal al aplicar directivas."
    Write-Host ""
    Write-Info "Para QUITAR Edge: en la Unión Europea Windows permite desinstalarlo oficialmente desde"
    Write-Info "Configuración > Aplicaciones > Aplicaciones instaladas > Microsoft Edge > Desinstalar."
    Write-Info "No elimines 'Microsoft Edge WebView2 Runtime': lo usan launchers de juegos y muchas apps."
    Write-Info "Para cambiar el navegador predeterminado: Configuración > Aplicaciones > Aplicaciones predeterminadas."
    if (Ask-YesNo "¿Abrir ahora 'Aplicaciones instaladas' para desinstalar Edge u otras apps?" $false) {
        Start-Process 'ms-settings:appsfeatures'
    }
    if (Ask-YesNo "¿Abrir 'Aplicaciones predeterminadas' para cambiar el navegador?" $false) {
        Start-Process 'ms-settings:defaultapps'
    }
}

# ----------------------------------------------------------------------------
#  5) Bloatware
# ----------------------------------------------------------------------------
# Nunca se eliminan, aunque coincidan con algún patrón.
$ProtectedApps = @(
    'Microsoft.YourPhone', 'MicrosoftWindows.CrossDevice', 'Microsoft.WindowsStore',
    'Microsoft.StorePurchaseApp', 'Microsoft.DesktopAppInstaller', 'Microsoft.SecHealthUI',
    'Microsoft.VCLibs*', 'Microsoft.UI.Xaml*', 'Microsoft.NET.*', 'Microsoft.WindowsAppRuntime*',
    'Microsoft.XboxIdentityProvider', 'Microsoft.Xbox.TCUI', 'Microsoft.GamingServices',
    'Microsoft.WindowsTerminal', 'Microsoft.WindowsCalculator', 'Microsoft.WindowsNotepad',
    'Microsoft.*Extension*', 'Microsoft.Windows.ShellExperienceHost', 'Microsoft.Windows.StartMenuExperienceHost'
)

$BloatCatalog = @(
    # --- Recomendado eliminar ---
    @{ N = 'Microsoft.BingNews';                     D = 'Noticias (MSN)';                          C = 'Recomendado' }
    @{ N = 'Microsoft.BingWeather';                  D = 'El Tiempo (MSN)';                         C = 'Recomendado' }
    @{ N = 'Microsoft.BingSearch';                   D = 'Búsqueda de Bing';                        C = 'Recomendado' }
    @{ N = 'Microsoft.Copilot';                      D = 'Copilot';                                 C = 'Recomendado' }
    @{ N = 'Microsoft.549981C3F5F10';                D = 'Cortana';                                 C = 'Recomendado' }
    @{ N = 'Microsoft.GetHelp';                      D = 'Obtener ayuda';                           C = 'Recomendado' }
    @{ N = 'Microsoft.Getstarted';                   D = 'Consejos';                                C = 'Recomendado' }
    @{ N = 'Microsoft.MicrosoftOfficeHub';           D = 'Microsoft 365 (anuncio de Office)';       C = 'Recomendado' }
    @{ N = 'Microsoft.MicrosoftSolitaireCollection'; D = 'Solitaire Collection (con anuncios)';     C = 'Recomendado' }
    @{ N = 'Microsoft.People';                       D = 'Contactos';                               C = 'Recomendado' }
    @{ N = 'Microsoft.PowerAutomateDesktop';         D = 'Power Automate';                          C = 'Recomendado' }
    @{ N = 'Microsoft.WindowsFeedbackHub';           D = 'Centro de opiniones';                     C = 'Recomendado' }
    @{ N = 'Microsoft.WindowsMaps';                  D = 'Mapas';                                   C = 'Recomendado' }
    @{ N = 'Microsoft.ZuneVideo';                    D = 'Películas y TV';                          C = 'Recomendado' }
    @{ N = 'Clipchamp.Clipchamp';                    D = 'Clipchamp (editor de vídeo en la nube)';  C = 'Recomendado' }
    @{ N = 'Microsoft.Windows.DevHome';              D = 'Dev Home (descontinuado)';                C = 'Recomendado' }
    @{ N = 'microsoft.windowscommunicationsapps';    D = 'Correo y Calendario (antiguos)';          C = 'Recomendado' }
    @{ N = 'Microsoft.SkypeApp';                     D = 'Skype (descontinuado)';                   C = 'Recomendado' }
    @{ N = 'Microsoft.MixedReality.Portal';          D = 'Portal de realidad mixta';                C = 'Recomendado' }
    @{ N = 'Microsoft.Microsoft3DViewer';            D = 'Visor 3D';                                C = 'Recomendado' }
    @{ N = 'Microsoft.Messaging';                    D = 'Mensajes';                                C = 'Recomendado' }
    @{ N = 'Microsoft.Wallet';                       D = 'Wallet';                                  C = 'Recomendado' }
    # --- Opcional: útiles para algunos ---
    @{ N = 'Microsoft.OutlookForWindows';            D = 'Outlook (nuevo)';                         C = 'Opcional' }
    @{ N = 'MSTeams';                                D = 'Microsoft Teams';                         C = 'Opcional' }
    @{ N = 'MicrosoftTeams';                         D = 'Microsoft Teams (personal, antiguo)';     C = 'Opcional' }
    @{ N = 'Microsoft.Todos';                        D = 'Microsoft To Do';                         C = 'Opcional' }
    @{ N = 'Microsoft.Office.OneNote';               D = 'OneNote';                                 C = 'Opcional' }
    @{ N = 'MicrosoftCorporationII.MicrosoftFamily'; D = 'Microsoft Family Safety';                 C = 'Opcional' }
    @{ N = 'MicrosoftCorporationII.QuickAssist';     D = 'Asistencia rápida (soporte remoto)';      C = 'Opcional' }
    @{ N = 'MicrosoftWindows.Client.WebExperience';  D = 'Widgets';                                 C = 'Opcional' }
    @{ N = 'Microsoft.ZuneMusic';                    D = 'Reproductor multimedia';                  C = 'Opcional' }
    @{ N = 'Microsoft.Windows.Photos';               D = 'Fotos';                                   C = 'Opcional' }
    @{ N = 'Microsoft.WindowsCamera';                D = 'Cámara';                                  C = 'Opcional' }
    @{ N = 'Microsoft.WindowsSoundRecorder';         D = 'Grabadora de sonido';                     C = 'Opcional' }
    @{ N = 'Microsoft.WindowsAlarms';                D = 'Reloj y alarmas';                         C = 'Opcional' }
    @{ N = 'Microsoft.MicrosoftStickyNotes';         D = 'Notas rápidas';                           C = 'Opcional' }
    @{ N = 'Microsoft.Paint';                        D = 'Paint';                                   C = 'Opcional' }
    @{ N = 'Microsoft.ScreenSketch';                 D = 'Recortes (capturas de pantalla)';         C = 'Opcional' }
    # --- Xbox: cuidado si juegas ---
    @{ N = 'Microsoft.GamingApp';                    D = 'App Xbox (NECESARIA para PC Game Pass)';  C = 'Xbox-cuidado' }
    @{ N = 'Microsoft.XboxGamingOverlay';            D = 'Xbox Game Bar (capturas, algunos juegos)';C = 'Xbox-cuidado' }
    @{ N = 'Microsoft.XboxSpeechToTextOverlay';      D = 'Voz a texto de Xbox';                     C = 'Xbox-cuidado' }
    @{ N = 'Microsoft.XboxApp';                      D = 'Xbox Console Companion (antigua)';        C = 'Xbox-cuidado' }
    # --- Terceros preinstalados ---
    @{ N = 'king.com.*';                             D = 'Juegos de King (Candy Crush...)';         C = 'Terceros' }
    @{ N = 'SpotifyAB.SpotifyMusic';                 D = 'Spotify (solo si no la instalaste tú)';   C = 'Terceros' }
    @{ N = 'Disney.*';                               D = 'Disney+';                                 C = 'Terceros' }
    @{ N = '*Facebook*';                             D = 'Facebook';                                C = 'Terceros' }
    @{ N = '*Instagram*';                            D = 'Instagram';                               C = 'Terceros' }
    @{ N = '*TikTok*';                               D = 'TikTok';                                  C = 'Terceros' }
    @{ N = 'AmazonVideo.PrimeVideo';                 D = 'Prime Video';                             C = 'Terceros' }
    @{ N = '*Netflix*';                              D = 'Netflix';                                 C = 'Terceros' }
    @{ N = '7EE7776C.LinkedInforWindows';            D = 'LinkedIn';                                C = 'Terceros' }
)

function Test-Protected([string]$Name) {
    foreach ($p in $ProtectedApps) { if ($Name -like $p) { return $true } }
    return $false
}

function ConvertFrom-Selection([string]$Text, [int]$Max) {
    $set = New-Object System.Collections.Generic.HashSet[int]
    foreach ($part in ($Text -split '[,;\s]+')) {
        if ($part -match '^(\d+)-(\d+)$') {
            $a = [int]$Matches[1]; $b = [int]$Matches[2]
            if ($a -gt $b) { $a, $b = $b, $a }
            for ($i = $a; $i -le $b; $i++) { if ($i -ge 1 -and $i -le $Max) { [void]$set.Add($i) } }
        } elseif ($part -match '^\d+$') {
            $i = [int]$part
            if ($i -ge 1 -and $i -le $Max) { [void]$set.Add($i) }
        }
    }
    return @($set | Sort-Object)
}

function Invoke-Bloatware {
    Write-Titulo "Eliminar bloatware"
    Write-Info "Buscando aplicaciones instaladas (puede tardar unos segundos)..."
    $installed   = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue)
    $provisioned = @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue)

    $found = @()
    foreach ($item in $BloatCatalog) {
        $hasUser = @($installed   | Where-Object { $_.Name -like $item.N -and -not (Test-Protected $_.Name) }).Count -gt 0
        $hasProv = @($provisioned | Where-Object { $_.DisplayName -like $item.N -and -not (Test-Protected $_.DisplayName) }).Count -gt 0
        if ($hasUser -or $hasProv) { $found += [pscustomobject]@{ N = $item.N; D = $item.D; C = $item.C } }
    }

    if ($found.Count -eq 0) { Write-Ok "No se ha encontrado bloatware de la lista. ¡Limpio!"; return }

    $colors = @{ 'Recomendado' = 'Green'; 'Opcional' = 'White'; 'Xbox-cuidado' = 'Yellow'; 'Terceros' = 'Magenta' }
    Write-Host ""
    for ($i = 0; $i -lt $found.Count; $i++) {
        $f = $found[$i]
        Write-Host ("  {0,3}) [{1,-12}] {2}" -f ($i + 1), $f.C, $f.D) -ForegroundColor $colors[$f.C]
    }
    Write-Host ""
    Write-Info "Enlace Móvil, Store, winget, Seguridad de Windows, Calculadora, Terminal y los componentes"
    Write-Info "de Xbox necesarios para iniciar sesión en juegos están protegidos y nunca se listan."
    Write-Host ""
    Write-Host "  Escribe los números separados por comas o rangos (ej: 1,3,5-8)"
    Write-Host "  R = todas las 'Recomendado'    Enter = cancelar"
    $sel = Read-Host "Selección"
    if ([string]::IsNullOrWhiteSpace($sel)) { Write-Info "Cancelado."; return }

    if ($sel.Trim().ToUpper() -eq 'R') {
        $chosen = @($found | Where-Object { $_.C -eq 'Recomendado' })
    } else {
        $chosen = @(ConvertFrom-Selection $sel $found.Count | ForEach-Object { $found[$_ - 1] })
    }
    if ($chosen.Count -eq 0) { Write-Info "No se ha seleccionado nada válido."; return }

    Write-Host ""
    Write-Host "Se eliminarán:" -ForegroundColor Cyan
    $chosen | ForEach-Object { Write-Host "   - $($_.D)" }
    if (@($chosen | Where-Object { $_.C -eq 'Xbox-cuidado' }).Count -gt 0) {
        Write-Aviso "Has incluido componentes de Xbox: sin la app Xbox no podrás usar PC Game Pass y sin Game Bar"
        Write-Aviso "algunos juegos pueden mostrar avisos al pulsar Win+G."
    }
    if (-not (Confirm-Strong "Las apps eliminadas se pueden reinstalar gratis desde Microsoft Store. ¿Continuar?")) {
        Write-Info "Cancelado."; return
    }
    if (-not (Ensure-Safety)) { return }

    foreach ($c in $chosen) {
        Write-Host "  -> $($c.D)" -ForegroundColor Cyan
        foreach ($p in @($installed | Where-Object { $_.Name -like $c.N })) {
            if (Test-Protected $p.Name) { Write-Info "Protegida, se omite: $($p.Name)"; continue }
            try {
                Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop
                Write-Ok "Eliminada: $($p.Name)"
                Add-Content -Path $AppsLogFile -Value ("{0:s}`t{1}`t{2}" -f (Get-Date), $p.Name, $c.D) -Encoding UTF8
            } catch {
                Write-Aviso "No se pudo eliminar $($p.Name): $($_.Exception.Message)"
            }
        }
        # Evita que se reinstale para usuarios nuevos o tras grandes actualizaciones
        foreach ($pp in @($provisioned | Where-Object { $_.DisplayName -like $c.N })) {
            if (Test-Protected $pp.DisplayName) { continue }
            try {
                Remove-AppxProvisionedPackage -Online -PackageName $pp.PackageName -ErrorAction Stop | Out-Null
                Write-Ok "Desaprovisionada: $($pp.DisplayName)"
            } catch {
                Write-Aviso "No se pudo desaprovisionar $($pp.DisplayName): $($_.Exception.Message)"
            }
        }
    }
    Write-Info "Lista de apps eliminadas guardada en: $AppsLogFile"
}

# ----------------------------------------------------------------------------
#  6) OneDrive
# ----------------------------------------------------------------------------
function Invoke-OneDrive {
    Write-Titulo "Desinstalar OneDrive"
    $shell = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
    $sf = Get-ItemProperty -Path $shell -ErrorAction SilentlyContinue
    $redirected = @()
    foreach ($n in 'Desktop', 'Personal', 'My Pictures', 'My Music', 'My Video') {
        if ($sf.$n -and ($sf.$n -like '*OneDrive*')) { $redirected += "$n -> $($sf.$n)" }
    }
    if ($redirected.Count -gt 0) {
        Write-Aviso "Algunas carpetas están dentro de OneDrive (copia de seguridad de carpetas activada):"
        $redirected | ForEach-Object { Write-Aviso "   $_" }
        Write-Aviso "ANTES de desinstalar: abre OneDrive > Configuración > Sincronización y copia de seguridad >"
        Write-Aviso "Administrar copia de seguridad y DETÉN la copia de cada carpeta, para devolverlas a su sitio."
    }
    Write-Info "Tus archivos NO se borran: los que estén descargados seguirán en $env:USERPROFILE\OneDrive."
    Write-Info "Los marcados como 'solo en línea' (icono de nube) NO estarán en el PC: descárgalos antes."
    if (-not (Confirm-Strong "¿Desinstalar OneDrive?")) { Write-Info "Cancelado."; return }
    if (-not (Ensure-Safety)) { return }

    Get-Process -Name OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    $done = $false
    $un = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\OneDriveSetup.exe' -ErrorAction SilentlyContinue
    if ($un -and $un.UninstallString) {
        try {
            Start-Process -FilePath 'cmd.exe' -ArgumentList "/c `"$($un.UninstallString)`"" -Wait -WindowStyle Hidden
            $done = $true
        } catch {}
    }
    if (-not $done -and (Get-Command winget -ErrorAction SilentlyContinue)) {
        & winget uninstall --id Microsoft.OneDrive -e --silent --accept-source-agreements
        $done = ($LASTEXITCODE -eq 0)
    }
    if (-not $done) {
        foreach ($exe in "$env:SystemRoot\System32\OneDriveSetup.exe", "$env:SystemRoot\SysWOW64\OneDriveSetup.exe") {
            if (Test-Path $exe) { Start-Process $exe -ArgumentList '/uninstall' -Wait; $done = $true; break }
        }
    }
    if ($done) { Write-Ok "OneDrive desinstalado." } else { Write-Aviso "No se encontró el desinstalador de OneDrive (puede que ya no esté)." }

    if (Ask-YesNo "¿Impedir que Windows vuelva a usar/reinstalar OneDrive (directiva)?" $true) {
        Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' 'DisableFileSyncNGSC' 1
        Save-Journal
        Write-Ok "Directiva aplicada (se revierte con la opción 'Revertir')."
    }
}

# ----------------------------------------------------------------------------
#  8) Revertir
# ----------------------------------------------------------------------------
function Invoke-Restore {
    Write-Titulo "Revertir cambios"
    if ($script:Journal.Count -eq 0) { Write-Info "No hay cambios registrados que revertir."; return }
    Write-Info "Hay $($script:Journal.Count) cambios registrados (registro, servicios y tareas)."
    Write-Info "Las apps eliminadas no se reinstalan automáticamente: búscalas en Microsoft Store"
    Write-Info "(la lista está en $AppsLogFile)."
    if (-not (Confirm-Strong "¿Devolver el registro, servicios y tareas a su estado original?")) { Write-Info "Cancelado."; return }

    $entries = @($script:Journal.ToArray())
    [array]::Reverse($entries)
    $errors = 0
    foreach ($e in $entries) {
        try {
            switch ($e.Type) {
                'Reg' {
                    if ($e.Existed) {
                        $v = $e.OldValue
                        switch ($e.OldKind) {
                            'Binary'      { $v = [byte[]]@($v) }
                            'MultiString' { $v = [string[]]@($v) }
                            'DWord'       { $v = [int]$v }
                            'QWord'       { $v = [long]$v }
                        }
                        if (-not (Test-Path -LiteralPath $e.Path)) { New-Item -Path $e.Path -Force | Out-Null }
                        New-ItemProperty -LiteralPath $e.Path -Name $e.Name -Value $v -PropertyType $e.OldKind -Force -ErrorAction Stop | Out-Null
                    } else {
                        Remove-ItemProperty -LiteralPath $e.Path -Name $e.Name -ErrorAction SilentlyContinue
                    }
                }
                'Service' {
                    if ($null -ne $e.OldStart) {
                        switch ([int]$e.OldStart) {
                            2 {
                                if ($e.OldDelayed -eq 1) { & sc.exe config $e.Name start= delayed-auto | Out-Null }
                                else { Set-Service -Name $e.Name -StartupType Automatic -ErrorAction Stop }
                                Start-Service -Name $e.Name -ErrorAction SilentlyContinue
                            }
                            3 { Set-Service -Name $e.Name -StartupType Manual -ErrorAction Stop }
                            4 { Set-Service -Name $e.Name -StartupType Disabled -ErrorAction Stop }
                            default { Set-ItemProperty -LiteralPath $e.Path -Name Start -Value ([int]$e.OldStart) -ErrorAction Stop }
                        }
                        Write-Ok "Servicio restaurado: $($e.Name)"
                    }
                }
                'Task' {
                    if ($e.WasEnabled) {
                        Enable-ScheduledTask -TaskPath $e.Path -TaskName $e.Name -ErrorAction Stop | Out-Null
                        Write-Ok "Tarea reactivada: $($e.Name)"
                    }
                }
            }
        } catch {
            $errors++
            Write-Aviso "No se pudo restaurar $($e.Type) $($e.Path)\$($e.Name): $($_.Exception.Message)"
        }
    }
    $archived = Join-Path $BaseDir ("cambios_revertidos_{0:yyyyMMdd_HHmmss}.json" -f (Get-Date))
    Move-Item -Path $JournalFile -Destination $archived -Force -ErrorAction SilentlyContinue
    $script:Journal.Clear()
    if ($errors -eq 0) { Write-Ok "Todo revertido. Reinicia el equipo para completar." }
    else { Write-Aviso "Revertido con $errors errores. Si algo falla, usa el punto de restauración (rstrui.exe)." }
}

# ----------------------------------------------------------------------------
#  9) Estado
# ----------------------------------------------------------------------------
function Show-Status {
    Write-Titulo "Estado actual"
    function Get-Val($p, $n) { (Get-ItemProperty -LiteralPath $p -Name $n -ErrorAction SilentlyContinue).$n }
    $tel = Get-Val 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry'
    $diag = Get-Service DiagTrack -ErrorAction SilentlyContinue
    $rows = @(
        @('Telemetría (directiva AllowTelemetry)', $(if ($null -eq $tel) { 'Por defecto de Windows' } else { "$tel (0/1 = mínimo)" })),
        @('Servicio DiagTrack', $(if ($diag) { "$($diag.Status) / $($diag.StartType)" } else { 'No existe' })),
        @('ID de publicidad', $(if ((Get-Val 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled') -eq 0) { 'Desactivado' } else { 'Activado' })),
        @('Bing en la búsqueda', $(if ((Get-Val 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled') -eq 0) { 'Desactivado' } else { 'Activado' })),
        @('Recall', $(if ((Get-Val 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI' 'AllowRecallEnablement') -eq 0) { 'Bloqueado' } else { 'Por defecto' })),
        @('Telemetría de Edge', $(if ((Get-Val 'HKLM:\SOFTWARE\Policies\Microsoft\Edge' 'DiagnosticData') -eq 0) { 'Desactivada' } else { 'Por defecto' })),
        @('Cambios registrados (revertibles)', "$($script:Journal.Count)")
    )
    foreach ($r in $rows) { Write-Host ("  {0,-38} {1}" -f $r[0], $r[1]) }
    Write-Host ""
    Write-Info "Carpeta de copias y logs: $BaseDir"
}

# ----------------------------------------------------------------------------
#  Menú
# ----------------------------------------------------------------------------
function Show-Menu {
    Clear-Host
    Write-Host "==============================================================" -ForegroundColor Cyan
    Write-Host "   Win11-Privacidad v$ScriptVersion - telemetría, privacidad y bloatware" -ForegroundColor Cyan
    Write-Host "==============================================================" -ForegroundColor Cyan
    Write-Host "  1) Desactivar telemetría"
    Write-Host "  2) Privacidad: anuncios, sugerencias, búsqueda Bing, widgets"
    Write-Host "  3) Desactivar Copilot, Recall y la IA en la nube"
    Write-Host "  4) Microsoft Edge: sin telemetría ni segundo plano (+ cómo quitarlo)"
    Write-Host "  5) Eliminar bloatware (tú eliges qué)"
    Write-Host "  6) Desinstalar OneDrive"
    Write-Host ""
    Write-Host "  7) RECOMENDADO: aplicar 1 + 2 + 3 + 4 (no borra ninguna app)" -ForegroundColor Green
    Write-Host ""
    Write-Host "  8) Revertir todos los cambios" -ForegroundColor Yellow
    Write-Host "  9) Ver estado"
    Write-Host "  P) Crear un punto de restauración ahora"
    Write-Host "  0) Salir"
    Write-Host ""
}

Write-Host ""
Write-Host "Este script no toca Enlace Móvil, Store, Windows Update, Defender ni los servicios de Xbox." -ForegroundColor Gray

$needsReboot = $false
while ($true) {
    Show-Menu
    $op = (Read-Host "Elige una opción").Trim().ToUpper()
    switch ($op) {
        '1' { if (Ensure-Safety) { Invoke-Telemetry; $needsReboot = $true }; Pause-Menu }
        '2' { if (Ensure-Safety) { Invoke-Privacy;   $needsReboot = $true }; Pause-Menu }
        '3' { if (Ensure-Safety) { Invoke-AI;        $needsReboot = $true }; Pause-Menu }
        '4' { if (Ensure-Safety) { Invoke-Edge;      $needsReboot = $true }; Pause-Menu }
        '5' { Invoke-Bloatware; Pause-Menu }
        '6' { Invoke-OneDrive; $needsReboot = $true; Pause-Menu }
        '7' {
            if (Ensure-Safety) {
                Invoke-Telemetry; Invoke-Privacy; Invoke-AI; Invoke-Edge
                $needsReboot = $true
                Write-Host ""; Write-Ok "Configuración recomendada aplicada."
            }
            Pause-Menu
        }
        '8' { Invoke-Restore; $needsReboot = $true; Pause-Menu }
        '9' { Show-Status; Pause-Menu }
        'P' { if (New-RestorePoint) { $script:SafetyDone = $true }; Pause-Menu }
        '0' { break }
        default { Write-Aviso "Opción no válida."; Start-Sleep -Milliseconds 800 }
    }
    if ($op -eq '0') { break }
}

Save-Journal
if ($needsReboot) {
    Write-Host ""
    Write-Aviso "Reinicia el equipo para que todos los cambios surtan efecto."
    if (Ask-YesNo "¿Reiniciar ahora?" $false) {
        try { Stop-Transcript | Out-Null } catch {}
        Restart-Computer
    }
}
try { Stop-Transcript | Out-Null } catch {}
