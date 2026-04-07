# Magicserve 🪄

Magicserve es una herramienta CLI para gestionar entornos de desarrollo web locales. Su objetivo es iniciar, detener y manejar el estado de múltiples servidores locales (`node` y `php`) al mismo tiempo, y automáticamente levantar un Reverse Proxy (Nginx) y generar certificados SSL vía `mkcert` para asignarle un dominio dinámico (ej. `tu-proyecto.test`).

## Requisitos

Antes de utilizar `magicserve`, es necesario tener instalado en la computadora de desarrollo:
- [Node.js y npm](https://nodejs.org/)
- [jq](https://jqlang.github.io/jq/) (`brew install jq`)
- [mkcert](https://github.com/FiloSottile/mkcert) (`brew install mkcert`)
- Nginx (`brew install nginx`)
- PHP (si tu proyecto requiere servicios backend en php)

## Instalación global

Si tienes los requisitos instalados, puedes instalar la utilidad de manera global usando npm:

```bash
npm install -g davidlomas/magicserve
```

> **Nota:** También puedes publicarlo en npm publico y usar `npm install -g magicserve` directamente.

## ¿Cómo se usa?

Una vez instalado de manera global, dirígete a cualquier carpeta en tu computadora que servirá como "nodo central" o "espacio de trabajo" de tus proyectos, y ejecuta:

```bash
magicserve init
```

Este comando creará automáticamente un archivo base llamado **`config.json`** en el directorio actual. 

### Archivo de configuración: `config.json`

Tu directorio central gestiona y levanta las aplicaciones referenciadas dentro del **`config.json`**. Su estructura es así de sencilla:

```json
[
    {
        "path": "../tu-proyecto-frontal",
        "domain": "tu-proyecto.test",
        "type": "node",
        "port": 3000
    },
    {
        "path": "../tu-api-backend",
        "domain": "api.tu-proyecto.test",
        "type": "php",
        "port": 3001
    }
]
```

**Propiedades:**
- **`path`**: Ruta relativa o absoluta hacia el directorio del proyecto donde se deberá correr el servidor.
- **`domain`**: El dominio de desarrollo local que se enlazará automáticamente (eg. `*.test`).
- **`type`**: `node` (Correrá usando `npm run dev`) o `php` (Correrá el built-in server usando `php -S`).
- **`port`**: El puerto interno que el servicio ocupará.

Una vez configurado o modificado a tu gusto, utiliza los comandos de control.

## Comandos disponibles

Dentro del directorio donde está tu `config.json`, dispones de los siguientes comandos mágicos:

- **`magicserve start`**: Inicia todos los servicios del `config.json` en los puertos definidos, genera certificados SSL dinámicos de ser necesario y configura Nginx.
- **`magicserve stop`**: Detiene ordenadamente los servicios activos mencionados de tu `config.json`.
- **`magicserve status`**: Te muestra en terminal cuáles de tus proyectos están activos actualmente y cuál es su PID.
- **`magicserve stopall`**: Comando de emergencia. Busca y destruye TODOS los demonios, configuraciones temporales nginx relacionadas, certificados, puertos y purga todas las entradas de localhost customizadas en todo el sistema, restaurando tu computadora.
