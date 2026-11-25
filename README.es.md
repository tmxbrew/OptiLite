# OptiLite

> **Optimizador local de Windows 10/11 con interfaz gráfica moderna.**
> Un solo archivo PowerShell · sin descargas · sin instalaciones · sin telemetría · todo reversible.

**Prefer English? → [README.md](README.md)**

```
┌──────────────┬─────────────────────────────────────────┐
│  OPTILITE    │  Título del panel             [buscar]  │
│  ● Resumen   │  ┌─────────────────────────────────────┐ │
│  ● Rendim.   │  │ Tarjeta de ajuste     ( interruptor )│ │
│  ● Juegos    │  │ Tarjeta de ajuste     ( interruptor )│ │
│  ● Privac.   │  │ Tarjeta de limpieza   [ botón ]      │ │
│  ● Limpieza  │  │ Tarjeta de perfil     [ aplicar ]    │ │
│  ● Perfiles  │  └─────────────────────────────────────┘ │
│  RAM · Proc  │  Barra de estado · aviso de reinicio     │
└──────────────┴─────────────────────────────────────────┘
```

## Características

- **26 ajustes reversibles** entre Rendimiento, Juegos y Privacidad: cada uno
  es un interruptor que lee el estado *real* del sistema y aplica el cambio al
  instante.
- **Idioma ES/EN conmutable**: en la barra superior hay un selector que cambia
  toda la interfaz (paneles, tarjetas, descripciones, mensajes) al instante;
  la preferencia queda guardada en `%LOCALAPPDATA%\OptiLite\optilite.json`
  y el español es el idioma por defecto.
- **Gestor de programas de inicio**: el panel *Inicio* lista todo lo que
  arranca con Windows (claves Run HKLM/HKCU + carpeta Inicio) y permite
  desactivar/reactivar cada entrada con un interruptor — nada se borra, así
  que siempre es reversible.
- **Pila de deshacer**: cada cambio aplicado se guarda en una pila de hasta
  50 entradas (`optilite-undo.json`); *Deshacer último cambio* los revierte
  uno por uno.
- **Exportar / importar copia de seguridad**: guarda el estado de todos los
  ajustes en un `.json` y reaplícalo cuando quieras o en otro PC.
- **Modo vista previa**: activa *Vista previa* y los interruptores/perfiles
  te dirán exactamente qué *cambiarían* — sin tocar nada.
- **Perfiles de un clic**: Competitivo (Valorant/CS2), Juegos AAA, Cloud/Xbox y
  *Restaurar Windows* (devuelve todos los ajustes a los valores de fábrica).
- **Punto de restauración propio**: antes de aplicar cualquier perfil se guarda
  una instantánea JSON de todos los ajustes, reversible con un clic.
- **Diagnóstico en el Resumen**: salud del disco (SMART), desgaste de batería,
  servicios en ejecución y top-5 de procesos por RAM.
- **Limpieza**: carpetas TEMP, Prefetch, logs CBS, informes de errores (WER),
  caché de Windows Update, Papelera y caché DNS.
- **Plan de energía Gaming Ultimate** (duplica Ultimate Performance, desactiva
  Core Parking, CPU mínima al 100% en corriente).
- **Monitor en vivo**: RAM y número de procesos se actualizan cada 5 segundos.
- **Búsqueda que ignora acentos** en todos los ajustes y acciones.
- **Conocimiento de anti-cheats**: Riot Vanguard y FACEIT se activan/desactivan
  con un interruptor; si el software no está instalado, el interruptor queda
  en gris automáticamente.
- **Cero acceso a red.** Todo es local; los únicos archivos que escribe son un
  registro y varios JSON de estado en `%LOCALAPPDATA%\OptiLite\`.

## Inicio rápido

1. Descarga **`OptiLite.ps1`** (o clona el repositorio).
2. Si el archivo quedó marcado al descargarlo, desbloquéalo una vez:
   ```powershell
   Unblock-File .\OptiLite.ps1
   ```
3. Clic derecho → **Ejecutar con PowerShell** (se auto-eleva y muestra el
   aviso de UAC), o desde un terminal:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\OptiLite.ps1
   ```

> **Consejo:** el panel *Resumen* incluye la acción **"Acceso en Escritorio"**,
> que crea un acceso directo que siempre abre OptiLite con permisos de
> administrador.

## Requisitos

| | |
|---|---|
| SO | Windows 10 (1809+) o Windows 11, ediciones de escritorio (requiere WPF — sin soporte en Server Core / WinPE) |
| PowerShell | 5.1 o superior (preinstalado en Windows 10/11) |
| Permisos | Administrador (lo solicita automáticamente vía UAC) |

## Paneles y catálogo

### Rendimiento

| Ajuste | OFF (recomendado para FPS) | Notas |
|---|---|---|
| VBS / Integridad de memoria | ~5–8% de FPS en la mayoría de equipos | Pide reinicio; los anti-cheats siguen funcionando |
| Efectos visuales | Animaciones/transparencia al mínimo | Por usuario, instantáneo |
| SysMain (Superfetch) | Sin servicio de precarga | Poco útil con SSD |
| Windows Search (indexación) | Sin indexado en segundo plano | El buscador será más lento |
| Hibernación e Inicio rápido | Libera `hiberfil.sys` (GB en disco) | Instantáneo |
| Apps en segundo plano | Las apps UWP no siguen abiertas | Los programas de escritorio no se ven afectados |
| TCP Autotuning | Off fija la ventana TCP | Reinicio; suele *bajar* el throughput — solo para pruebas |
| Nagle / TcpAckFrequency | Envío inmediato de paquetes | Reinicio; menos latencia en juegos online |
| **Plan de energía** *(acción)* | Plan Gaming Ultimate: Core Parking off, CPU mín. 100% | Botón, no interruptor |

### Juegos

| Ajuste | Qué hace |
|---|---|
| Riot Vanguard (Valorant) | Activa/desactiva el driver kernel `vgk` y el servicio `vgc` (requiere reinicio) |
| FACEIT Anti-Cheat (CS2) | Activación/desactivación instantánea de los servicios FACEIT |
| Servicios Xbox y Cloud Gaming | Interruptor de Xbox Live / GamingServices — OFF si no usas Game Pass |
| Modo Juego (Game Mode) | Prioridad de CPU/GPU para el juego en primer plano (recomendado ON) |
| Game Bar y DVR | Desactiva la grabación en segundo plano (OBS no se afecta) |
| Optimizaciones de pantalla completa (FSO) | Pantalla completa exclusiva real — menos latencia |
| Aceleración del puntero | Movimiento 1:1 del ratón (estándar competitivo) |
| MPO | Desactiva Multi-Plane Overlay — corrige microstutter en GPU AMD Polaris (RX 400/500) |
| Modo DAW | Prioriza los buffers de audio para Ableton/FL (frente a la respuesta gaming) |

### Privacidad

Telemetría (nivel mínimo; en las ediciones LTSC se respeta el nivel Seguridad) ·
Servicio DiagTrack · Historial de actividad · Identificador de publicidad ·
Sugerencias y apps promocionadas · Recolección de escritura y tinta ·
Notificaciones de feedback · Envío del idioma local a los sitios web.

### Limpieza

Limpieza rápida (TEMP del usuario + `C:\Windows\Temp`) · Limpieza profunda
(+ Prefetch, logs CBS, informes WER, caché de Windows Update) · Vaciar papelera ·
Vaciar caché DNS.

### Inicio

Todas las entradas de las claves Run HKLM/HKCU y de la carpeta Inicio con un
interruptor por programa. Al desactivar una entrada se guarda un respaldo (los
valores de registro pasan a una clave de respaldo; los accesos de carpeta se
mueven a `disabled-startup`), así que *reactivar siempre es posible desde el
mismo interruptor*.

### Perfiles

| Perfil | Objetivo |
|---|---|
| COMPETITIVO | Vanguard + FACEIT ON, Xbox/VBS/DVR/FSO/aceleración de ratón OFF, red sin límite |
| JUEGOS AAA | Anti-cheats y Xbox OFF, máximo FPS en todo |
| CLOUD / XBOX | Listo para Game Pass, red pensada para streaming |
| RESTAURAR WINDOWS | Todos los ajustes a valores de fábrica (anti-cheats intactos) |
| **Punto de restauración** | Crea/revierte una instantánea JSON de los 26 ajustes |
| **Deshacer último cambio** | Revierte el último cambio aplicado, uno por uno (pila de 50) |
| **Exportar / Importar copia** | Guarda/aplica el estado de todos los ajustes en un `.json` portable |

## Deshacer y seguridad

- Cada cambio (interruptor manual, perfil o copia importada) entra en una
  **pila de deshacer**: *Deshacer último cambio* los revierte uno por uno,
  hasta 50 entradas atrás.
- Al aplicar cualquier perfil se **guarda automáticamente** el estado actual en
  `%LOCALAPPDATA%\OptiLite\optilite-restore.json`; *Restaurar último punto*
  revierte todo lo cambiado desde esa instantánea.
- Los programas de inicio desactivados **nunca se borran**: los valores de
  registro pasan a una clave de respaldo y los accesos de carpeta a
  `disabled-startup`, así que siempre se pueden reactivar.
- *RESTAURAR WINDOWS* devuelve todos los ajustes a los valores de fábrica.
- Cada acción queda registrada en `%LOCALAPPDATA%\OptiLite\optilite.log`.
- OptiLite no hace conexiones de red, no descarga nada y no toca archivos
  personales: solo los ajustes de Windows listados arriba.
- Como con cualquier optimizador: **lee el código primero** (es un único
  archivo legible) y considera crear un punto de restauración del sistema antes
  de cambios grandes.

## Preguntas frecuentes

**¿Puedo deshacer todo?**
Sí: usa el punto de restauración (estados exactos previos) o el perfil
*Restaurar Windows* (valores de fábrica). Los ajustes que piden reinicio están
claramente marcados.

**Desactivé Vanguard y Valorant no arranca.**
Es lo esperado: Valorant exige Vanguard. Vuelve a activar el interruptor y
reinicia. OptiLite nunca elimina software anti-cheat, solo cambia el modo de
inicio de sus servicios.

**Mi antivirus marca el script.**
Los heurísticos suelen marcar scripts de PowerShell que escriben en el registro
y piden admin. Todo el código fuente es un único archivo auditable en este
repositorio.

**¿Envía datos a algún sitio?**
No. No hay ninguna llamada de red. Compruébalo en el código o con tu firewall.

## Contribuir · Seguridad · Licencia

- Las contribuciones son bienvenidas — ver [CONTRIBUTING.md](CONTRIBUTING.md)
  (el motor de ajustes es data-driven: una tabla hash por ajuste).
- ¿Encontraste un problema de seguridad? Sigue [SECURITY.md](SECURITY.md).
- Publicado bajo la [Licencia MIT](LICENSE).

## Hoja de ruta

- Más ajustes propuestos por la comunidad
- Modo CLI opcional (`-Apply perfil`, `-Restore`)
- Programación de cambios grandes
