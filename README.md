# Monitorización de recursos con panel

Sistema de monitorización hecho solo con **Bash, jq, awk y curl**. Un **agente** ligero se ejecuta en cada equipo y envía periódicamente el estado de sus recursos por webhook a un canal. Un **panel** lee el canal y muestra en tiempo real todos los equipos, con colores según umbrales.

```
[Equipo A: agente.sh] ─┐
[Equipo B: agente.sh] ─┼─► Canal "monitor" ─► [panel.sh] ─► tabla con colores
[Equipo C: agente.sh] ─┘                           │
                                                   └─► Canal "alertas" (solo cuando cambia el estado)
```

## Características

**Fase 1 (obligatoria)**
- Agente: CPU, memoria, disco, carga, uptime y top 3 de procesos, enviados cada `N` segundos (`-i`, por defecto 10).
- Registro de errores de envío en `logs/agente.log`.
- Panel: tabla en terminal con host, CPU, memoria, disco raíz, carga y hora del último informe.
- Colores por umbral: verde (< 60 %), amarillo (hasta 85 %), rojo (> 85 %).
- Hosts con más de 30 s sin informar marcados como **CAÍDO**.

**Fase 2 (ampliaciones)**
- [x] Umbrales configurables en `umbrales.json`.
- [x] Mini-gráfica de CPU de los últimos 20 informes (`▁▂▃▄▅▆▇█`).
- [x] Alertas en el canal `alertas` solo al cambiar de estado.
- [ ] Panel web (`panel.sh --html`), opcional.

## Requisitos

- Linux (probado en Kali / Debian) con Bash 4+ (se usan arrays asociativos).
- `jq`, `curl`, `awk`, `ps`, `df`, `tput`.
- Opcional para la demo: `stress-ng`.

```bash
sudo apt update && sudo apt install -y jq curl stress-ng
```

## Estructura del proyecto

```
monitorizacion/
├── README.md                  # Este fichero
├── config.sh                  # URLs de los canales y valores comunes
├── umbrales.json              # Umbrales configurables (ampliación A)
│
├── agente.sh                  # Script principal del agente
├── panel.sh                   # Script principal del panel
│
├── lib/
│   ├── metricas.sh            # cpu_pct, mem, carga, uptime
│   ├── disco_procesos.sh      # disco y top_procesos
│   ├── colores.sh             # cargar_umbrales, color_por_umbral
│   ├── grafica.sh             # mini-gráfica ▁▂▃▄▅▆▇█ (ampliación B)
│   └── alertas.sh             # nivel, comprobar_alerta (ampliación C)
│
├── pruebas/
│   ├── datos_prueba.json      # Informes de ejemplo (rojo, normal, antiguo)
│   ├── validar_contrato.sh    # Comprueba campos y tipos numéricos
│   ├── estres.sh              # Generador de carga para la demo
│   └── probar_p5.sh           # Pruebas de colores, gráfica y alertas
│
├── logs/
│   └── agente.log             # Generado: errores de envío
├── estado/
│   └── estado_anterior.txt    # Generado: último estado de cada host
└── web/
    └── index.html             # Generado por panel.sh --html (opcional)
```

## Configuración

`config.sh` centraliza las direcciones. Define el webhook mediante variables
de entorno para no guardar su token en el repositorio. Por defecto, las alertas
usan el mismo webhook; el panel hace GET al endpoint de sincronización:

```bash
export URL_MONITOR="CAMBIAR_URL_MONITOR"
export URL_ALERTAS="${URL_MONITOR}"
export URL_CANAL="CAMBIAR_URL_GET_SYNC"
INTERVALO_DEF=10
```

El agente y el panel cargan estas variables al arrancar; las variables de
entorno pueden reemplazar cualquier URL sin editar `config.sh`.

Umbrales (`umbrales.json`). Si el fichero no existe se usan 60 y 85:

```json
{ "amarillo": 60, "rojo": 85 }
```

## Uso

```bash
git clone <URL-DEL-REPOSITORIO>
cd monitorizacion
chmod +x agente.sh panel.sh pruebas/*.sh
```

**Agente** (en cada equipo que se quiera monitorizar):

```bash
./agente.sh            # envía cada 10 s
./agente.sh -i 5       # envía cada 5 s (recomendado para la demo)
./agente.sh -o -i 5    # envía un único informe y termina
```

**Panel** (en otra terminal, en el equipo que muestra el resultado):

```bash
./panel.sh        # actualiza la tabla cada 5 s
./panel.sh -o     # dibuja una tabla y termina
```

El agente envía un informe JSON con las métricas en la raíz del objeto. La
respuesta del canal puede ser un array o un objeto con `messages`; el panel
acepta informes directos y mensajes con el informe dentro de `datos`. Selecciona
el último informe de cada host, dibuja CPU, memoria, disco raíz, carga, gráfica
e informa CAÍDO tras 30 s.
Las alertas se publican únicamente al cambiar el estado.

Para salir de cualquiera de los dos: `Ctrl+C`.

## Contrato JSON

Cada informe del agente tiene este formato. Los números son **números JSON**, no cadenas (se construye con `jq --argjson`).

```json
{
  "host": "kali-g2",
  "ts": "2026-11-17T10:50:00Z",
  "cpu_pct": 12.5,
  "mem": { "total_mb": 3936, "usada_mb": 1210, "pct": 30.7 },
  "disco": [ { "montaje": "/", "pct": 45 } ],
  "carga": [0.12, 0.30, 0.25],
  "uptime_s": 3600,
  "top_procesos": [ { "pid": 1234, "cmd": "firefox-esr", "cpu": 5.1 } ]
}
```

Alerta publicada en el canal `alertas`:

```json
{ "host": "kali-g2", "de": "ok", "a": "critico", "cpu_pct": 97.3, "ts": "2026-11-17T10:51:00Z" }
```

## Cómo funciona

| Métrica | Fuente | Detalle |
|---|---|---|
| CPU | `/proc/stat` | Dos lecturas separadas 1 s; `100 × (Δtotal − Δidle) / Δtotal` con `awk` |
| Memoria | `/proc/meminfo` | `MemTotal` y `MemAvailable`; usada = total − disponible |
| Disco | `df -P` | Se quita el `%` y se convierte a array JSON con `jq` |
| Carga | `/proc/loadavg` | Tres primeros valores |
| Uptime | `/proc/uptime` | Primer valor, en segundos |
| Procesos | `ps -eo pid,comm,%cpu --sort=-%cpu` | Top 3, convertido a JSON solo con `jq` |

El panel consulta el canal cada 5 s, se queda con el último informe de cada host
(`group_by(.datos.host) | map(last)`) y repinta la tabla con `tput cup 0 0` para
evitar parpadeos.

## Pruebas y demo

```bash
./pruebas/validar_contrato.sh   # valida el JSON del agente
./pruebas/probar_p5.sh          # colores, gráfica y alertas
./pruebas/probar_integracion.sh # panel con canal simulado, sin red
./pruebas/estres.sh             # genera carga de CPU
```

`validar_contrato.sh` sustituye `curl` por una función local y no necesita
conectarse al webhook.

Criterios de aceptación ("hecho cuando…"):

1. El panel muestra al menos **3 equipos** actualizándose.
2. Un `yes > /dev/null &` pone la CPU en **rojo en menos de 15 s** (usar `-i 5`). Para pararlo: `pkill yes`.
3. Al parar un agente, su equipo pasa a **CAÍDO** a los 30 s.

## Equipo

| Puesto | Responsable | Parte |
|---|---|---|
| P1 | _nombre_ | Coordinación, envío del agente (`agente.sh`, `config.sh`) |
| P2 | _nombre_ | Métricas de CPU, memoria, carga y uptime (`lib/metricas.sh`) |
| P3 | _nombre_ | Disco, procesos, validación y estrés (`lib/disco_procesos.sh`, `pruebas/`) |
| P4 | _nombre_ | Panel y tabla en terminal (`panel.sh`) |
| P5 | _nombre_ | Colores, umbrales, gráfica y alertas (`lib/colores.sh`, `lib/grafica.sh`, `lib/alertas.sh`) |

## Problemas frecuentes

- **Los números salen entre comillas en el JSON:** usa `--argjson` en lugar de `--arg` para valores numéricos.
- **`syntax error` al comparar CPU:** Bash no compara decimales; usa `awk` para la comparación.
- **El panel no muestra nada:** revisa `URL_MONITOR` en `config.sh` y que el agente esté enviando (`logs/agente.log`).
- **Un host aparece CAÍDO sin motivo:** comprueba que la hora de los equipos esté sincronizada.

## `.gitignore` recomendado

```
logs/
estado/
web/index.html
```
