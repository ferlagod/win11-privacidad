# Lista completa de cambios

Todo lo que el script puede tocar, para que lo revises antes de ejecutarlo.
Todo lo de esta lista (registro, servicios y tareas) se revierte con la opción 8.
Las apps eliminadas no: se reinstalan desde la Store.

Abreviaturas: `HKLM` = `HKEY_LOCAL_MACHINE`, `HKCU` = `HKEY_CURRENT_USER`.

## 1. Telemetría

### Registro

| Clave | Valor | Dato |
|---|---|---|
| `HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection` | `AllowTelemetry` | 0 |
| | `MaxTelemetryAllowed` | 0 |
| | `AllowDeviceNameInTelemetry` | 0 |
| | `DoNotShowFeedbackNotifications` | 1 |
| | `LimitDiagnosticLogCollection` | 1 |
| | `LimitDumpCollection` | 1 |
| `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection` | `AllowTelemetry` | 0 |
| `HKLM\SOFTWARE\Policies\Microsoft\SQMClient\Windows` | `CEIPEnable` | 0 |
| `HKLM\SOFTWARE\Policies\Microsoft\Windows\AppCompat` | `AITEnable` | 0 |
| | `DisableInventory` | 1 |
| | `DisableUAR` | 1 |
| `HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting` | `Disabled` | 1 |
| `HKLM\SOFTWARE\Policies\Microsoft\Windows\TabletPC` | `PreventHandwritingDataSharing` | 1 |
| `HKLM\SOFTWARE\Policies\Microsoft\Windows\HandwritingErrorReports` | `PreventHandwritingErrorReports` | 1 |
| `HKLM\SOFTWARE\Policies\Microsoft\MRT` | `DontReportInfectionInformation` | 1 |
| `HKCU\Software\Microsoft\Siuf\Rules` | `NumberOfSIUFInPeriod` | 0 |
| `HKLM\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization` | `DODownloadMode` | 0 (sin P2P) |
| `HKCU\Software\Policies\Microsoft\Office\16.0\Common\ClientTelemetry` | `DisableTelemetry` / `SendTelemetry` | 1 / 3 |
| `HKCU\Software\Policies\Microsoft\Office\Common\ClientTelemetry` | `DisableTelemetry` / `SendTelemetry` | 1 / 3 |
| `HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment` | `POWERSHELL_TELEMETRY_OPTOUT` | "1" |
| | `DOTNET_CLI_TELEMETRY_OPTOUT` | "1" |

### Servicios (pasan a Deshabilitado)

- `DiagTrack`: Experiencias del usuario y telemetría asociadas
- `dmwappushservice`: enrutamiento de mensajes push WAP

### Tareas programadas (se desactivan si existen)

- `\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser`
- `\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser Exp`
- `\Microsoft\Windows\Application Experience\ProgramDataUpdater`
- `\Microsoft\Windows\Application Experience\MareBackup`
- `\Microsoft\Windows\Autochk\Proxy`
- `\Microsoft\Windows\Customer Experience Improvement Program\Consolidator`
- `\Microsoft\Windows\Customer Experience Improvement Program\UsbCeip`
- `\Microsoft\Windows\DiskDiagnostic\Microsoft-Windows-DiskDiagnosticDataCollector`
- `\Microsoft\Windows\Feedback\Siuf\DmClient`
- `\Microsoft\Windows\Feedback\Siuf\DmClientOnScenarioDownload`
- `\Microsoft\Windows\Windows Error Reporting\QueueReporting`

## 2. Privacidad

| Clave | Valor | Dato |
|---|---|---|
| `HKLM\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo` | `DisabledByGroupPolicy` | 1 |
| `HKCU\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo` | `Enabled` | 0 |
| `HKCU\Software\Policies\Microsoft\Windows\CloudContent` | `DisableTailoredExperiencesWithDiagnosticData` | 1 |
| `HKCU\Software\Microsoft\Windows\CurrentVersion\Privacy` | `TailoredExperiencesWithDiagnosticDataEnabled` | 0 |
| `HKLM\SOFTWARE\Policies\Microsoft\Windows\System` | `EnableActivityFeed` / `PublishUserActivities` / `UploadUserActivities` | 0 |
| `HKCU\Software\Microsoft\InputPersonalization` | `RestrictImplicitInkCollection` / `RestrictImplicitTextCollection` | 1 |
| `HKCU\Software\Microsoft\InputPersonalization\TrainedDataStore` | `HarvestContacts` | 0 |
| `HKCU\Software\Microsoft\Personalization\Settings` | `AcceptedPrivacyPolicy` | 0 |
| `HKCU\Software\Microsoft\Input\TIPC` | `Enabled` | 0 |
| `HKCU\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy` | `HasAccepted` | 0 |
| `HKCU\Control Panel\International\User Profile` | `HttpAcceptLanguageOptOut` | 1 |
| `HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager` | `SilentInstalledAppsEnabled`, `SystemPaneSuggestionsEnabled`, `SoftLandingEnabled`, `OemPreInstalledAppsEnabled`, `PreInstalledAppsEnabled`, `PreInstalledAppsEverEnabled`, `FeatureManagementEnabled`, `RotatingLockScreenOverlayEnabled`, `SubscribedContent-310093Enabled`, `-338387`, `-338388`, `-338389`, `-338393`, `-353694`, `-353696`, `-353698` | 0 |
| `HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent` | `DisableWindowsConsumerFeatures` / `DisableConsumerAccountStateContent` / `DisableCloudOptimizedContent` | 1 |
| `HKCU\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement` | `ScoobeSystemSettingEnabled` | 0 |
| `HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced` | `Start_IrisRecommendations` / `Start_AccountNotifications` / `Start_TrackProgs` / `ShowSyncProviderNotifications` | 0 |
| `HKCU\Software\Policies\Microsoft\Windows\Explorer` | `DisableSearchBoxSuggestions` | 1 |
| `HKCU\Software\Microsoft\Windows\CurrentVersion\Search` | `BingSearchEnabled` | 0 |
| `HKLM\SOFTWARE\Policies\Microsoft\Windows\Windows Search` | `AllowCloudSearch` / `ConnectedSearchUseWeb` | 0 |
| | `DisableWebSearch` | 1 |
| `HKCU\Software\Microsoft\Windows\CurrentVersion\SearchSettings` | `IsDynamicSearchBoxEnabled` / `IsMSACloudSearchEnabled` / `IsAADCloudSearchEnabled` / `IsDeviceSearchHistoryEnabled` | 0 |
| `HKLM\SOFTWARE\Policies\Microsoft\Dsh` | `AllowNewsAndInterests` | 0 |

Solo si respondes que sí:

| Clave | Valor | Dato |
|---|---|---|
| `HKLM\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors` | `DisableLocation` | 1 |
| `HKLM\SOFTWARE\Policies\Microsoft\FindMyDevice` | `AllowFindMyDevice` | 0 |

## 3. Copilot, Recall e IA

| Clave | Valor | Dato |
|---|---|---|
| `HKCU\Software\Policies\Microsoft\Windows\WindowsCopilot` | `TurnOffWindowsCopilot` | 1 |
| `HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot` | `TurnOffWindowsCopilot` | 1 |
| `HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced` | `ShowCopilotButton` | 0 |
| `HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsAI` | `DisableAIDataAnalysis` / `DisableClickToDo` | 1 |
| | `AllowRecallEnablement` | 0 |
| `HKCU\Software\Policies\Microsoft\Windows\WindowsAI` | `DisableAIDataAnalysis` / `DisableClickToDo` | 1 |
| `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint` | `DisableCocreator` / `DisableGenerativeFill` / `DisableImageCreator` | 1 |
| `HKLM\SOFTWARE\Policies\WindowsNotepad` | `DisableAIFeatures` | 1 |

## 4. Edge

Todo en `HKLM\SOFTWARE\Policies\Microsoft\Edge`:

| Valor | Dato |
|---|---|
| `DiagnosticData`, `MetricsReportingEnabled`, `PersonalizationReportingEnabled`, `UserFeedbackAllowed` | 0 |
| `StartupBoostEnabled`, `BackgroundModeEnabled` | 0 |
| `HubsSidebarEnabled`, `EdgeShoppingAssistantEnabled`, `ShowRecommendationsEnabled`, `SpotlightExperiencesAndRecommendationsEnabled`, `ShowMicrosoftRewards` | 0 |
| `ConfigureDoNotTrack`, `HideFirstRunExperience` | 1 |

## 5. Bloatware

Solo se muestran las que tengas instaladas, y solo se quitan las que elijas. Se
eliminan para todos los usuarios y se desaprovisionan para que no vuelvan en cuentas
nuevas. La lista completa está en `$BloatCatalog` dentro del script.

Protegidas (nunca se quitan aunque coincidan con un patrón): `Microsoft.YourPhone`,
`MicrosoftWindows.CrossDevice`, `Microsoft.WindowsStore`, `Microsoft.StorePurchaseApp`,
`Microsoft.DesktopAppInstaller`, `Microsoft.SecHealthUI`, `Microsoft.VCLibs*`,
`Microsoft.UI.Xaml*`, `Microsoft.NET.*`, `Microsoft.WindowsAppRuntime*`,
`Microsoft.XboxIdentityProvider`, `Microsoft.Xbox.TCUI`, `Microsoft.GamingServices`,
`Microsoft.WindowsTerminal`, `Microsoft.WindowsCalculator`, `Microsoft.WindowsNotepad`,
`Microsoft.*Extension*` (códecs), shell del menú Inicio.

## 6. OneDrive

Ejecuta el desinstalador oficial (o `winget uninstall Microsoft.OneDrive`). Opcionalmente:

| Clave | Valor | Dato |
|---|---|---|
| `HKLM\SOFTWARE\Policies\Microsoft\Windows\OneDrive` | `DisableFileSyncNGSC` | 1 |
