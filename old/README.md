# Entorno de Desarrollo Local

Esta carpeta contiene scripts para levantar fácilmente un entorno de desarrollo local con HTTPS y dominios personalizados, usando Nginx y mkcert.

## Requisitos previos

-   **mkcert**: `brew install mkcert` (y ejecutar `mkcert -install`)
-   **nginx**: `brew install nginx`
-   **php**: (si usas el servidor PHP)
-   **node**: (si usas el servidor Node)

## Instalación en un nuevo proyecto

1.  Copia toda la carpeta `local/` a la raíz de tu nuevo proyecto.
2.  Copia el archivo de configuración de ejemplo:
    ```bash
    cp local/config-sample.sh local/config.sh
    ```
3.  Edita `local/config.sh` y ajusta:
    -   `DOMAIN`: El dominio local que quieres usar (ej: `mi-proyecto.test`).
    -   `PHP_PORT` / `NODE_PORT`: Los puertos donde correrá tu app.
    -   `PHP_DOCROOT`: La carpeta pública (ej: `public` o `.`).

4.  Añade lo siguiente a tu `.gitignore` para no subir archivos temporales:
    ```gitignore
    local/logs/
    local/config.sh
    local/*.pid
    ```

## Uso

### Iniciar servidor

Desde la raíz del proyecto:

-   **Para PHP:**
    ```bash
    ./local/run.sh php
    ```
-   **Para Node:**
    ```bash
    ./local/run.sh node
    ```

Esto iniciará el servidor correspondiente y configurará Nginx para servir el dominio HTTPS especificado.

### Detener servidor

```bash
./local/run.sh stop
```

Esto detendrá los procesos de PHP/Node y eliminará la configuración temporal de Nginx.

## Estructura

-   `run.sh`: Script principal orquestador.
-   `php-server.sh`: Inicia servidor PHP (`php -S`).
-   `node-server.sh`: Inicia servidor Node (`npm run dev`).
-   `proxy.sh`: Configura Nginx y certificados SSL con `mkcert`.
-   `config.sh`: Tu configuración local (ignorado por git).
-   `config-sample.sh`: Plantilla de configuración.
