# Win11-Privacidad

Script en PowerShell para quitarle a Windows 11 la telemetría, los anuncios y las apps
que nadie pidió, **sin romper nada y pudiendo deshacerlo todo**.

Lo hice porque sigo necesitando Windows para jugar y para algunos programas, pero no
soporto la cantidad de datos que manda a Microsoft ni que me metan Candy Crush en el
menú Inicio. Probé varios "debloaters" y casi todos tienen el mismo problema: o tocan
demasiado (y luego falla Windows Update, la Store o el Game Pass) o no hay forma
razonable de volver atrás. Este intenta ser lo contrario: conservador, transparente y
reversible.

> ⚠️ Úsalo bajo tu responsabilidad. Lo he hecho con cuidado, pero cada equipo es un
> mundo. Lee qué hace (está todo en [docs/CAMBIOS.md](docs/CAMBIOS.md)) antes de
> ejecutar nada como administrador, sea este script o cualquier otro.

## Qué hace

Menú interactivo, cada bloque se aplica por separado:

| # | Opción | Resumen |
|---|--------|---------|
| 1 | Telemetría | Datos de diagnóstico al mínimo, servicio `DiagTrack` desactivado, tareas de recopilación (CEIP, Compatibility Appraiser...) desactivadas, informes de errores, telemetría de Office/PowerShell/.NET |
| 2 | Privacidad | ID de publicidad, experiencias personalizadas, historial de actividad, sugerencias y anuncios en Inicio/Configuración/pantalla de bloqueo, apps que se instalan solas, Bing en la búsqueda, widgets. Ubicación y "Encontrar mi dispositivo" solo si dices que sí |
| 3 | IA | Copilot, Recall, Click to Do y la IA en la nube de Paint y Bloc de notas |
| 4 | Edge | Sin telemetría, sin arranque rápido ni procesos en segundo plano, sin barra lateral ni "asistente de compras" |
| 5 | Bloatware | Lista lo que tienes instalado y **tú eliges** qué quitar |
| 6 | OneDrive | Desinstalación, avisándote antes si tienes carpetas sincronizadas |
| 7 | Recomendado | 1 + 2 + 3 + 4. No borra ninguna app |
| 8 | Revertir | Deja registro, servicios y tareas exactamente como estaban |

## Qué NO toca (a propósito)

- **Enlace Móvil / Phone Link**, la plataforma de dispositivos conectados y el portapapeles entre dispositivos.
- **Juegos**: servicios de Xbox, Gaming Services, Xbox Identity Provider y Xbox TCUI. La app de Xbox y la Game Bar aparecen en la lista de bloatware marcadas con aviso, pero nunca se quitan solas.
- Microsoft Store, winget, Windows Update, Defender, Firewall, SmartScreen.
- WebView2 (lo usan launchers de juegos y un montón de programas).
- El archivo `hosts` y el firewall. Bloquear dominios de Microsoft suena bien, pero rompe actualizaciones, Store e inicio de sesión de Xbox, y Defender lo marca como amenaza.

## Cómo se protege

- Crea un **punto de restauración** antes del primer cambio.
- Exporta a `.reg` las ramas del registro que va a modificar.
- Apunta el **valor original** de cada clave, servicio y tarea en `C:\ProgramData\Win11Privacidad\cambios.json`. La opción 8 usa ese archivo para revertir. Si ejecutas el script varias veces, se conserva siempre el valor de antes de la primera vez.
- Guarda un log de cada sesión en `C:\ProgramData\Win11Privacidad\logs`.
- Para borrar apps o desinstalar OneDrive hay que escribir `SI`.

## Uso

1. Descarga la última versión desde [Releases](../../releases) y descomprímela.
2. (Opcional, pero recomendable) comprueba el hash:
   ```powershell
   Get-FileHash .\Win11-Privacidad.ps1 -Algorithm SHA256
   ```
   y compáralo con el que aparece en la release.
3. Doble clic en **`Ejecutar.cmd`**. Pedirá permisos de administrador.

   O desde PowerShell, en la carpeta del script:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\Win11-Privacidad.ps1
   ```
4. Si no sabes por dónde empezar: opción **7** y luego, si quieres, la **5**.
5. Reinicia.

Ejecútalo desde tu propia cuenta (si es administradora). Si usas una cuenta estándar y
te elevas con otra, los ajustes "de usuario" se aplicarían al perfil del administrador.

No hay versión `irm ... | iex` y no la va a haber: un script de privacidad no debería
enseñar a ejecutar código remoto como administrador sin mirarlo.

### Sobre SmartScreen / Defender

Al ser un script sin firmar que cambia directivas, Windows puede avisarte. Es normal.
Si te da desconfianza (bien hecho), lee el código: es un solo archivo, sin
dependencias y sin descargar nada de Internet.

## Deshacer

- **Opción 8** del menú: restaura registro, servicios y tareas.
- Las apps eliminadas se reinstalan gratis desde Microsoft Store. La lista de lo que
  quitaste está en `C:\ProgramData\Win11Privacidad\apps_eliminadas.txt`.
- Y si algo va muy mal: `rstrui.exe` y eliges el punto de restauración "Win11-Privacidad".

## Preguntas habituales

**¿Desactiva la telemetría al 100 %?**
No. En Windows 11 Home/Pro el mínimo es el nivel "Requerido"; el nivel 0 real solo
existe en Enterprise/Education. Lo que sí hace es apagar todo lo opcional y el servicio
que lo envía.

**¿Puedo quitar Edge?**
Si vives en el Espacio Económico Europeo, sí, de forma oficial: Configuración >
Aplicaciones > Aplicaciones instaladas > Microsoft Edge > Desinstalar. La opción 4 te
abre esa pantalla. Fuera del EEE no lo fuerzo, porque los métodos no oficiales suelen
romperse con las actualizaciones.

**Edge dice "Administrado por tu organización".**
Es lo que muestra cuando hay directivas aplicadas. No hay ninguna organización, eres tú.

**¿Tengo que volver a ejecutarlo tras una actualización grande?**
Las directivas suelen sobrevivir, pero las actualizaciones de versión (24H2 → 25H2,
etc.) a veces reinstalan apps. Vuelve a pasar la opción 5 y listo.

## Requisitos

- Windows 11 (probado en 24H2/25H2). Debería funcionar en Windows 10 en su mayor
  parte, pero no está pensado para él.
- Windows PowerShell 5.1 (viene con Windows). No necesita PowerShell 7.

## Contribuir

Si algo falla, abre un [issue](../../issues) con tu versión de Windows (`winver`) y el
log de `C:\ProgramData\Win11Privacidad\logs`. Si propones añadir una clave de
registro, enlaza la documentación de Microsoft o explica de dónde sale, y que no rompa
nada de la lista de "qué NO toca".

## Licencia

[MIT](LICENSE)
