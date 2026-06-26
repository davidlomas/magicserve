# Magicserve 🪄

> **URLs bonitas `https://tu-proyecto.test` para cualquier servidor local — en un solo comando.**

[![npm version](https://img.shields.io/npm/v/magicserve.svg?color=cb3837&logo=npm)](https://www.npmjs.com/package/magicserve)
[![npm downloads](https://img.shields.io/npm/dm/magicserve.svg?color=cb3837&logo=npm)](https://www.npmjs.com/package/magicserve)
[![license](https://img.shields.io/npm/l/magicserve.svg?color=blue)](./LICENSE)
[![platform](https://img.shields.io/badge/platform-macOS%20(Apple%20Silicon)-black?logo=apple)](#requisitos)

*[Read in English 🇬🇧](README.md)*

Magicserve convierte `localhost:3000` en un dominio real, confiable y con **HTTPS** como `https://tu-proyecto.test` — y opcionalmente una **URL pública** para webhooks — sin que toques ni una sola config de Nginx, certificado o línea de `/etc/hosts`.

Tú sigues levantando tus propios servidores (Node, PHP, Python, Go, Rust… lo que sea). Magicserve cablea la infraestructura alrededor de ellos.

```bash
npm install -g magicserve
magicserve init      # crea magicserve.json
magicserve start     # 🎉 https://tu-proyecto.test ya corre con SSL válido
```

---

## ¿Por qué Magicserve?

Configurar HTTPS local "a mano" significa pelearte con `mkcert`, escribir bloques `server` de Nginx, editar `/etc/hosts` como root y levantar un túnel por cada webhook que pruebas. Magicserve hace todo eso desde un pequeño archivo JSON:

| Sin Magicserve | Con Magicserve |
| --- | --- |
| `http://localhost:3001` 😪 | `https://api.tu-proyecto.test` 🔒 |
| Advertencias de SSL en el navegador | Certificado confiable vía `mkcert` |
| Editar Nginx + `/etc/hosts` a mano | Un solo `magicserve.json` |
| Un comando `ngrok`/`localtunnel` por servicio | `"tunnel": "mi-api"` en la config |
| Configuración distinta por stack | El mismo flujo para **cualquier** lenguaje |

- 🔒 **HTTPS local confiable** — certificados SSL reales vía `mkcert`, sin advertencias del navegador ni `--insecure`.
- 🌐 **Dominios `.test` bonitos** — `https://tu-proyecto.test` en lugar de `localhost:3000`; hasta las cookies y CORS se portan bien.
- 🚇 **Túneles públicos en una línea** — expón un puerto a internet para webhooks de Stripe / Mercado Libre / WhatsApp o pruebas en el móvil.
- 🧩 **Agnóstico al stack** — Magicserve nunca inicia tus servidores, así que funciona con Node, PHP, Python, Go, Bun, Deno… lo que corras.
- ⚡ **Multi-servicio** — haz proxy de toda tu constelación de microservicios (`app.test`, `api.test`, `admin.test`) a la vez.
- 🧹 **Limpieza en un comando** — `stop` limpia solo tu proyecto; `stopall` resetea toda la máquina.

## Requisitos

macOS en Apple Silicon, con [Homebrew](https://brew.sh). Luego instala las dependencias:

```bash
brew install jq mkcert nginx
mkcert -install   # una sola vez: confía en la autoridad certificadora local
```

| Herramienta | Para qué se necesita |
| --- | --- |
| [Node.js y npm](https://nodejs.org/) | Para instalar y ejecutar Magicserve |
| [jq](https://jqlang.github.io/jq/) | Parsea tu `magicserve.json` |
| [mkcert](https://github.com/FiloSottile/mkcert) | Genera certificados SSL locales confiables |
| [Nginx](https://nginx.org/) | El proxy inverso con HTTPS |

## Instalación

```bash
npm install -g magicserve
```

**Actualiza** a la última versión cuando quieras — tus archivos `magicserve.json` nunca se tocan:

```bash
npm update -g magicserve
```

> 💡 Cada comando imprime la versión instalada al inicio, así siempre sabes qué estás ejecutando.

## Inicio rápido

1. Ve a cualquier carpeta que quieras usar como nodo central y crea la config:

   ```bash
   magicserve init
   ```

2. Edita el **`magicserve.json`** generado para mapear dominios a los puertos que vas a levantar:

   ```json
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
   ```

3. Levanta tus propios servidores en esos puertos (ej. `npm run dev`, `php artisan serve --port=3001`, …).

4. Cablea los dominios HTTPS, certificados y túneles:

   ```bash
   magicserve start
   ```

   Ahora abre **`https://tu-proyecto.test`** en tu navegador. 🔒

> `start`, `stop` y `stopall` editan `/etc/hosts` y recargan Nginx, por lo que piden tu contraseña de `sudo`.

### Configuración: `magicserve.json`

Un array JSON que mapea dominios a puertos locales. Esa es toda la API:

| Propiedad | Obligatoria | Descripción |
| --- | --- | --- |
| `domain` | ✅ | El dominio de desarrollo local a mapear (ej. `tu-proyecto.test`). |
| `port` | ✅ | El puerto donde escucha **tu** servidor. Magicserve hace proxy del dominio a `localhost:<port>`. |
| `tunnel` | ⬜ | Expón el puerto públicamente vía `localtunnel`. Usa un string para un subdominio fijo (`https://<string>.loca.lt`) o `true` para uno aleatorio. Ideal para webhooks de terceros. |

## Comandos

Ejecútalos desde el directorio que contiene tu `magicserve.json`:

| Comando | Qué hace |
| --- | --- |
| `magicserve init` | Crea un `magicserve.json` inicial en el directorio actual. |
| `magicserve start` | Para cada dominio: genera el certificado SSL (si hace falta), agrega la entrada en `/etc/hosts`, escribe el proxy HTTPS de Nginx hacia `localhost:<port>` y abre los túneles configurados. |
| `magicserve stop` | Quita los proxys de Nginx, las entradas de `/etc/hosts` y los túneles de **este** `magicserve.json`. Tus servidores siguen corriendo. |
| `magicserve status` | Muestra si hay algo escuchando en el puerto de cada dominio, más el estado y la URL pública de cada túnel. |
| `magicserve stopall` | 🧨 Reset de emergencia: destruye **todas** las configs de proxy de Nginx, túneles, certificados SSL y entradas custom de `localhost` en todo el sistema. |

## ¿Cómo funciona bajo la manga?

Magicserve orquesta en segundos varias herramientas subyacentes para que tú solo te preocupes por tu código.

```mermaid
flowchart TD
    Dev([👨‍💻 Desarrollador])
    World([🌐 Webhooks Externos])

    subgraph Tu Computadora Local
        Nginx(Nginx Proxy Inverso SSL)
        LT(LocalTunnel Túnel Reverso)
        Node((Tu Servidor\nEj. 3000))
        PHP((Tu Servidor\nEj. 3001))
    end

    Dev -- "https://tu-proyecto.test" --> Nginx
    World -- "https://mi-api.loca.lt" --> LT

    Nginx -- "localhost:3000" --> Node
    Nginx -- "localhost:3001" --> PHP
    LT -- "Túnel" --> PHP
```

> Magicserve gestiona la infraestructura (proxy Nginx, SSL, hosts, túnel). Los servidores detrás de los puertos los inicias y detienes **tú**.

## Preguntas frecuentes

**¿Magicserve inicia mi servidor de app?**
No — y es intencional. Tú corres el stack que quieras en los puertos; Magicserve solo cablea el dominio HTTPS, el certificado y el túnel hacia ellos.

**¿Por qué dominios `.test`?**
`.test` es un TLD reservado (RFC 6761) que nunca resolverá en internet público, así que es la opción segura y sin conflictos para desarrollo local.

**¿Es un reemplazo de `ngrok`?**
Para la parte de URL pública, sí — la propiedad opcional `tunnel` te da una URL pública HTTPS vía `localtunnel`, ideal para recibir webhooks (Stripe, Mercado Libre, WhatsApp…) o probar en un teléfono.

**¿Funciona en Linux / Windows / Macs Intel?**
Aún no. Magicserve asume macOS en Apple Silicon con rutas de Homebrew. Las contribuciones para ampliar el soporte son muy bienvenidas.

**Me sale una advertencia de SSL.**
Ejecuta `mkcert -install` una vez para confiar en la autoridad certificadora local, y luego `magicserve start` de nuevo.

## Contribuir

Toda la herramienta es un único script de Bash (`run.sh`) — fácil de leer y modificar. Issues y PRs bienvenidos: [github.com/davidlomas/magicserve](https://github.com/davidlomas/magicserve).

## Novedades

### v2.0.0 🔌 (Breaking)

- **Tú levantas tus propios servidores.** Magicserve ya no inicia procesos `node`/`php` — solo configura el proxy HTTPS de Nginx, el certificado SSL, la entrada en `/etc/hosts` y el túnel opcional apuntando al puerto que tú levantas (funciona con **cualquier** stack).
- **Config más simple.** `magicserve.json` ahora solo lleva `domain` + `port` (+ `tunnel` opcional). Se eliminaron las propiedades `path` y `type`.
- **`stop` no afecta a tus apps.** Solo retira el proxy y los túneles; tus servidores siguen corriendo.
- **`status` revisa el puerto.** Reporta si hay algo escuchando en cada puerto (vía `lsof`) en lugar de rastrear el PID de un servidor.
- **`stopall` ya no mata tus servidores de apps**; sigue purgando todos los proxys, túneles, certificados y entradas custom de `hosts`.

> **Migrar desde v1.x:** elimina `path` y `type` de cada entrada de tu `magicserve.json`, y levanta tus servidores tú mismo antes/después de ejecutar `magicserve start`.

### v1.2.0 🚇

- **Localtunnel integrado**: expón cualquier puerto de tu API a internet vía la propiedad `tunnel` para recibir **webhooks** de terceros (Mercado Libre, Stripe, etc).

### v1.1.0 🚀

- **Visualización de versión** en la terminal.
- **Soporte para archivos grandes**: Nginx configurado para payloads de hasta **100MB**, solucionando el error "413 Request Entity Too Large".
- **SSL automático** vía `mkcert`.

## Licencia

[MIT](./LICENSE) © David Lomas
