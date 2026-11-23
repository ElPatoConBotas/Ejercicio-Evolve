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

# PUESTO 2: procesos. Versión provisional: ps -> array JSON solo con jq.
# Sustituir por la función definitiva del compañero.
recoger_procesos() {
  ps -eo pid=,user=,pcpu=,pmem=,comm= | jq -R -n '
    [inputs
     | capture("^\\s*(?<pid>\\d+)\\s+(?<user>\\S+)\\s+(?<cpu>[\\d.]+)\\s+(?<mem>[\\d.]+)\\s+(?<comando>.+)$")
     | .pid |= tonumber
     | .cpu |= tonumber
     | .mem |= tonumber]'
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
  local host ts procesos sistema
  host="$(hostname)"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  procesos="$(json_o_reserva procesos "$(recoger_procesos 2>>"$LOG")" '[]')"
  sistema="$(json_o_reserva sistema "$(recoger_sistema 2>>"$LOG")" '{}')"

  jq -n \
    --arg host "$host" \
    --arg ts "$ts" \
    --argjson procesos "$procesos" \
    --argjson sistema "$sistema" \
    '{host: $host, ts: $ts, procesos: $procesos, sistema: $sistema}'
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