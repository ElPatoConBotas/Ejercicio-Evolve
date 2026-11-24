#!/usr/bin/env bash

# Comprueba el renderizado del panel con un canal simulado y sin red.
script_source="${BASH_SOURCE[0]//\\//}"
directorio_script="${script_source%/*}"
if [[ "$directorio_script" == "$script_source" ]]; then
    directorio_script=.
fi
directorio_pruebas="$(cd -- "$directorio_script" && pwd)"
DIR="$(cd -- "$directorio_pruebas/.." && pwd)"

if ! command -v jq >/dev/null 2>&1 || ! command -v awk >/dev/null 2>&1; then
    printf 'FALLO: hacen falta jq y awk para probar el panel\n' >&2
    exit 1
fi

TEMP_DIR=$(mktemp -d) || {
    printf 'FALLO: no se pudo crear el directorio temporal\n' >&2
    exit 1
}
trap 'rm -rf -- "$TEMP_DIR"' EXIT

export CANAL_JSON
CANAL_JSON=$(jq -cn '
    def informe($host; $edad; $cpu; $mem):
        {datos: {
            host: $host,
            ts: ((now - $edad) | todateiso8601),
            cpu_pct: $cpu,
            mem: {total_mb: 1000, usada_mb: 400, pct: $mem},
            disco: [{montaje: "/", pct: 45}],
            carga: [0.2, 0.3, 0.4],
            uptime_s: 3600,
            top_procesos: [{pid: 123, cmd: "test", cpu: 1.0}]
        }};
    def informe_directo($host; $edad; $cpu; $mem):
        {
            host: $host,
            ts: ((now - $edad) | todateiso8601),
            cpu_pct: $cpu,
            mem: {total_mb: 1000, usada_mb: 400, pct: $mem},
            disco: [{montaje: "/", pct: 45}],
            carga: [0.2, 0.3, 0.4],
            uptime_s: 3600,
            top_procesos: [{pid: 124, cmd: "test", cpu: 1.0}]
        };
    {messages: [
        informe("pc1"; 60; 10; 30),
        informe("pc1"; 5; 95; 30),
        informe("pc2"; 5; 40; 70),
        informe("pc3"; 40; 30; 30),
        informe_directo("pc4"; 5; 50; 40),
        {datos: {
            host: "alerta-test",
            ts: (now | todateiso8601),
            de: "ok",
            a: "critico",
            cpu_pct: 95
        }}
    ]}
')

curl() {
    printf '%s' "$CANAL_JSON"
}
export -f curl

export ALERTAS_DRY_RUN=1
export FICHERO_ESTADOS="$TEMP_DIR/estado_anterior.txt"

if ! salida=$(bash "$DIR/panel.sh" -o 2>"$TEMP_DIR/panel.err"); then
    printf 'FALLO: el panel no terminó correctamente\n' >&2
    cat "$TEMP_DIR/panel.err" >&2
    exit 1
fi

fallos=0
comprobar_texto() {
    local descripcion="$1"
    local texto="$2"
    if [[ "$salida" == *"$texto"* ]]; then
        printf 'OK: %s\n' "$descripcion"
    else
        printf 'FALLO: %s\n' "$descripcion"
        fallos=$((fallos + 1))
    fi
}

comprobar_texto 'el panel muestra los hosts del canal' 'pc1'
comprobar_texto 'se elige el último informe de pc1 (CPU 95%)' '95%'
comprobar_texto 'se muestran las métricas de pc2' '70%'
comprobar_texto 'el informe antiguo aparece CAÍDO' 'CAÍDO'
comprobar_texto 'también se aceptan informes directos en el canal' 'pc4'

# Las alertas no tienen las métricas obligatorias y no deben aparecer como hosts.
if [[ "$salida" != *"alerta-test"* ]]; then
    printf 'OK: las alertas no se confunden con informes\n'
else
    printf 'FALLO: una alerta se confundió con un informe\n'
    fallos=$((fallos + 1))
fi

if [[ ! -s "$TEMP_DIR/panel.err" ]]; then
    printf 'OK: el panel no produjo errores con el canal simulado\n'
else
    printf 'FALLO: el panel escribió errores con el canal simulado\n'
    cat "$TEMP_DIR/panel.err" >&2
    fallos=$((fallos + 1))
fi

# El panel también debe seguir funcionando si el endpoint falla o viene vacío.
curl() {
    return 7
}
export -f curl
if salida_error=$(bash "$DIR/panel.sh" -o 2>"$TEMP_DIR/panel.err") &&
    [[ "$salida_error" == *"No se pudo consultar"* ]] &&
    [[ ! -s "$TEMP_DIR/panel.err" ]]; then
    printf 'OK: un fallo de curl no detiene el panel\n'
else
    printf 'FALLO: el panel no toleró un fallo de curl\n'
    fallos=$((fallos + 1))
fi

curl() {
    printf '{}'
}
export -f curl
if salida_vacia=$(bash "$DIR/panel.sh" -o 2>"$TEMP_DIR/panel.err") &&
    [[ "$salida_vacia" == *"no contiene informes compatibles"* ]] &&
    [[ ! -s "$TEMP_DIR/panel.err" ]]; then
    printf 'OK: un canal vacío no rompe el panel\n'
else
    printf 'FALLO: el panel no toleró un JSON vacío\n'
    fallos=$((fallos + 1))
fi

printf 'Resumen integración: %d fallo(s).\n' "$fallos"
(( fallos == 0 ))
