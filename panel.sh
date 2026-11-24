#!/usr/bin/env bash

# Resuelve las rutas desde la ubicación del script, no desde la carpeta actual.
SCRIPT_SOURCE="${BASH_SOURCE[0]//\\//}"
SCRIPT_DIR="${SCRIPT_SOURCE%/*}"
if [[ "$SCRIPT_DIR" == "$SCRIPT_SOURCE" ]]; then
    SCRIPT_DIR=.
fi
DIR="$(cd -- "$SCRIPT_DIR" && pwd)"
source "$DIR/config.sh"
source "$DIR/lib/colores.sh"
source "$DIR/lib/grafica.sh"
source "$DIR/lib/alertas.sh"

INTERVALO=5
UMBRAL_CAIDO=30
UNA_VEZ=0
FICHERO_UMBRALES="${FICHERO_UMBRALES:-$DIR/umbrales.json}"

while getopts ":oh" opt; do
    case "$opt" in
        o) UNA_VEZ=1 ;;
        h)
            printf 'Uso: %s [-o] [-h]\n' "$0"
            printf '  -o  consulta una vez, dibuja la tabla y termina\n'
            exit 0
            ;;
        \?)
            printf 'Opción no válida: -%s\n' "$OPTARG" >&2
            exit 1
            ;;
    esac
done

cargar_umbrales
cargar_estados

restaurar_terminal() {
    if [[ -t 1 ]]; then
        tput cnorm 2>/dev/null || true
    fi
}

trap 'exit 0' INT TERM
trap restaurar_terminal EXIT

if [[ -t 1 ]]; then
    tput civis 2>/dev/null || true
    clear 2>/dev/null || true
fi

while true; do
    # Se vuelve a leer la configuración para aplicar cambios sin reiniciar.
    cargar_umbrales

    json_raw=
    aviso=
    if ! json_raw="$(curl -fsS --max-time 5 "$URL_CANAL" 2>/dev/null)"; then
        aviso="No se pudo consultar el canal monitor."
        json_raw=
    fi

    filas_texto=
    if [[ -n "$json_raw" ]]; then
        if ! filas_texto=$(jq -r '
            def mensajes:
                if type == "array" then .
                elif type == "object" and (.messages | type) == "array" then .messages
                else []
                end;

            mensajes
            | map(if (.datos | type) == "object" then .datos else . end)
            | map(select(
                (.host | type) == "string"
                and (.ts | type) == "string"
                and (.cpu_pct | type) == "number"
                and (.mem.pct | type) == "number"
                and (.disco | type) == "array"
                and (.carga | type) == "array"
                and (try (.ts | fromdateiso8601) catch null) != null
            ))
            | sort_by([.host, .ts])
            | group_by(.host)
            | map(last)[]
            | [
                .host,
                (.cpu_pct | tostring),
                (.mem.pct | tostring),
                (([.disco[] | select(.montaje == "/") | .pct][0] // "N/A") | tostring),
                ((.carga[0] // "N/A") | tostring),
                (.ts | fromdateiso8601 | tostring),
                (.ts | fromdateiso8601 | strftime("%H:%M:%S"))
              ]
            | @tsv
        ' <<< "$json_raw" 2>/dev/null); then
            filas_texto=
            aviso="El canal devolvió JSON inválido."
        fi
    fi

    filas=()
    if [[ -n "$filas_texto" ]]; then
        mapfile -t filas <<< "$filas_texto"
    fi

    ahora=$(date +%s)

    if [[ -t 1 ]]; then
        tput cup 0 0 2>/dev/null || printf '\033[H'
    fi

    printf '%-16s %-9s %-9s %-9s %-9s %-20s %-8s %-9s\n' \
        "HOST" "CPU" "MEMORIA" "DISCO /" "CARGA" "CPU (20)" "HORA" "ESTADO"
    printf '%-16s %-9s %-9s %-9s %-9s %-20s %-8s %-9s\n' \
        "----------------" "---------" "---------" "---------" "---------" \
        "--------------------" "--------" "---------"

    if ((${#filas[@]} == 0)); then
        if [[ -n "$aviso" ]]; then
            printf '%s\n' "$aviso"
        elif [[ -n "$json_raw" ]]; then
            printf 'El canal respondió, pero no contiene informes compatibles (faltan métricas como cpu_pct, mem.pct, disco o carga).\n'
        else
            printf 'Esperando informes válidos en el canal monitor.\n'
        fi
    fi

    for fila in "${filas[@]}"; do
        fila="${fila%$'\r'}"
        IFS=$'\t' read -r host cpu memoria disco carga ts hora <<< "$fila"

        if [[ "$disco" == "N/A" ]]; then
            disco_mostrar=$disco
        else
            disco_mostrar="${disco}%"
        fi

        edad=$((ahora - ts))
        color_cpu=$(color_por_umbral "$cpu")
        color_memoria=$(color_por_umbral "$memoria")
        color_disco=$(color_por_umbral "$disco")
        grafica_cpu=$(grafica_host "$host" "$json_raw")

        if (( edad > UMBRAL_CAIDO )); then
            estado="CAÍDO"
            color_estado=$(color_caido)
            comprobar_alerta "$host" CAIDO >/dev/null
        else
            estado="OK"
            color_estado=$'\033[32m'
            comprobar_alerta "$host" "$cpu" >/dev/null
        fi

        printf '%-16.16s %s%-9s%s %s%-9s%s %s%-9s%s %-9s %-20s %-8s %s%-9s%s\n' \
            "$host" \
            "$color_cpu" "${cpu}%" "$RESET" \
            "$color_memoria" "${memoria}%" "$RESET" \
            "$color_disco" "$disco_mostrar" "$RESET" \
            "$carga" "$grafica_cpu" "$hora" \
            "$color_estado" "$estado" "$RESET"
    done

    if [[ -t 1 ]]; then
        tput ed 2>/dev/null || true
    fi

    if (( UNA_VEZ )); then
        break
    fi
    sleep "$INTERVALO"
done
