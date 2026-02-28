#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Cargar configuración desde el mismo directorio del script
if [ -f "$SCRIPT_DIR/config.sh" ]; then
    source "$SCRIPT_DIR/config.sh"
fi

COMMAND=$1

usage() {
    echo "Uso:"
    echo "  ./local/run.sh [php|node|stop]"
    echo ""
    echo "Opciones:"
    echo "  php   → Inicia Servidor PHP + Proxy ($DOMAIN -> $PHP_PORT)"
    echo "  node  → Inicia Servidor Node + Proxy ($DOMAIN -> $NODE_PORT)"
    echo "  stop  → Detiene TODOS los servicios (PHP, Node, Proxy)"
    exit 1
}

start_php() {
    echo "🚀 Iniciando entorno PHP..."
    "$SCRIPT_DIR/php-server.sh" start
    
    echo "🔗 Conectando Proxy a puerto PHP ($PHP_PORT)..."
    "$SCRIPT_DIR/proxy.sh" on "$DOMAIN" "$PHP_PORT"
}

start_node() {
    echo "🚀 Iniciando entorno Node..."
    "$SCRIPT_DIR/node-server.sh" start
    
    echo "🔗 Conectando Proxy a puerto Node ($NODE_PORT)..."
    "$SCRIPT_DIR/proxy.sh" on "$DOMAIN" "$NODE_PORT"
}

stop_all() {
    echo "🛑 Deteniendo todos los servicios..."
    "$SCRIPT_DIR/php-server.sh" stop 2>/dev/null
    "$SCRIPT_DIR/node-server.sh" stop 2>/dev/null
    "$SCRIPT_DIR/proxy.sh" off 2>/dev/null
    echo "✅ Todo detenido."
}

case "$COMMAND" in
    php)
        start_php
        ;;
    node)
        start_node
        ;;
    stop)
        stop_all
        ;;
    *)
        usage
        ;;
esac
