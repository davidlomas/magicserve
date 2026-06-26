#!/bin/bash

# run.sh

# El directorio de trabajo actual (donde se ejecuta el comando)
SCRIPT_DIR="$(pwd)"
CONFIG_FILE="$SCRIPT_DIR/magicserve.json"

# El directorio donde reside el script (resolviendo symlinks para instalación global via npm)
_SCRIPT_SOURCE="${BASH_SOURCE[0]}"
while [ -L "$_SCRIPT_SOURCE" ]; do
    _SCRIPT_DIR="$(cd "$(dirname "$_SCRIPT_SOURCE")" && pwd)"
    _SCRIPT_SOURCE="$(readlink "$_SCRIPT_SOURCE")"
    # Si readlink devuelve una ruta relativa, resolverla desde el dir del symlink
    [[ "$_SCRIPT_SOURCE" != /* ]] && _SCRIPT_SOURCE="$_SCRIPT_DIR/$_SCRIPT_SOURCE"
done
REAL_SCRIPT_DIR="$(cd "$(dirname "$_SCRIPT_SOURCE")" && pwd)"
VERSION=$(jq -r '.version' "$REAL_SCRIPT_DIR/package.json" 2>/dev/null || echo "1.1.0")

MAGICSERVE_DIR="$SCRIPT_DIR/.magicserve"
LOGS_DIR="$MAGICSERVE_DIR/logs"
PIDS_DIR="$MAGICSERVE_DIR/pids"

# Asegurar que los directorios internos existen
mkdir -p "$LOGS_DIR" "$PIDS_DIR"

echo "🪄 Magicserve v$VERSION"
echo ""

if [ "$1" != "stopall" ] && [ "$1" != "init" ] && [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Error: magicserve.json no encontrado en el directorio actual."
    echo "💡 Truco: Ejecuta 'magicserve init' para generar un template base."
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "❌ jq no instalado → brew install jq"
    exit 1
fi

ACTION=$1

usage() {
    echo "Uso:"
    echo "  magicserve [start|stop|stopall|status|init]"
    echo ""
    echo "  init     - Crea un archivo magicserve.json de plantilla en la carpeta actual"
    echo "  start    - Configura proxy Nginx (HTTPS) y túneles para los dominios del magicserve.json"
    echo "  stop     - Detiene los proxys y túneles del magicserve.json (no toca tus servidores)"
    echo "  stopall  - Borra TODOS los proxys, túneles, certificados y entradas de hosts (sin depender de magicserve.json)"
    echo "  status   - Muestra si hay un servidor escuchando en cada puerto y el estado de los túneles"
    exit 1
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

    client_max_body_size 100M;

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

start_tunnel() {
    local DOMAIN=$1
    local PORT=$2
    local TUNNEL_SUBDOMAIN=$3

    echo "🚇 Iniciando túnel para $DOMAIN en puerto $PORT..."
    local TUNNEL_PID_FILE="$PIDS_DIR/${DOMAIN}_tunnel.pid"
    local TUNNEL_URL_FILE="$PIDS_DIR/${DOMAIN}_tunnel.url"

    # Si pasaron false o null, no hacer nada
    if [ "$TUNNEL_SUBDOMAIN" == "false" ] || [ "$TUNNEL_SUBDOMAIN" == "null" ] || [ -z "$TUNNEL_SUBDOMAIN" ]; then
        return
    fi

    local TUNNEL_LOG="$LOGS_DIR/${DOMAIN}_tunnel.log"

    if [ "$TUNNEL_SUBDOMAIN" == "true" ]; then
        nohup npx localtunnel --port $PORT > "$TUNNEL_LOG" 2>&1 &
        local PID=$!
        echo $PID > "$TUNNEL_PID_FILE"
        echo "✅ Túnel corriendo (PID: $PID)"
        # Esperar a que localtunnel imprima la URL dinámica
        echo "⏳ Esperando URL del túnel..."
        sleep 4
        local URL=$(grep -o 'https://[^ ]*' "$TUNNEL_LOG" 2>/dev/null | head -1)
        if [ -n "$URL" ]; then
            echo "$URL" > "$TUNNEL_URL_FILE"
            echo "🌐 URL pública del túnel: $URL"
        else
            echo "⚠️  No se pudo obtener la URL del túnel aún. Revisa: $TUNNEL_LOG"
        fi
    else
        nohup npx localtunnel --port $PORT --subdomain "$TUNNEL_SUBDOMAIN" > "$TUNNEL_LOG" 2>&1 &
        local PID=$!
        echo $PID > "$TUNNEL_PID_FILE"
        local URL="https://${TUNNEL_SUBDOMAIN}.loca.lt"
        echo "$URL" > "$TUNNEL_URL_FILE"
        echo "✅ Túnel corriendo (PID: $PID)"
        echo "🌐 URL pública del túnel: $URL"
    fi
}

start_all() {
    echo "🌟 Configurando proxys y túneles desde magicserve.json..."
    echo "💡 Recuerda: tú debes levantar tus servidores (node/php/python/etc) en los puertos indicados."
    echo ""

    local LENGTH=$(jq '. | length' "$CONFIG_FILE")
    for (( i=0; i<$LENGTH; i++ )); do
        local DOMAIN=$(jq -r ".[$i].domain" "$CONFIG_FILE")
        local PORT=$(jq -r ".[$i].port" "$CONFIG_FILE")
        local TUNNEL=$(jq -r ".[$i].tunnel // empty" "$CONFIG_FILE")

        start_proxy "$DOMAIN" "$PORT"

        if [ -n "$TUNNEL" ]; then
            start_tunnel "$DOMAIN" "$PORT" "$TUNNEL"
        fi
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
    echo "🛑 Deteniendo proxys y túneles..."

    local HOSTS_FILE="/etc/hosts"
    local NGINX_SERVER_DIR="/opt/homebrew/etc/nginx/servers"

    local LENGTH=$(jq '. | length' "$CONFIG_FILE")
    for (( i=0; i<$LENGTH; i++ )); do
        local DOMAIN=$(jq -r ".[$i].domain" "$CONFIG_FILE")

        local TUNNEL_PID_FILE="$PIDS_DIR/${DOMAIN}_tunnel.pid"
        local TUNNEL_URL_FILE="$PIDS_DIR/${DOMAIN}_tunnel.url"
        if [ -f "$TUNNEL_PID_FILE" ]; then
            local TPID=$(cat "$TUNNEL_PID_FILE")
            if ps -p $TPID > /dev/null; then
                kill $TPID
                echo "🛑 Túnel para $DOMAIN detenido (PID: $TPID)."
            else
                echo "⚠️ Proceso de túnel para $DOMAIN no encontrado."
            fi
            rm "$TUNNEL_PID_FILE"
            rm -f "$TUNNEL_URL_FILE"
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

    echo "✅ Proxys y túneles detenidos. (Tus servidores siguen corriendo, deténlos tú mismo)."
}

status() {
    echo "📊 Estado de los servicios:"
    local LENGTH=$(jq '. | length' "$CONFIG_FILE")
    for (( i=0; i<$LENGTH; i++ )); do
        local DOMAIN=$(jq -r ".[$i].domain" "$CONFIG_FILE")
        local PORT=$(jq -r ".[$i].port" "$CONFIG_FILE")

        # No gestionamos el proceso del servidor: comprobamos si algo escucha en el puerto
        local LISTENER=$(lsof -nP -iTCP:$PORT -sTCP:LISTEN -t 2>/dev/null | head -1)
        if [ -n "$LISTENER" ]; then
            echo "🟢 $DOMAIN → localhost:$PORT (servidor escuchando, PID: $LISTENER)"
        else
            echo "⚪️ $DOMAIN → localhost:$PORT (nada escuchando — levanta tu servidor)"
        fi

        local TUNNEL_PID_FILE="$PIDS_DIR/${DOMAIN}_tunnel.pid"
        local TUNNEL_URL_FILE="$PIDS_DIR/${DOMAIN}_tunnel.url"
        if [ -f "$TUNNEL_PID_FILE" ]; then
            local TPID=$(cat "$TUNNEL_PID_FILE")
            if ps -p $TPID > /dev/null; then
                local TURL=""
                [ -f "$TUNNEL_URL_FILE" ] && TURL=$(cat "$TUNNEL_URL_FILE")
                if [ -n "$TURL" ]; then
                    echo "  ↳ 🚇 Túnel activo (PID: $TPID) → 🌐 $TURL"
                else
                    echo "  ↳ 🚇 Túnel activo (PID: $TPID)"
                fi
            else
                 echo "  ↳ 🔴 Túnel: Archivo PID existe pero no está corriendo"
            fi
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
    if [ -d "$PIDS_DIR" ]; then
        for PID_FILE in "$PIDS_DIR"/*.pid; do
            [ -f "$PID_FILE" ] || continue
            FOUND_SOMETHING=true
            local PID=$(cat "$PID_FILE")
            local BASENAME=$(basename "$PID_FILE")
            local DOMAIN_NAME=${BASENAME%.pid}

        if ps -p $PID > /dev/null 2>&1; then
            kill $PID 2>/dev/null
            echo "  🛑 Proceso detenido: $DOMAIN_NAME (PID: $PID)"
        else
            echo "  ⚠️  Proceso ya no existía: $DOMAIN_NAME (PID: $PID)"
        fi
        done
    fi
    if [ "$FOUND_SOMETHING" = false ]; then
        echo "  ✅ No se encontraron archivos .pid"
    fi

    # NOTA: Magicserve ya no lanza servidores (node/php/python), así que tampoco
    # los mata aquí. Tus servidores los gestionas tú. Solo limpiamos lo que
    # Magicserve crea: túneles, configs de nginx, /etc/hosts, certificados y logs.

    # ─── 2. Matar procesos de localtunnel ───
    echo ""
    echo "🔍 Buscando procesos de localtunnel..."
    local LT_PIDS=$(pgrep -f "localtunnel" 2>/dev/null)
    if [ -n "$LT_PIDS" ]; then
        echo "$LT_PIDS" | while read PID; do
            kill $PID 2>/dev/null
            echo "  🛑 localtunnel detenido (PID: $PID)"
        done
    else
        echo "  ✅ No se encontraron procesos de localtunnel"
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

init_config() {
    if [ -f "$CONFIG_FILE" ]; then
        echo "⚠️  El archivo magicserve.json ya existe en este directorio."
        exit 1
    fi
    cat <<EOF > "$CONFIG_FILE"
[
    {
        "domain": "tu-proyecto.test",
        "port": 3000
    },
    {
        "domain": "api.tu-proyecto.test",
        "port": 3001,
        "tunnel": "mi-super-api-dev"
    }
]
EOF
    echo "✅ Archivo magicserve.json base generado exitosamente."
}

case "$ACTION" in
    init)
        init_config
        ;;
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
