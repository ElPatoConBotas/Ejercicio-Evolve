#!/usr/bin/env bash

# Ejecuta el agente una sola vez y captura el POST sin usar la red.
script_source="${BASH_SOURCE[0]//\\//}"
directorio_script="${script_source%/*}"
if [[ "$directorio_script" == "$script_source" ]]; then
    directorio_script=.
fi
directorio_pruebas="$(cd -- "$directorio_script" && pwd)"
DIR="$(cd -- "$directorio_pruebas/.." && pwd)"

if ! command -v jq >/dev/null 2>&1; then
    printf 'FALLO: hace falta jq para validar el contrato\n' >&2
    exit 1
fi

TEMP_DIR=$(mktemp -d) || {
    printf 'FALLO: no se pudo crear el directorio temporal\n' >&2
    exit 1
}
trap 'rm -rf -- "$TEMP_DIR"' EXIT

export CAPTURE_JSON="$TEMP_DIR/informe.json"
export URL_MONITOR="http://127.0.0.1:9/sin-red"

# Git Bash no ofrece el formato Linux de df/ps; se simulan esas dos salidas
# únicamente allí. En Kali se prueban los comandos reales del sistema.
case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        df() {
            printf 'Filesystem 1024-blocks Used Available Use%% Mounted on\n'
            printf '/dev/mock 100000 40000 60000 40%% /\n'
        }
        ps() {
            printf '1234 proceso_a 5.0\n1235 proceso_b 3.0\n1236 proceso_c 1.0\n'
        }
        export -f df ps
        ;;
esac

# Esta función sustituye curl en el proceso Bash hijo y guarda el cuerpo del POST.
curl() {
    while (($#)); do
        if [[ "$1" == "-d" && -n "${2:-}" ]]; then
            printf '%s\n' "$2" > "$CAPTURE_JSON"
            return 0
        fi
        shift
    done
    return 1
}
export -f curl

if ! bash "$DIR/agente.sh" -o -i 1; then
    printf 'FALLO: el agente no pudo generar y enviar el informe de prueba\n' >&2
    exit 1
fi

if [[ ! -s "$CAPTURE_JSON" ]]; then
    printf 'FALLO: curl simulado no recibió el JSON del agente\n' >&2
    exit 1
fi

if jq -e '
    (.host | type) == "string"
    and (.ts | type) == "string"
    and (.ts | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))
    and (.cpu_pct | type) == "number"
    and (.mem.total_mb | type) == "number"
    and (.mem.usada_mb | type) == "number"
    and (.mem.pct | type) == "number"
    and (.disco | type) == "array"
    and all(.disco[]; (.pct | type) == "number")
    and (.carga | type) == "array"
    and (.carga | length) == 3
    and all(.carga[]; type == "number")
    and (.uptime_s | type) == "number"
    and (.top_procesos | type) == "array"
    and (.top_procesos | length) == 3
    and all(.top_procesos[]; (.pid | type) == "number" and (.cpu | type) == "number")
' "$CAPTURE_JSON" >/dev/null; then
    printf 'OK: el informe del agente cumple el contrato JSON\n'
else
    printf 'FALLO: el informe del agente no cumple el contrato JSON\n' >&2
    jq . "$CAPTURE_JSON"
    exit 1
fi
