#!/bin/bash
# agente.sh - Agente ligero: recoge datos, monta un JSON y lo envía por webhook.
#
# Uso: ./agente.sh [-i segundos] [-h]
#   -i  intervalo entre envíos en segundos (por defecto 10)
#   -h  ayuda
#
# La URL del canal "monitor" se puede cambiar sin tocar el script:
#   MONITOR_URL="https://..." ./agente.sh -i 30

# ---------------------------------------------------------------------------
# Configuración
# ---------------------------------------------------------------------------
INTERVALO=10
LOG="agente.log"
# TODO(equipo): acordar la URL definitiva del canal monitor
WEBHOOK_URL="${MONITOR_URL:-http://62.238.114.81:9009/webhook/7eE-cDNabJH6}"

# ---------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------
uso() {
  echo "Uso: $0 [-i segundos] [-h]" >&2
}

# Registra un error en agente.log con fecha y hora
log_error() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $*" >> "$LOG"
}

# ---------------------------------------------------------------------------
# Parámetros
# ---------------------------------------------------------------------------
while getopts ":i:h" opt; do
  case "$opt" in
    i) INTERVALO="$OPTARG" ;;
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

# Memoria (/proc/meminfo está en kB). Imprime: "total_mb usada_mb pct"
# Ejemplo de salida: 3936 1210 30.7   (usada = MemTotal - MemAvailable)
mem_info() {
  local salida
  salida="$(awk '
    /^MemTotal:/     { t = $2 }
    /^MemAvailable:/ { a = $2 }
    END {
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

# PUESTO 3: datos del sistema. Versión provisional (disco y carga).
# Sustituir por la función definitiva del compañero.
recoger_sistema() {
  jq -n \
    --argjson disco "$(df / | awk 'NR==2 {gsub("%","",$5); print $5}')" \
    --arg carga "$(cut -d' ' -f1 /proc/loadavg 2>/dev/null || echo 0)" \
    '{disco_pct: $disco, carga_1m: ($carga | tonumber)}'
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
  local host ts recursos sistema
  host="$(hostname)"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  recursos="$(json_o_reserva recursos "$(recoger_recursos 2>>"$LOG")" '{}')"
  sistema="$(json_o_reserva sistema "$(recoger_sistema 2>>"$LOG")" '{}')"

  jq -n \
    --arg host "$host" \
    --arg ts "$ts" \
    --argjson recursos "$recursos" \
    --argjson sistema "$sistema" \
    '{host: $host, ts: $ts, recursos: $recursos, sistema: $sistema}'
}

enviar() {
  local json="$1" salida
  if ! salida="$(curl -sS -f -m 10 -X POST \
        -H 'Content-Type: application/json' \
        -d "$json" "$WEBHOOK_URL" 2>&1)"; then
    log_error "Fallo al enviar a $WEBHOOK_URL: $salida"
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
  sleep "$INTERVALO"
done