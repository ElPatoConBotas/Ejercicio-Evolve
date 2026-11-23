# Estado de alerta en memoria: la primera observación solo inicializa el host.
declare -A ESTADO_ANT
declare -A CPU_ANT

nivel() {
    local cpu="${1:-0}"
    local umbral_amarillo="${U_AMA:-60}"
    local umbral_rojo="${U_ROJ:-85}"

    if [[ "$cpu" == "CAIDO" ]]; then
        printf 'CAIDO'
    elif awk -v cpu="$cpu" -v umbral="$umbral_amarillo" \
        'BEGIN { exit !(cpu < umbral) }'; then
        printf 'ok'
    elif awk -v cpu="$cpu" -v umbral="$umbral_rojo" \
        'BEGIN { exit !(cpu <= umbral) }'; then
        printf 'aviso'
    else
        printf 'critico'
    fi
}

comprobar_alerta() {
    local host="${1:-}"
    local cpu="${2:-}"
    local actual anterior cpu_json marca_tiempo cuerpo

    if [[ -z "$host" || -z "$cpu" ]]; then
        printf 'Uso: comprobar_alerta <host> <cpu|CAIDO>\n' >&2
        return 1
    fi

    actual=$(nivel "$cpu")
    anterior="${ESTADO_ANT[$host]-}"

    # Para CAIDO se conserva en el aviso la última CPU conocida del host.
    if [[ "$cpu" == "CAIDO" ]]; then
        cpu_json="${CPU_ANT[$host]:-0}"
    else
        cpu_json=$cpu
        CPU_ANT["$host"]=$cpu
    fi

    if [[ -n "$anterior" && "$anterior" != "$actual" && -n "${URL_ALERTAS:-}" ]]; then
        marca_tiempo=$(jq -nr 'now | todateiso8601')
        cuerpo=$(jq -n \
            --arg host "$host" \
            --arg de "$anterior" \
            --arg a "$actual" \
            --argjson cpu_pct "$cpu_json" \
            --arg ts "$marca_tiempo" \
            '{host: $host, de: $de, a: $a, cpu_pct: $cpu_pct, ts: $ts}')

        # Un fallo de red no debe interrumpir el panel.
        curl -sS -X POST \
            -H 'Content-Type: application/json' \
            --data "$cuerpo" \
            "$URL_ALERTAS" >/dev/null 2>&1 || true
    fi

    ESTADO_ANT["$host"]=$actual
}