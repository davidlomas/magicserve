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
# Usar argumentos si se proporcionan, de lo contrario usar config (NODE_PORT)
PORT=${2:-$NODE_PORT}

LOG_FILE="local/logs/node_server.log"
PID_FILE="local/.node_server.pid"

usage() {
    echo "Uso:"
    echo "  ./local/node-server.sh start [puerto]"
    echo "  ./local/node-server.sh stop"
    echo "  ./local/node-server.sh status"
    echo ""
    echo "Configuración actual (config.sh o defaults):"
    echo "  PUERTO NODE: ${PORT:-No definido}"
    echo ""
    echo "Ejemplos:"
    echo "  ./local/node-server.sh start"
    echo "  ./local/node-server.sh start 3000"
    exit 1
}

start() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if ps -p $PID > /dev/null; then
            echo "⚠️  El servidor Node ya está corriendo (PID: $PID)."
            exit 1
        else
            echo "⚠️  El archivo PID existe pero el proceso no. Limpiando..."
            rm "$PID_FILE"
        fi
    fi

    if [ -z "$PORT" ]; then
        echo "❌ Error: Falta el puerto. Defínelo en config.sh (NODE_PORT) o pásalo como argumento."
        usage
    fi

    echo "🚀 Iniciando servidor Node (npm run dev) en puerto $PORT..."
    echo "📄 Logs en: $LOG_FILE"

    # Ejecutar npm run dev pasando el puerto como flag
    nohup npm run dev -- --port $PORT > "$LOG_FILE" 2>&1 &
    PID=$!
    echo $PID > "$PID_FILE"
    echo "✅ Servidor Node corriendo en segundo plano. PID: $PID"
}

stop() {
    if [ ! -f "$PID_FILE" ]; then
        echo "❌ No se encontró archivo PID. ¿El servidor Node está corriendo?"
        exit 1
    fi

    PID=$(cat "$PID_FILE")
    if ps -p $PID > /dev/null; then
        kill $PID
        echo "🛑 Servidor Node detenido (PID: $PID)."
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
            echo "🟢 Servidor Node corriendo (PID: $PID)"
            echo "📄 Logs: tail -f $LOG_FILE"
        else
            echo "🔴 Archivo PID existe ($PID) pero el proceso no está corriendo."
        fi
    else
        echo "⚪️ Servidor Node detenido."
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
