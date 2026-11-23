#!/usr/bin/env bash
set -euo pipefail

directorio_script="${BASH_SOURCE[0]%/*}"
if [[ "$directorio_script" == "${BASH_SOURCE[0]}" ]]; then
    directorio_script=.
fi
directorio_pruebas="$(cd -- "$directorio_script" && pwd)"
raiz_proyecto="$(cd -- "$directorio_pruebas/.." && pwd)"
archivo_umbrales="$raiz_proyecto/umbrales.json"
umbrales_originales=$(<"$archivo_umbrales")

restaurar_umbrales() {
    printf '%s\n' "$umbrales_originales" > "$archivo_umbrales"
}
trap restaurar_umbrales EXIT

source "$raiz_proyecto/lib/colores.sh"
source "$raiz_proyecto/lib/grafica.sh"
source "$raiz_proyecto/lib/alertas.sh"

FICHERO_UMBRALES=$archivo_umbrales
cargar_umbrales

comprobar_color() {
    local valor=$1 esperado=$2 obtenido
    obtenido=$(color_por_umbral "$valor")
    if [[ "$obtenido" != "$esperado" ]]; then
        printf 'FALLO: color_por_umbral %s devolvió un color inesperado\n' "$valor" >&2
        exit 1
    fi
    printf 'OK: color_por_umbral %s\n' "$valor"
}

comprobar_color 30 $'\033[32m'
comprobar_color 70 $'\033[33m'
comprobar_color 90 $'\033[31m'

# Cambia el umbral rojo para verificar que se vuelve a leer del fichero.
printf '{ "amarillo": 60, "rojo": 50 }\n' > "$archivo_umbrales"
cargar_umbrales
comprobar_color 70 $'\033[31m'
printf 'OK: umbral rojo personalizado\n'

grafica_obtenida=$(grafica 5 20 40 60 80 95)
if [[ "$grafica_obtenida" != '▁▂▄▅▇█' ]]; then
    printf 'FALLO: grafica produjo "%s"\n' "$grafica_obtenida" >&2
    exit 1
fi
printf 'OK: grafica %s\n' "$grafica_obtenida"

# Simula curl para no enviar solicitudes a un servicio real.
CURL_LLAMADAS=0
curl() {
    CURL_LLAMADAS=$((CURL_LLAMADAS + 1))
    echo "curl simulado: $*"
}
URL_ALERTAS='https://ejemplo.invalid/alertas'
ESTADO_ANT=()
CPU_ANT=()

comprobar_alerta pc1 30
if [[ "$CURL_LLAMADAS" -ne 0 ]]; then
    printf 'FALLO: se alertó durante la primera observación\n' >&2
    exit 1
fi

comprobar_alerta pc1 95
if [[ "$CURL_LLAMADAS" -ne 1 ]]; then
    printf 'FALLO: se esperaba exactamente una alerta tras el cambio de estado\n' >&2
    exit 1
fi
printf 'OK: comprobar_alerta envió una alerta solo al cambiar de estado\n'
