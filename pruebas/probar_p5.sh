#!/usr/bin/env bash

# Ejecutar las comprobaciones sin modificar los ficheros reales del proyecto.
script_source="${BASH_SOURCE[0]//\\//}"
directorio_script="${script_source%/*}"
if [[ "$directorio_script" == "$script_source" ]]; then
    directorio_script=.
fi
directorio_pruebas="$(cd -- "$directorio_script" && pwd)"
DIR="$(cd -- "$directorio_pruebas/.." && pwd)"

source "$DIR/lib/colores.sh"
source "$DIR/lib/grafica.sh"
source "$DIR/lib/alertas.sh"

TEMP_DIR=$(mktemp -d) || {
    printf 'FALLO: no se pudo crear el directorio temporal\n' >&2
    exit 1
}
trap 'rm -rf -- "$TEMP_DIR"' EXIT

total=0
fallos=0

comprobar() {
    local nombre="$1"
    shift
    total=$((total + 1))
    if "$@"; then
        printf 'OK: %s\n' "$nombre"
    else
        printf 'FALLO: %s\n' "$nombre"
        fallos=$((fallos + 1))
    fi
}

igual() {
    [[ "$1" == "$2" ]]
}

sin_salida() {
    [[ ! -s "$1" ]]
}

jq_valido() {
    jq -e "$1" "$2" >/dev/null 2>&1
}

grafica_sin_salto() {
    local esperado="$1"
    local recibido
    shift

    grafica "$@" > "$TEMP_DIR/grafica.txt"
    IFS= read -r -d '' recibido < "$TEMP_DIR/grafica.txt" || true
    [[ "$recibido" == "$esperado" ]]
}

if ! command -v jq >/dev/null 2>&1 || ! command -v awk >/dev/null 2>&1; then
    printf 'FALLO: se necesitan jq y awk para ejecutar estas pruebas\n' >&2
    exit 1
fi

# Todas las rutas de configuración y estado apuntan a copias temporales.
DIR="$TEMP_DIR/proyecto"
mkdir -p "$DIR/estado"
FICHERO_UMBRALES="$TEMP_DIR/umbrales.json"
printf '{ "amarillo": 60, "rojo": 85 }\n' > "$FICHERO_UMBRALES"
cargar_umbrales

# Colores habituales y los cuatro límites solicitados.
comprobar 'CPU 30 es verde' igual "$(color_por_umbral 30)" $'\033[32m'
comprobar 'CPU 70 es amarillo' igual "$(color_por_umbral 70)" $'\033[33m'
comprobar 'CPU 90 es rojo' igual "$(color_por_umbral 90)" $'\033[31m'
comprobar '59.9 es verde' igual "$(color_por_umbral 59.9)" $'\033[32m'
comprobar '60 es amarillo' igual "$(color_por_umbral 60)" $'\033[33m'
comprobar '85 es amarillo' igual "$(color_por_umbral 85)" $'\033[33m'
comprobar '85.1 es rojo' igual "$(color_por_umbral 85.1)" $'\033[31m'
comprobar 'valor vacío es gris' igual "$(color_por_umbral '')" $'\033[90m'
comprobar 'valor no numérico es gris' igual "$(color_por_umbral abc)" $'\033[90m'
comprobar 'color CAÍDO es rojo en negrita' igual "$(color_caido)" $'\033[1;31m'

# Verificar umbrales configurables y los dos casos de reserva.
printf '{ "amarillo": 60, "rojo": 50 }\n' > "$FICHERO_UMBRALES"
cargar_umbrales
comprobar 'rojo personalizado: 70 es rojo' igual "$(color_por_umbral 70)" $'\033[31m'

FICHERO_UMBRALES="$TEMP_DIR/no-existe.json"
errores="$TEMP_DIR/errores_umbral.txt"
cargar_umbrales 2>"$errores"
comprobar 'fichero de umbrales ausente usa 60/85' \
    igual "$U_AMA/$U_ROJ" '60/85'
comprobar 'fichero ausente no muestra errores' sin_salida "$errores"

FICHERO_UMBRALES="$TEMP_DIR/vacio.json"
: > "$FICHERO_UMBRALES"
cargar_umbrales 2>"$errores"
comprobar 'fichero vacío usa 60/85' igual "$U_AMA/$U_ROJ" '60/85'
comprobar 'fichero vacío no muestra errores' sin_salida "$errores"

FICHERO_UMBRALES="$TEMP_DIR/roto.json"
printf '{ JSON roto\n' > "$FICHERO_UMBRALES"
cargar_umbrales 2>"$errores"
comprobar 'JSON roto usa 60/85' igual "$U_AMA/$U_ROJ" '60/85'
comprobar 'JSON roto no muestra errores' sin_salida "$errores"

FICHERO_UMBRALES="$TEMP_DIR/tipos_invalidos.json"
printf '{ "amarillo": "sesenta", "rojo": 50 }\n' > "$FICHERO_UMBRALES"
cargar_umbrales 2>"$errores"
comprobar 'umbral no numérico usa su valor predeterminado' \
    igual "$U_AMA/$U_ROJ" '60/50'
comprobar 'umbral no numérico no muestra errores' sin_salida "$errores"

# La gráfica usa los ocho niveles y limita valores fuera del rango.
comprobar 'gráfica del ejemplo' \
    grafica_sin_salto '▁▂▄▅▇█' 5 20 40 60 80 95
comprobar 'gráfica limita 0, 100, -5 y 150' \
    igual "$(grafica 0 100 -5 150)" '▁█▁█'
comprobar 'gráfica ignora valores no numéricos' \
    igual "$(grafica 5 abc 20)" '▁▂'

# Crear 25 informes ordenados para probar el recorte a los últimos veinte.
json_prueba=$(jq -cn '
    (
    [range(0; 25) as $i |
        {datos: {
            host: "pc1",
            ts: ((now - (24 - $i)) | todateiso8601),
            cpu_pct: ($i + 1),
            mem: {pct: 30},
            disco: [],
            carga: [0.1, 0.2, 0.3]
        }}
    ]
    + [{datos: {
        host: "pc1",
        ts: ((now + 60) | todateiso8601),
        cpu_pct: 99
    }}]
    )
')
cpu_obtenidas=$(ultimos_cpu pc1 "$json_prueba")
locales=()
while IFS= read -r valor; do
    [[ -n "$valor" ]] && locales+=("$valor")
done <<< "$cpu_obtenidas"
comprobar 'ultimos_cpu devuelve exactamente 20 valores' \
    igual "${#locales[@]}" 20
comprobar 'ultimos_cpu ordena y conserva los valores 6 a 25' \
    igual "${locales[0]:-}" 6
comprobar 'ultimos_cpu termina con el valor 25' \
    igual "${locales[19]:-}" 25
comprobar 'JSON inválido no produce valores' \
    igual "$(ultimos_cpu pc1 '{ JSON roto')" ''

json_corto='[{"datos":{"host":"pc2","ts":"2026-11-17T10:00:00Z","cpu_pct":0,"mem":{"pct":20},"disco":[],"carga":[0,0,0]}},{"datos":{"host":"pc2","ts":"2026-11-17T10:00:01Z","cpu_pct":100,"mem":{"pct":20},"disco":[],"carga":[0,0,0]}}]'
comprobar 'grafica_host rellena a veinte caracteres' \
    igual "$(grafica_host pc2 "$json_corto")" '                  ▁█'

# ALERTAS_DRY_RUN muestra los JSON en archivos para conservar el estado en memoria.
export ALERTAS_DRY_RUN=1
unset URL_ALERTAS
ESTADO_ANT=()

comprobar_alerta pc1 30 > "$TEMP_DIR/alerta_inicial.json"
comprobar 'primera observación no alerta' sin_salida "$TEMP_DIR/alerta_inicial.json"

comprobar_alerta pc1 95 > "$TEMP_DIR/alerta_critica.json"
comprobar 'cambio ok a critico publica alerta' \
    jq_valido '.de == "ok" and .a == "critico"' "$TEMP_DIR/alerta_critica.json"
comprobar 'alerta CPU crítica lleva número y fecha UTC' \
    jq_valido '(.cpu_pct | type) == "number" and (.ts | test("Z$"))' \
    "$TEMP_DIR/alerta_critica.json"

comprobar_alerta pc1 96 > "$TEMP_DIR/alerta_repetida.json"
comprobar 'mismo estado critico no alerta otra vez' sin_salida "$TEMP_DIR/alerta_repetida.json"

comprobar_alerta pc1 20 > "$TEMP_DIR/alerta_recuperada.json"
comprobar 'cambio critico a ok publica alerta' \
    jq_valido '.de == "critico" and .a == "ok"' "$TEMP_DIR/alerta_recuperada.json"
comprobar 'alerta de recuperación lleva CPU numérica' \
    jq_valido '(.cpu_pct | type) == "number"' "$TEMP_DIR/alerta_recuperada.json"

comprobar_alerta pc1 CAIDO > "$TEMP_DIR/alerta_caida.json"
comprobar 'cambio a CAIDO publica cpu_pct null' \
    jq_valido '.de == "ok" and .a == "caido" and .cpu_pct == null' \
    "$TEMP_DIR/alerta_caida.json"
comprobar 'cpu_pct de CAIDO tiene tipo null' \
    jq_valido '(.cpu_pct | type) == "null"' "$TEMP_DIR/alerta_caida.json"

comprobar_alerta pc1 30 > "$TEMP_DIR/alerta_fin_caida.json"
comprobar 'recuperación desde CAIDO incluye recuperado true' \
    jq_valido '.de == "caido" and .a == "ok" and .recuperado == true' \
    "$TEMP_DIR/alerta_fin_caida.json"
comprobar 'CPU tras recuperar desde CAIDO es numérica' \
    jq_valido '(.cpu_pct | type) == "number"' "$TEMP_DIR/alerta_fin_caida.json"

# Guardar y volver a cargar el estado usando solo el directorio temporal.
guardar_estados
ESTADO_ANT=()
cargar_estados
comprobar 'persistencia restaura el estado del host' \
    igual "${ESTADO_ANT[pc1]:-}" ok

printf 'línea corrupta\npc2=desconocido\n' \
    > "$DIR/estado/estado_anterior.txt"
cargar_estados
comprobar 'estado corrupto se ignora en silencio' \
    igual "${#ESTADO_ANT[@]}" 0

printf 'Resumen: %d comprobaciones, %d fallidas.\n' "$total" "$fallos"
(( fallos == 0 ))
