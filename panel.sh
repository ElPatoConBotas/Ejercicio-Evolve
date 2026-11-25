#!/usr/bin/env bash
set -u

URL="http://62.238.114.81:8089/sync"
INTERVALO=5
UMBRAL_CAIDO=30

cleanup() {
    tput cnorm 2>/dev/null || true
    echo ""
}
trap cleanup EXIT INT TERM
tput civis 2>/dev/null || true
clear

a_epoch() {
    local ts="$1"
    if [[ -z "$ts" || "$ts" == "null" ]]; then
        echo 0
        return
    fi
    date -d "$ts" +%s 2>/dev/null || date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$ts" +%s 2>/dev/null || echo 0
}

while true; do
    ahora=$(date +%s)
    json_raw=$(curl -fsS --max-time 6 "$URL" 2>/dev/null)

    tput cup 0 0
    printf "Último mensaje recibido por _origen (%s) | %s\n\n" "$URL" "$(date -d "@$ahora" '+%H:%M:%S' 2>/dev/null || date -r "$ahora" '+%H:%M:%S')"

    # Busca cualquier objeto en el JSON que tenga ._origen, agrupa por _origen,
    # toma el último mensaje recibido y ordena por _id
    ultimos_recibidos=$(printf '%s\n' "$json_raw" | jq -c '
        [.. | objects | select(has("_origen") and ._origen != null)]
        | group_by(._origen)
        | map(max_by([(._recibido // ""), (._id // 0)]))
        | sort_by(._id // 0)[]
    ' 2>/dev/null)

    if [[ -z "$ultimos_recibidos" ]]; then
        printf "No hay mensajes válidos o no responde el endpoint.\n"
        tput ed
        sleep "$INTERVALO"
        continue
    fi

    printf "%-16s %-10s %-8s %-20s %-9s %-17s %-10s %-8s\n" \
        "IP_ORIGEN" "HOST" "CPU" "MEMORIA" "DISCO_/" "CARGA_1/5/15" "HORA_INF" "ESTADO"
    printf -- "----------------------------------------------------------------------------------------------------\n"

    while IFS= read -r msg; do
        read -r ip host cpu mem disco carga ts < <(
            printf '%s\n' "$msg" | jq -r '[
                (._origen | tostring),
                (.host // "-" | tostring),
                (if .cpu_pct != null then (.cpu_pct | tostring) + "%" else "-" end),
                (if .mem != null then
                    ((.mem.usada_mb // "?") | tostring) + "/" +
                    ((.mem.total_mb // "?") | tostring) + "MB (" +
                    ((.mem.pct // "?") | tostring) + "%)"
                 else "-" end),
                (([.disco[]? | select(.montaje == "/") | .pct][0] // "-") | tostring | if . != "-" then . + "%" else . end),
                (if (.carga | type) == "array" then (.carga | map(tostring) | join("/")) else "-" end),
                (.ts // "" | tostring)
            ] | @tsv'
        )

        ts_epoch=$(a_epoch "$ts")
        if [[ "$ts_epoch" -gt 0 ]]; then
            edad=$((ahora - ts_epoch))
            (( edad < 0 )) && edad=0
            hora_inf=$(date -d "@$ts_epoch" '+%H:%M:%S' 2>/dev/null || date -r "$ts_epoch" '+%H:%M:%S')
        else
            edad=999999
            hora_inf="-"
        fi

        if (( edad > UMBRAL_CAIDO )); then
            estado="CAÍDO"
        else
            estado="OK"
        fi

        printf "%-16s %-10s %-8s %-20s %-9s %-17s %-10s %-8s\n" \
            "$ip" "$host" "$cpu" "$mem" "$disco" "$carga" "$hora_inf" "$estado"
    done <<< "$ultimos_recibidos"

    tput ed
    sleep "$INTERVALO"
done
