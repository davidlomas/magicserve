#!/bin/bash

# run.sh

# El directorio de trabajo actual (donde se ejecuta el comando)
SCRIPT_DIR="$(pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.json"
LOGS_DIR="$SCRIPT_DIR/logs"

# Asegurar que el directorio de logs existe
mkdir -p "$LOGS_DIR"

if [ "$1" != "stopall" ] && [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Error: config.json no encontrado."
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "❌ jq no instalado → brew install jq"
    exit 1
fi

ACTION=$1

usage() {
    echo "Uso:"
    echo "  ./run.sh [start|stop|stopall|status]"
    echo ""
    echo "  start    - Inicia todos los servicios del config.json"
    echo "  stop     - Detiene los servicios del config.json"
    echo "  stopall  - Busca y detiene TODOS los dominios (sin depender de config.json) y borra todo rastro"
    echo "  status   - Muestra el estado de los servicios"
    exit 1
}

start_server() {
    local PATH_DIR=$1
    local DOMAIN=$2
    local TYPE=$3
    local PORT=$4

    local PID_FILE="$SCRIPT_DIR/.${DOMAIN}.pid"

    echo "🚀 Iniciando $DOMAIN ($TYPE) en puerto $PORT..."

    # Navegar al directorio del proyecto relativo al script
    cd "$SCRIPT_DIR/$PATH_DIR" || {
        echo "❌ Error: Directorio $PATH_DIR no encontrado para $DOMAIN"
        return
    }

    if [ "$TYPE" == "node" ]; then
        nohup npm run dev -- --port $PORT > "$LOGS_DIR/${DOMAIN}.log" 2>&1 &
        local PID=$!
        echo $PID > "$PID_FILE"
        echo "✅ Node corriendo (PID: $PID)"
    elif [ "$TYPE" == "php" ]; then
        # El docroot por defecto para php es el directorio actual
        nohup php -S "localhost:$PORT" -t . > "$LOGS_DIR/${DOMAIN}.log" 2>&1 &
        local PID=$!
        echo $PID > "$PID_FILE"
        echo "✅ PHP corriendo (PID: $PID)"
    else
        echo "❌ Tipo $TYPE no soportado (usa 'node' o 'php')"
    fi
}

start_proxy() {
    local DOMAIN=$1
    local PORT=$2

    echo "🔐 Configurando SSL y Proxy Nginx para $DOMAIN -> $PORT..."

    local HOSTS_FILE="/etc/hosts"
    local NGINX_SERVER_DIR="/opt/homebrew/etc/nginx/servers"
    local NGINX_CONF="$NGINX_SERVER_DIR/${DOMAIN}.conf"
    local CERT_DIR="$HOME/.ssl"
    local CERT="$CERT_DIR/$DOMAIN.pem"
    local KEY="$CERT_DIR/$DOMAIN-key.pem"

    # Validar si mkcert y nginx están instalados
    if ! command -v mkcert &> /dev/null; then
        echo "❌ mkcert no instalado → brew install mkcert"
        exit 1
    fi
    if ! command -v nginx &> /dev/null; then
        echo "❌ nginx no instalado → brew install nginx"
        exit 1
    fi

    # Generar carpeta de certificados si no existe
    mkdir -p "$CERT_DIR" "$NGINX_SERVER_DIR"
    sudo chown -R $(whoami) "$CERT_DIR"

    # Instalar mkcert CA si no lo está (suave)
    mkcert -install > /dev/null 2>&1

    # Generar los certificados para el dominio si no existen
    if [ ! -f "$CERT" ] || [ ! -f "$KEY" ]; then
        echo "🆕 Generando certificado SSL para $DOMAIN..."
        mkcert -cert-file "$CERT" -key-file "$KEY" "$DOMAIN"
    fi

    # Limpiar en /etc/hosts el dominio y volver a añadirlo
    sudo sed -i '' "/[[:space:]]$DOMAIN$/d" "$HOSTS_FILE"
    echo "127.0.0.1    $DOMAIN" | sudo tee -a "$HOSTS_FILE" > /dev/null

    # Crear configuración de Nginx para el dominio
    sudo tee "$NGINX_CONF" > /dev/null <<EOF
server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate     $CERT;
    ssl_certificate_key $KEY;

    location / {
        proxy_pass http://localhost:$PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;

        # WebSockets Support (Vite HMR)
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}

server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}
EOF
}

start_all() {
    echo "🌟 Iniciando todos los servicios desde config.json..."

    local LENGTH=$(jq '. | length' "$CONFIG_FILE")
    for (( i=0; i<$LENGTH; i++ )); do
        local PATH_DIR=$(jq -r ".[$i].path" "$CONFIG_FILE")
        local DOMAIN=$(jq -r ".[$i].domain" "$CONFIG_FILE")
        local TYPE=$(jq -r ".[$i].type" "$CONFIG_FILE")
        local PORT=$(jq -r ".[$i].port" "$CONFIG_FILE")

        start_server "$PATH_DIR" "$DOMAIN" "$TYPE" "$PORT"
        start_proxy "$DOMAIN" "$PORT"
    done

    echo "🔄 Recargando Nginx..."
    if sudo nginx -t > /dev/null 2>&1; then
        sudo nginx -s reload || sudo nginx
        echo "✅ Nginx configurado exitosamente."
    else
        echo "❌ Error en configuración de Nginx. Revisa /opt/homebrew/etc/nginx/servers/"
    fi
    echo "🎉 ¡Todo listo!"
}

stop_all() {
    echo "🛑 Deteniendo todos los servicios..."

    local HOSTS_FILE="/etc/hosts"
    local NGINX_SERVER_DIR="/opt/homebrew/etc/nginx/servers"

    local LENGTH=$(jq '. | length' "$CONFIG_FILE")
    for (( i=0; i<$LENGTH; i++ )); do
        local DOMAIN=$(jq -r ".[$i].domain" "$CONFIG_FILE")
        local PID_FILE="$SCRIPT_DIR/.${DOMAIN}.pid"

        if [ -f "$PID_FILE" ]; then
            local PID=$(cat "$PID_FILE")
            if ps -p $PID > /dev/null; then
                kill $PID
                echo "🛑 Servidor para $DOMAIN detenido (PID: $PID)."
            else
                echo "⚠️ Proceso para $DOMAIN no encontrado (el archivo PID será limpiado)."
            fi
            rm "$PID_FILE"
        fi

        # Limpiar de /etc/hosts
        sudo sed -i '' "/[[:space:]]$DOMAIN$/d" "$HOSTS_FILE"

        # Eliminar configuración de nginx
        local NGINX_CONF="$NGINX_SERVER_DIR/${DOMAIN}.conf"
        if [ -f "$NGINX_CONF" ]; then
            sudo rm "$NGINX_CONF"
        fi
    done

    # Recargar nginx
    if sudo nginx -t > /dev/null 2>&1; then
        sudo nginx -s reload > /dev/null 2>&1
    fi

    echo "✅ Todo detenido."
}

status() {
    echo "📊 Estado de los servicios:"
    local LENGTH=$(jq '. | length' "$CONFIG_FILE")
    for (( i=0; i<$LENGTH; i++ )); do
        local DOMAIN=$(jq -r ".[$i].domain" "$CONFIG_FILE")
        local PID_FILE="$SCRIPT_DIR/.${DOMAIN}.pid"

        if [ -f "$PID_FILE" ]; then
            local PID=$(cat "$PID_FILE")
            if ps -p $PID > /dev/null; then
                 echo "🟢 $DOMAIN: Corriendo (PID: $PID)"
            else
                 echo "🔴 $DOMAIN: Archivo PID existe pero el proceso no está corriendo"
            fi
        else
            echo "⚪️ $DOMAIN: Detenido"
        fi
    done
}

stop_all_global() {
    echo "🔥 STOPALL: Buscando y eliminando TODOS los dominios y rastros de la computadora..."
    echo ""

    local HOSTS_FILE="/etc/hosts"
    local NGINX_SERVER_DIR="/opt/homebrew/etc/nginx/servers"
    local CERT_DIR="$HOME/.ssl"
    local FOUND_SOMETHING=false

    # ─── 1. Limpiar archivos .pid locales ───
    echo "🔍 Buscando archivos .pid locales..."
    for PID_FILE in "$SCRIPT_DIR"/.*.pid; do
        [ -f "$PID_FILE" ] || continue
        FOUND_SOMETHING=true
        local PID=$(cat "$PID_FILE")
        local BASENAME=$(basename "$PID_FILE")
        local DOMAIN_NAME=${BASENAME#.}
        DOMAIN_NAME=${DOMAIN_NAME%.pid}

        if ps -p $PID > /dev/null 2>&1; then
            kill $PID 2>/dev/null
            echo "  🛑 Proceso detenido: $DOMAIN_NAME (PID: $PID)"
        else
            echo "  ⚠️  Proceso ya no existía: $DOMAIN_NAME (PID: $PID)"
        fi
        rm -f "$PID_FILE"
    done
    if [ "$FOUND_SOMETHING" = false ]; then
        echo "  ✅ No se encontraron archivos .pid"
    fi

    # ─── 2. Matar TODOS los servidores PHP built-in de la computadora ───
    echo ""
    echo "🔍 Buscando servidores PHP built-in (php -S)..."
    local PHP_PIDS=$(pgrep -f "php -S" 2>/dev/null)
    if [ -n "$PHP_PIDS" ]; then
        echo "$PHP_PIDS" | while read PID; do
            local CMD=$(ps -p $PID -o args= 2>/dev/null)
            kill $PID 2>/dev/null
            echo "  🛑 PHP detenido (PID: $PID) → $CMD"
        done
    else
        echo "  ✅ No se encontraron servidores PHP"
    fi

    # ─── 3. Matar TODOS los servidores Node de desarrollo ───
    echo ""
    echo "🔍 Buscando servidores Node de desarrollo (vite, next, nuxt, webpack)..."
    local NODE_PIDS=$(pgrep -f "(vite|next dev|nuxt|webpack-dev-server|node.*dev)" 2>/dev/null)
    if [ -n "$NODE_PIDS" ]; then
        echo "$NODE_PIDS" | while read PID; do
            local CMD=$(ps -p $PID -o args= 2>/dev/null | head -c 120)
            kill $PID 2>/dev/null
            echo "  🛑 Node detenido (PID: $PID) → $CMD"
        done
    else
        echo "  ✅ No se encontraron servidores Node de desarrollo"
    fi

    # ─── 4. Eliminar TODAS las configuraciones de nginx en servers/ ───
    echo ""
    echo "🔍 Buscando configuraciones de Nginx..."
    FOUND_SOMETHING=false
    if [ -d "$NGINX_SERVER_DIR" ]; then
        for CONF_FILE in "$NGINX_SERVER_DIR"/*.conf; do
            [ -f "$CONF_FILE" ] || continue
            FOUND_SOMETHING=true
            local CONF_NAME=$(basename "$CONF_FILE")
            sudo rm -f "$CONF_FILE"
            echo "  🗑️  Eliminado: $CONF_NAME"
        done
    fi
    if [ "$FOUND_SOMETHING" = false ]; then
        echo "  ✅ No se encontraron configuraciones de Nginx"
    fi

    # ─── 5. Limpiar /etc/hosts (TODAS las entradas custom de 127.0.0.1) ───
    echo ""
    echo "🔍 Limpiando /etc/hosts (todas las entradas custom)..."
    # Contar entradas de 127.0.0.1 que NO sean localhost
    local HOSTS_BEFORE=$(grep -c '^127\.0\.0\.1' "$HOSTS_FILE" 2>/dev/null || echo 0)
    # Eliminar todas las líneas 127.0.0.1 que NO sean localhost
    sudo sed -i '' '/^127\.0\.0\.1[[:space:]]\{1,\}localhost$/!{ /^127\.0\.0\.1/d; }' "$HOSTS_FILE"
    local HOSTS_AFTER=$(grep -c '^127\.0\.0\.1' "$HOSTS_FILE" 2>/dev/null || echo 0)
    local REMOVED=$((HOSTS_BEFORE - HOSTS_AFTER))
    if [ $REMOVED -gt 0 ]; then
        echo "  🗑️  Se eliminaron $REMOVED entradas custom de /etc/hosts"
    else
        echo "  ✅ No se encontraron entradas custom en /etc/hosts"
    fi

    # ─── 6. Eliminar TODO el contenido de ~/.ssl/ ───
    echo ""
    echo "🔍 Limpiando $CERT_DIR (todos los archivos)..."
    if [ -d "$CERT_DIR" ] && [ "$(ls -A "$CERT_DIR" 2>/dev/null)" ]; then
        local SSL_COUNT=$(ls -1 "$CERT_DIR" | wc -l | tr -d ' ')
        rm -rf "$CERT_DIR"/*
        echo "  🗑️  Se eliminaron $SSL_COUNT archivos de $CERT_DIR"
    else
        echo "  ✅ No se encontraron archivos en $CERT_DIR"
    fi

    # ─── 7. Eliminar logs ───
    echo ""
    echo "🔍 Limpiando logs..."
    if [ -d "$LOGS_DIR" ] && [ "$(ls -A "$LOGS_DIR" 2>/dev/null)" ]; then
        rm -f "$LOGS_DIR"/*
        echo "  🗑️  Logs eliminados"
    else
        echo "  ✅ No se encontraron logs"
    fi

    # ─── 8. Detener Nginx completamente ───
    echo ""
    echo "🔍 Deteniendo Nginx..."
    if pgrep -x nginx > /dev/null 2>&1; then
        sudo nginx -s stop > /dev/null 2>&1
        echo "  🛑 Nginx detenido"
    else
        echo "  ✅ Nginx no estaba corriendo"
    fi

    echo ""
    echo "🧹 ¡Todo limpio! No queda rastro."
}

case "$ACTION" in
    start)
        start_all
        ;;
    stop)
        stop_all
        ;;
    stopall)
        stop_all_global
        ;;
    status)
        status
        ;;
    *)
        usage
        ;;
esac
