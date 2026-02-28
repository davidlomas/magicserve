#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Cargar configuración desde el mismo directorio del script
if [ -f "$SCRIPT_DIR/config.sh" ]; then
    source "$SCRIPT_DIR/config.sh"
fi

# Cambiar al directorio raíz del proyecto para que las rutas relativas funcionen
cd "$PROJECT_ROOT"

ACTION=$1
# Usar argumentos si se proporcionan, de lo contrario usar config o valores por defecto
PORT=${2:-$PHP_PORT}
DOCROOT=${3:-$PHP_DOCROOT}

# Valores por defecto de seguridad si no hay config ni argumentos
DOCROOT=${DOCROOT:-.}

LOG_FILE="local/logs/php_server.log"
PID_FILE="local/.php_server.pid"

usage() {
    echo "Uso:"
    echo "  ./local/php-server.sh start [puerto] [directorio]"
    echo "  ./local/php-server.sh stop"
    echo "  ./local/php-server.sh status"
    echo ""
    echo "Configuración actual (config.sh o defaults):"
    echo "  PUERTO: ${PORT:-No definido}"
    echo "  DOCROOT: $DOCROOT (relativo a $PROJECT_ROOT)"
    echo ""
    echo "Ejemplos:"
    echo "  ./local/php-server.sh start"
    echo "  ./local/php-server.sh start 8000"
    exit 1
}

start() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if ps -p $PID > /dev/null; then
            echo "⚠️  El servidor PHP ya está corriendo (PID: $PID)."
            exit 1
        else
            echo "⚠️  El archivo PID existe pero el proceso no. Limpiando..."
            rm "$PID_FILE"
        fi
    fi

    if [ -z "$PORT" ]; then
        echo "❌ Error: Falta el puerto. Defínelo en config.sh (PHP_PORT) o pásalo como argumento."
        usage
    fi

    if [ ! -d "$DOCROOT" ]; then
        echo "❌ Error: El directorio '$DOCROOT' no existe."
        exit 1
    fi

    echo "🚀 Iniciando servidor PHP en http://localhost:$PORT (Root: $DOCROOT)..."
    echo "📄 Logs en: $LOG_FILE"

    nohup php -S "localhost:$PORT" -t "$DOCROOT" > "$LOG_FILE" 2>&1 &
    PID=$!
    echo $PID > "$PID_FILE"
    echo "✅ Servidor PHP corriendo en segundo plano. PID: $PID"
}

stop() {
    if [ ! -f "$PID_FILE" ]; then
        echo "❌ No se encontró archivo PID. ¿El servidor PHP está corriendo?"
        exit 1
    fi

    PID=$(cat "$PID_FILE")
    if ps -p $PID > /dev/null; then
        kill $PID
        echo "🛑 Servidor PHP detenido (PID: $PID)."
        rm "$PID_FILE"
    else
        echo "⚠️  El proceso $PID no está corriendo. Limpiando archivo PID."
        rm "$PID_FILE"
    fi
}

status() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if ps -p $PID > /dev/null; then
            echo "🟢 Servidor PHP corriendo (PID: $PID)"
            echo "📄 Logs: tail -f $LOG_FILE"
        else
            echo "🔴 Archivo PID existe ($PID) pero el proceso no está corriendo."
        fi
    else
        echo "⚪️ Servidor PHP detenido."
    fi
}

case "$ACTION" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    status)
        status
        ;;
    *)
        usage
        ;;
esac
