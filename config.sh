# Define URL_MONITOR en el entorno para no guardar el token del webhook en el repo.
URL_MONITOR="${URL_MONITOR:-CAMBIAR_URL_MONITOR}"
# Si no se configura otra dirección, las alertas usan el webhook de monitor.
URL_ALERTAS="${URL_ALERTAS:-$URL_MONITOR}"
# Endpoint de consulta del canal monitor (GET).
URL_CANAL="${URL_CANAL:-http://62.238.114.81:8089/sync}"
INTERVALO_DEF="${INTERVALO_DEF:-10}"

# Calcula la carpeta del proyecto para que las rutas funcionen desde cualquier lugar.
CONFIG_SOURCE="${BASH_SOURCE[0]//\\//}"
CONFIG_DIR="${CONFIG_SOURCE%/*}"
if [[ "$CONFIG_DIR" == "$CONFIG_SOURCE" ]]; then
    CONFIG_DIR=.
fi
DIR="$(cd -- "$CONFIG_DIR" && pwd)"
FICHERO_UMBRALES="${FICHERO_UMBRALES:-$DIR/umbrales.json}"