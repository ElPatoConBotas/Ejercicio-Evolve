# Dibuja una barra por cada valor, sin añadir un salto de línea.
grafica() {
    local valor indice
    local -a barras=( '▁' '▂' '▃' '▄' '▅' '▆' '▇' '█' )

    for valor in "$@"; do
        indice=$(awk -v valor="$valor" '
            BEGIN {
                n = int(valor / 12.5)
                if (n < 0) n = 0
                if (n > 7) n = 7
                print n
            }
        ')
        printf '%s' "${barras[$indice]}"
    done
}

# El canal puede ser una ruta a un JSON o el contenido JSON directamente.
# Se asume que el canal es un array de mensajes con el informe en .datos.
ultimos_cpu() {
    local host="${1:-}"
    local json_canal="${2:-}"
    local filtro='[.[] | select(.datos.host == $host) | .datos.cpu_pct | select(type == "number")][-20:][]'

    if [[ -f "$json_canal" ]]; then
        jq -r --arg host "$host" "$filtro" "$json_canal"
    else
        jq -r --arg host "$host" "$filtro" <<< "$json_canal"
    fi
}