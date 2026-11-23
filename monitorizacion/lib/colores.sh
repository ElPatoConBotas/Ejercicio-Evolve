# Colores y umbrales compartidos por el panel.
U_AMA=60
U_ROJ=85
RESET=$'\033[0m'

cargar_umbrales() {
    local archivo valores directorio_lib

    U_AMA=60
    U_ROJ=85

    if [[ -n "${FICHERO_UMBRALES:-}" ]]; then
        archivo=$FICHERO_UMBRALES
    else
        directorio_lib="${BASH_SOURCE[0]%/*}"
        if [[ "$directorio_lib" == "${BASH_SOURCE[0]}" ]]; then
            directorio_lib=.
        fi
        archivo="$directorio_lib/../umbrales.json"
    fi

    if [[ -f "$archivo" ]] &&
        valores=$(jq -er '
            if type == "object" then
                [
                    ((.amarillo // 60) | if type == "number" then . else 60 end),
                    ((.rojo // 85) | if type == "number" then . else 85 end)
                ] | @tsv
            else
                error("se esperaba un objeto JSON")
            end
        ' "$archivo" 2>/dev/null); then
        IFS=$'\t' read -r U_AMA U_ROJ <<< "$valores"
    fi
}

color_por_umbral() {
    local valor="${1:-0}"
    local umbral_amarillo="${U_AMA:-60}"
    local umbral_rojo="${U_ROJ:-85}"

    # awk compara correctamente valores decimales.
    if awk -v valor="$valor" -v umbral="$umbral_amarillo" \
        'BEGIN { exit !(valor < umbral) }'; then
        printf '\033[32m'
    elif awk -v valor="$valor" -v umbral="$umbral_rojo" \
        'BEGIN { exit !(valor <= umbral) }'; then
        printf '\033[33m'
    else
        printf '\033[31m'
    fi
}