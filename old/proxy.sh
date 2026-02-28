#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Cargar configuración desde el mismo directorio del script
if [ -f "$SCRIPT_DIR/config.sh" ]; then
    source "$SCRIPT_DIR/config.sh"
fi

ACTION=$1
# Usar argumentos si se proporcionan, de lo contrario usar config
DOMAIN=${2:-$DOMAIN}
API_PORT=${3:-$PORT}

HOSTS_FILE="/etc/hosts"
NGINX_SERVER_DIR="/opt/homebrew/etc/nginx/servers"
NGINX_CONF="$NGINX_SERVER_DIR/${DOMAIN}.conf"

CERT_DIR="$HOME/.ssl"
CERT="$CERT_DIR/$DOMAIN.pem"
KEY="$CERT_DIR/$DOMAIN-key.pem"

usage() {
    echo "Uso:"
    echo "  ./local/proxy.sh on [dominio] [puerto]"
    echo "  ./local/proxy.sh off [dominio]"
    echo "  ./local/proxy.sh status [dominio]"
    echo ""
    echo "Configuración actual (config.sh):"
    echo "  DOMINIO: ${DOMAIN:-No definido}"
    echo "  PUERTO API: ${API_PORT:-No definido}"
    echo ""
    echo "Ejemplos:"
    echo "  ./local/proxy.sh on"
    echo "  ./local/proxy.sh on mi-api.local 3000"
    echo "  ./local/proxy.sh off"
}

enable() {
    echo "🔐 ACTIVANDO $DOMAIN en LOCAL (Puerto: $API_PORT) con SSL..."

    if ! command -v mkcert &> /dev/null; then
        echo "❌ mkcert no instalado → brew install mkcert"
        exit 1
    fi

    if ! command -v nginx &> /dev/null; then
        echo "❌ nginx no instalado → brew install nginx"
        exit 1
    fi

    mkcert -install > /dev/null 2>&1
    mkdir -p "$CERT_DIR" "$NGINX_SERVER_DIR"
    sudo chown -R $(whoami) "$CERT_DIR"

    if [ ! -f "$CERT" ] || [ ! -f "$KEY" ]; then
        echo "🆕 Generando certificado SSL para $DOMAIN..."
        mkcert -cert-file "$CERT" -key-file "$KEY" "$DOMAIN"
    fi

    # Limpiar entrada anterior en hosts si existe
    sudo sed -i '' "/[[:space:]]$DOMAIN$/d" "$HOSTS_FILE"
    
    echo "127.0.0.1    $DOMAIN" | sudo tee -a "$HOSTS_FILE" > /dev/null

    # Crear configuración de Nginx
    sudo tee "$NGINX_CONF" > /dev/null <<EOF
server {
    listen 443 ssl;
    server_name $DOMAIN;

    ssl_certificate     $CERT;
    ssl_certificate_key $KEY;

    location / {
        proxy_pass http://localhost:$API_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}

server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}
EOF

    if sudo nginx -t; then
        sudo nginx -s reload || sudo nginx
    else
        echo "❌ Error en configuración de Nginx. Revisa $NGINX_CONF"
        exit 1
    fi

    echo "✅ LOCAL ACTIVO"
    echo "🔌 https://$DOMAIN"
    echo "🔌 API puerto → localhost:$API_PORT"
}

disable() {
    echo "🌍 DESACTIVANDO $DOMAIN (Volviendo a producción/normal)..."

    sudo sed -i '' "/[[:space:]]$DOMAIN$/d" "$HOSTS_FILE"

    if [ -f "$NGINX_CONF" ]; then
        sudo rm "$NGINX_CONF"
        sudo nginx -t && sudo nginx -s reload
    else
        echo "⚠️  No se encontró configuración Nginx para $DOMAIN"
    fi

    echo "✅ $DOMAIN DESACTIVADO"
}

status() {
    if grep -q "[[:space:]]$DOMAIN$" "$HOSTS_FILE"; then
        echo "🟢 ESTADO: LOCAL ($DOMAIN)"
        echo "→ https://$DOMAIN"
        if [ -f "$NGINX_CONF" ]; then
             echo "→ Config Nginx activa: $NGINX_CONF"
        fi
    else
        echo "🔵 ESTADO: INACTIVO / PRODUCCIÓN ($DOMAIN)"
    fi
}

case "$ACTION" in
    on)
        if [ -z "$DOMAIN" ] || [ -z "$API_PORT" ]; then
            echo "❌ Error: Faltan argumentos (Dominio y Puerto) y no están en config."
            usage
            exit 1
        fi
        enable
        ;;
    off)
        if [ -z "$DOMAIN" ]; then
            echo "❌ Error: Falta el dominio."
            usage
            exit 1
        fi
        disable
        ;;
    status)
        if [ -z "$DOMAIN" ]; then
            echo "❌ Error: Falta el dominio."
            usage
            exit 1
        fi
        status
        ;;
    *)
        usage
        exit 1
        ;;
esac
