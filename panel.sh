#!/bin/bash

URL_CANAL="http://62.238.114.81:8089/sync"
INTERVALO=5
UMBRAL_CAIDO=30

# Ocultar cursor y restaurarlo al salir
tput civis
trap 'tput cnorm; clear; exit 0' INT TERM

clear

while true; do
    json_raw=$(curl -s "$URL_CANAL")
    ahora=$(date +%s)

    # Extraer último informe por host (filtrando mensajes sin host como los de prueba)
    mapfile -t filas < <(echo "$json_raw" | jq -r '
        [ .messages[] | select(.host != null) ]
        | sort_by(.ts)
        | group_by(.host)
        | map(last)
        | .[]
        | [
            .host,
            (if .procesos then (([.procesos[].cpu] | add * 10 | round / 10 | tostring) + "%") else "N/A" end),
            (if .procesos then (([.procesos[].mem] | add * 10 | round / 10 | tostring) + "%") else "N/A" end),
            (if .sistema.disco_pct then ((.sistema.disco_pct | tostring) + "%") else "N/A" end),
            (if .sistema.carga_1m then (.sistema.carga_1m | tostring) else "N/A" end),
            (.ts | fromdateiso8601)
          ] | @tsv
    ')

    tput cup 0 0

    # Cabecera
    printf "%-15s %-10s %-10s %-10s %-10s %-12s %-10s\n" \
        "HOST" "CPU" "MEMORIA" "DISCO /" "CARGA" "ÚLTIMO INF." "ESTADO"
    printf "%-15s %-10s %-10s %-10s %-10s %-12s %-10s\n" \
        "---------------" "----------" "----------" "----------" "----------" "------------" "----------"

    # Filas
    for fila in "${filas[@]}"; do
        IFS=$'\t' read -r host cpu mem disco carga ts <<< "$fila"

        diferencia=$((ahora - ts))
        hora_formateada=$(date -d "@$ts" +"%H:%M:%S" 2>/dev/null || echo "Error")

        if (( diferencia > UMBRAL_CAIDO )); then
            estado="\e[31mCAÍDO\e[0m"
        else
            estado="\e[32mOK\e[0m"
        fi

        printf "%-15s %-10s %-10s %-10s %-10s %-12s " \
            "$host" "$cpu" "$mem" "$disco" "$carga" "$hora_formateada"
        echo -e "${estado}$(tput el)"
    done

    tput ed
    sleep "$INTERVALO"
done

