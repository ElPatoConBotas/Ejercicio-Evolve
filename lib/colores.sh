# Colores y umbrales compartidos por el panel.
P5_LIB_SOURCE="${BASH_SOURCE[0]//\\//}"
P5_LIB_DIR="${P5_LIB_SOURCE%/*}"
[[ "$P5_LIB_DIR" == "$P5_LIB_SOURCE" ]] && P5_LIB_DIR=.
P5_PROJECT_DIR="$P5_LIB_DIR/.."

U_AMA=60
U_ROJ=85
RESET=$'\033[0m'

cargar_umbrales() {
    local archivo valores

    U_AMA=60
    U_ROJ=85
    archivo="${FICHERO_UMBRALES:-$P5_PROJECT_DIR/umbrales.json}"

    [[ -f "$archivo" ]] || return 0

    valores=$(jq -er '
        if type != "object" then
            error("se esperaba un objeto JSON")
        else
            [
                ((.amarillo // 60) | if type == "number" then . else 60 end),
                ((.rojo // 85) | if type == "number" then . else 85 end)
            ] | @tsv
        end
    ' "$archivo" 2>/dev/null) || return 0

    valores="${valores//$'\r'/}"
    IFS=$'\t' read -r U_AMA U_ROJ <<< "$valores"
}

color_por_umbral() {
    local valor="${1:-}"
    local umbral_amarillo="${U_AMA:-60}"
    local umbral_rojo="${U_ROJ:-85}"

    # Se rechazan valores vacíos o que no sean números decimales válidos.
    if ! awk -v valor="$valor" '
        BEGIN {
            patron = "^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][+-]?[0-9]+)?$"
            exit !(valor ~ patron)
        }
    '; then
        printf '\033[90m'
        return 0
    fi

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

color_caido() {
    printf '\033[1;31m'
}
