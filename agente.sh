#!/bin/bash
# agente.sh - Agente ligero: recoge datos, monta un JSON y lo envía por webhook.
#
# Uso: ./agente.sh [-i segundos] [-o] [-h]
#   -i  intervalo entre envíos en segundos (por defecto 10)
#   -o  recoge y envía un único informe, y termina
#   -h  ayuda
#
# ---------------------------------------------------------------------------
# Configuración
# ---------------------------------------------------------------------------
SCRIPT_SOURCE="${BASH_SOURCE[0]//\\//}"
SCRIPT_DIR="${SCRIPT_SOURCE%/*}"
if [[ "$SCRIPT_DIR" == "$SCRIPT_SOURCE" ]]; then
  SCRIPT_DIR=.
fi
DIR="$(cd -- "$SCRIPT_DIR" && pwd)"
source "$DIR/config.sh"

INTERVALO="${INTERVALO_DEF:-10}"
UNA_VEZ=0
LOG="$DIR/logs/agente.log"
WEBHOOK_URL="${URL_MONITOR:-}"

# ---------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------
uso() {
  echo "Uso: $0 [-i segundos] [-o] [-h]" >&2
}

# Registra un error en agente.log con fecha y hora
log_error() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $*" >> "$LOG"
}

# ---------------------------------------------------------------------------
# Parámetros
# ---------------------------------------------------------------------------
while getopts ":i:oh" opt; do
  case "$opt" in
    i) INTERVALO="$OPTARG" ;;
    o) UNA_VEZ=1 ;;
    h) uso; exit 0 ;;
    :) echo "Falta el valor de -$OPTARG" >&2; uso; exit 1 ;;
    \?) echo "Opción no válida: -$OPTARG" >&2; uso; exit 1 ;;
  esac
done

if ! [[ "$INTERVALO" =~ ^[1-9][0-9]*$ ]]; then
  echo "El intervalo (-i) debe ser un entero positivo" >&2
  exit 1
fi

command -v jq >/dev/null 2>&1   || { echo "Falta jq" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "Falta curl" >&2; exit 1; }

if [[ -z "$WEBHOOK_URL" || "$WEBHOOK_URL" == CAMBIAR* ]]; then
  echo "Define URL_MONITOR en el entorno antes de iniciar el agente." >&2
  exit 1
fi

mkdir -p "$DIR/logs" || {
  echo "No se pudo crear el directorio de logs: $DIR/logs" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# Piezas de datos (cada función imprime JSON válido por stdout)
# ---------------------------------------------------------------------------

# PUESTO 2: recursos (CPU, memoria, carga y uptime).
# Las cuatro funciones auxiliares imprimen solo números (no JSON), listos para jq --argjson.
# Si una lectura falla: no imprimen nada, avisan por stderr (acaba en agente.log) y devuelven 1.

# Lee los contadores de CPU de /proc/stat. Imprime: "total inactivo"
leer_cpu() {
  local u n s id w irq sirq st
  read -r _ u n s id w irq sirq st _ < /proc/stat || return 1
  echo "$(( u + n + s + id + w + irq + sirq + st )) $(( id + w ))"
}

# % de uso de CPU: dos lecturas separadas 1 s. Ejemplo de salida: 12.5
# porcentaje = 100 * (Δtotal - Δinactivo) / Δtotal
cpu_pct() {
  local t1 i1 t2 i2 lectura
  lectura="$(leer_cpu)" || { echo "cpu_pct: no se pudo leer /proc/stat" >&2; return 1; }
  read -r t1 i1 <<< "$lectura"
  sleep 1
  lectura="$(leer_cpu)" || { echo "cpu_pct: no se pudo leer /proc/stat" >&2; return 1; }
  read -r t2 i2 <<< "$lectura"

  awk -v dt="$(( t2 - t1 ))" -v di="$(( i2 - i1 ))" \
    'BEGIN { if (dt > 0) printf "%.1f\n", 100 * (dt - di) / dt; else print "0.0" }'
}

# Memoria (/proc/meminfo está en kB). Imprime: "total_mb usada_mb pct".
# Usa MemAvailable cuando existe; en sistemas sin ese campo usa MemFree.
mem_info() {
  local salida
  salida="$(awk '
    /^MemTotal:/     { t = $2 }
    /^MemAvailable:/ { a = $2; disponible = 1 }
    /^MemFree:/       { libre = $2 }
    END {
      if (!disponible) a = libre
      if (t > 0 && a != "") printf "%d %d %.1f", t / 1024, (t - a) / 1024, 100 * (t - a) / t
    }' /proc/meminfo)"
  if [[ -z "$salida" ]]; then
    echo "mem_info: no se pudo leer MemTotal/MemAvailable" >&2
    return 1
  fi
  echo "$salida"
}

# Carga media del sistema (1, 5 y 15 min). Imprime: "c1 c5 c15". Ejemplo: 0.15 0.10 0.05
carga_info() {
  local c1 c5 c15
  read -r c1 c5 c15 _ < /proc/loadavg || { echo "carga_info: no se pudo leer /proc/loadavg" >&2; return 1; }
  [[ -n "$c15" ]] || { echo "carga_info: formato inesperado en /proc/loadavg" >&2; return 1; }
  echo "$c1 $c5 $c15"
}

# Tiempo encendido en segundos (entero). Ejemplo: 86400
uptime_seg() {
  local up
  read -r up _ < /proc/uptime || { echo "uptime_seg: no se pudo leer /proc/uptime" >&2; return 1; }
  [[ -n "$up" ]] || { echo "uptime_seg: formato inesperado en /proc/uptime" >&2; return 1; }
  echo "${up%.*}"
}

# Junta las cuatro lecturas en un único objeto JSON.
recoger_recursos() {
  local cpu mem mem_total mem_usada mem_pct carga c1 c5 c15 up
  cpu="$(cpu_pct)"       || return 1
  mem="$(mem_info)"      || return 1
  carga="$(carga_info)"  || return 1
  up="$(uptime_seg)"     || return 1
  read -r mem_total mem_usada mem_pct <<< "$mem"
  read -r c1 c5 c15 <<< "$carga"

  jq -n \
    --argjson cpu "$cpu" \
    --argjson mem_total "$mem_total" \
    --argjson mem_usada "$mem_usada" \
    --argjson mem_pct "$mem_pct" \
    --argjson c1 "$c1" --argjson c5 "$c5" --argjson c15 "$c15" \
    --argjson up "$up" \
    '{cpu_pct: $cpu,
      mem: {total_mb: $mem_total, usada_mb: $mem_usada, pct: $mem_pct},
      carga: {"1m": $c1, "5m": $c5, "15m": $c15},
      uptime_seg: $up}'
}

# PUESTO 3: disco y top 3 procesos (funciones definitivas)

# df -P -> [{montaje, pct}] solo con jq: quita el %, admite puntos de montaje
# con espacios y descarta pseudo-sistemas que solo meten ruido en el panel.
recoger_disco() {
  df -P -x tmpfs -x devtmpfs -x squashfs -x overlay -x efivarfs 2>/dev/null | jq -R -s -c '
    split("\n")[1:]
    | map(select(length > 0)
          | capture("^\\S+\\s+\\d+\\s+\\d+\\s+\\d+\\s+(?<pct>\\d+)%\\s+(?<montaje>.+)$")
          | {montaje, pct: (.pct | tonumber)})'
}

# ps -> [{pid, cmd, cpu}] con los 3 que más CPU gastan, solo con jq (sin bucles
# de Bash). comm puede llevar espacios ("Isolated Web Co"): pid al principio,
# %cpu al final y todo lo de en medio es cmd. El recorte a 3 lo hace jq.
recoger_top_procesos() {
  ps -eo pid,comm,%cpu --sort=-%cpu --no-headers | jq -R -s -c '
    split("\n")
    | map(select(length > 0)
          | capture("^\\s*(?<pid>\\d+)\\s+(?<cmd>.+?)\\s+(?<cpu>[0-9]+(\\.[0-9]+)?)\\s*$")
          | {pid: (.pid | tonumber), cmd, cpu: (.cpu | tonumber)})
    | .[:3]'
}

# ---------------------------------------------------------------------------
# Montaje y envío
# ---------------------------------------------------------------------------

# Comprueba que un texto es JSON válido; si no, registra el error y usa el valor de reserva
json_o_reserva() {
  local nombre="$1" texto="$2" reserva="$3"
  if printf '%s' "$texto" | jq -e . >/dev/null 2>&1; then
    printf '%s' "$texto"
  else
    log_error "La pieza '$nombre' no devolvió JSON válido; se usa $reserva"
    printf '%s' "$reserva"
  fi
}

montar_json() {
  local host ts recursos disco top
  host="$(hostname)"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  recursos="$(recoger_recursos 2>>"$LOG")" || return 1
  disco="$(json_o_reserva disco "$(recoger_disco 2>>"$LOG")" '[]')"
  top="$(json_o_reserva top_procesos "$(recoger_top_procesos 2>>"$LOG")" '[]')"

  jq -n \
    --arg host "$host" \
    --arg ts "$ts" \
    --argjson recursos "$recursos" \
    --argjson disco "$disco" \
    --argjson top "$top" \
    '{
      host: $host,
      ts: $ts,
      cpu_pct: $recursos.cpu_pct,
      mem: $recursos.mem,
      disco: $disco,
      carga: [
        $recursos.carga["1m"],
        $recursos.carga["5m"],
        $recursos.carga["15m"]
      ],
      uptime_s: $recursos.uptime_seg,
      top_procesos: $top
    }'
}

enviar() {
  local json="$1" salida codigo
  if salida="$(curl -g -sS -f -m 10 -X POST \
        -H 'Content-Type: application/json' \
        -d "$json" "$WEBHOOK_URL" 2>&1)"; then
    return 0
  else
    codigo=$?
    log_error "Fallo al enviar al canal monitor (curl $codigo)"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Bucle principal
# ---------------------------------------------------------------------------
trap 'echo "Agente detenido." >&2; exit 0' INT TERM

while true; do
  if JSON="$(montar_json)"; then
    enviar "$JSON"
  else
    log_error "No se pudo montar el JSON final"
  fi
  if (( UNA_VEZ )); then
    break
  fi
  sleep "$INTERVALO"
done