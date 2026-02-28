#!/bin/bash

# run.sh

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CONFIG_FILE="$SCRIPT_DIR/config.json"
LOGS_DIR="$SCRIPT_DIR/logs"

# Asegurar que el directorio de logs existe
mkdir -p "$LOGS_DIR"

if [ ! -f "$CONFIG_FILE" ]; then
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
    echo "  ./run.sh [start|stop|status]"
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

case "$ACTION" in
    start)
        start_all
        ;;
    stop)
        stop_all
        ;;
    status)
        status
        ;;
    *)
        usage
        ;;
esac
