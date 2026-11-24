# Dibuja una barra por cada valor, sin añadir un salto de línea.
grafica() {
    local valor indice
    local -a barras=( '▁' '▂' '▃' '▄' '▅' '▆' '▇' '█' )

    for valor in "$@"; do
        # Los valores no numéricos se ignoran sin imprimir texto adicional.
        if ! awk -v valor="$valor" '
            BEGIN {
                patron = "^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][+-]?[0-9]+)?$"
                exit !(valor ~ patron)
            }
        '; then
            continue
        fi

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

# Lee el canal, que puede ser un array o un objeto con una propiedad messages.
# Acepta informes directos y mensajes que guardan el informe dentro de .datos.
ultimos_cpu() {
    local host="${1:-}"
    local json_canal="${2:-}"
    local valor

    [[ -n "$host" && -n "$json_canal" ]] || return 0

    jq -r --arg host "$host" '
        def mensajes:
            if type == "array" then .
            elif type == "object" and (.messages | type) == "array" then .messages
            else []
            end;

        mensajes
        | map(if (.datos | type) == "object" then .datos else . end)
        | map(select(.host? == $host
                     and (.cpu_pct? | type) == "number"
                     and (.mem.pct? | type) == "number"
                     and (.disco? | type) == "array"
                     and (.carga? | type) == "array"
                     and (.ts? | type) == "string"))
        | sort_by(.ts)
        | .[-20:]
        | .[].cpu_pct
    ' <<< "$json_canal" 2>/dev/null |
        while IFS= read -r valor; do
            printf '%s\n' "${valor%$'\r'}"
        done || true
}

# Devuelve una gráfica de ancho fijo para la columna del panel.
grafica_host() {
    local host="${1:-}"
    local json_canal="${2:-}"
    local salida relleno
    local -a valores=()

    salida=$(ultimos_cpu "$host" "$json_canal")
    if [[ -n "$salida" ]]; then
        mapfile -t valores <<< "$salida"
    fi

    relleno=$((20 - ${#valores[@]}))
    (( relleno > 0 )) && printf '%*s' "$relleno" ''
    grafica "${valores[@]}"
}
