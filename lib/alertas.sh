# Estado de alerta en memoria y rutas por defecto del proyecto.
P5_ALERTAS_LIB_SOURCE="${BASH_SOURCE[0]//\\//}"
P5_ALERTAS_LIB_DIR="${P5_ALERTAS_LIB_SOURCE%/*}"
[[ "$P5_ALERTAS_LIB_DIR" == "$P5_ALERTAS_LIB_SOURCE" ]] && P5_ALERTAS_LIB_DIR=.
P5_ALERTAS_PROJECT_DIR="$P5_ALERTAS_LIB_DIR/.."

declare -A ESTADO_ANT

p5_es_numero() {
    local valor="${1:-}"

    awk -v valor="$valor" '
        BEGIN {
            patron = "^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][+-]?[0-9]+)?$"
            exit !(valor ~ patron)
        }
    '
}

nivel() {
    local cpu="${1:-}"
    local umbral_amarillo="${U_AMA:-60}"
    local umbral_rojo="${U_ROJ:-85}"

    if ! p5_es_numero "$cpu"; then
        return 1
    fi

    if awk -v cpu="$cpu" -v umbral="$umbral_amarillo" \
        'BEGIN { exit !(cpu < umbral) }'; then
        printf 'ok'
    elif awk -v cpu="$cpu" -v umbral="$umbral_rojo" \
        'BEGIN { exit !(cpu <= umbral) }'; then
        printf 'aviso'
    else
        printf 'critico'
    fi
}

guardar_estados() {
    local raiz="${DIR:-$P5_ALERTAS_PROJECT_DIR}"
    local carpeta="$raiz/estado"
    local archivo="${FICHERO_ESTADOS:-$carpeta/estado_anterior.txt}"
    local host

    mkdir -p "$carpeta" 2>/dev/null || return 0
    : > "$archivo" 2>/dev/null || return 0

    for host in "${!ESTADO_ANT[@]}"; do
        # El formato de persistencia usa el primer signo igual como separador.
        [[ "$host" != *"="* && "$host" != *$'\n'* ]] || continue
        printf '%s=%s\n' "$host" "${ESTADO_ANT[$host]}" >> "$archivo" 2>/dev/null
    done
    return 0
}

cargar_estados() {
    local raiz="${DIR:-$P5_ALERTAS_PROJECT_DIR}"
    local archivo="${FICHERO_ESTADOS:-$raiz/estado/estado_anterior.txt}"
    local linea host estado

    ESTADO_ANT=()
    [[ -f "$archivo" ]] || return 0

    while IFS= read -r linea || [[ -n "$linea" ]]; do
        [[ "$linea" == *=* ]] || continue
        host="${linea%%=*}"
        estado="${linea#*=}"
        [[ -n "$host" ]] || continue
        case "$estado" in
            ok|aviso|critico|caido) ESTADO_ANT["$host"]="$estado" ;;
        esac
    done < "$archivo" 2>/dev/null
    return 0
}

comprobar_alerta() {
    local host="${1:-}"
    local cpu="${2:-}"
    local actual anterior cpu_json marca_tiempo cuerpo

    [[ -n "$host" && -n "$cpu" ]] || return 0

    if [[ "$cpu" == "CAIDO" ]]; then
        actual=caido
        cpu_json=null
    else
        p5_es_numero "$cpu" || return 0
        actual=$(nivel "$cpu") || return 0
        cpu_json=$cpu
    fi

    anterior="${ESTADO_ANT[$host]-}"
    ESTADO_ANT["$host"]=$actual

    if [[ -n "$anterior" && "$anterior" != "$actual" ]]; then
        marca_tiempo=$(jq -nr 'now | todateiso8601' 2>/dev/null) || marca_tiempo=
        if [[ -n "$marca_tiempo" ]]; then
            cuerpo=$(jq -cn \
                --arg host "$host" \
                --arg de "$anterior" \
                --arg a "$actual" \
                --argjson cpu_pct "$cpu_json" \
                --arg ts "$marca_tiempo" \
                '{
                    host: $host,
                    de: $de,
                    a: $a,
                    cpu_pct: $cpu_pct,
                    ts: $ts
                } + (if $de == "caido" then {recuperado: true} else {} end)' \
                2>/dev/null) || cuerpo=

            if [[ -n "$cuerpo" ]]; then
                if [[ "${ALERTAS_DRY_RUN:-0}" == 1 ]]; then
                    echo "$cuerpo"
                elif [[ -n "${URL_ALERTAS:-}" && "$URL_ALERTAS" != CAMBIAR* ]]; then
                    curl -s --max-time 5 -X POST \
                        -H 'Content-Type: application/json' \
                        --data "$cuerpo" \
                        "$URL_ALERTAS" >/dev/null 2>&1 || true
                fi
            fi
        fi
    fi

    guardar_estados
}
