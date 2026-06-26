# Magicserve 🪄

*[Leer en Español](README.es.md)*

Magicserve is a CLI tool for managing local web development environments. It automatically sets up a Reverse Proxy (Nginx) with HTTPS for multiple local services at once, generates SSL certificates via `mkcert`, and assigns each a dynamic local domain (e.g. `your-project.test`) — plus optional public `localtunnel` URLs.

> **You run your own servers.** Magicserve does **not** start or stop your apps. Launch whatever you want (Node, PHP, Python, Go, …) on the ports listed in `magicserve.json`, and Magicserve wires the HTTPS domain, certificate, and tunnel to that port.

## Requirements

Before using `magicserve`, you must have the following installed on your development machine:
- [Node.js and npm](https://nodejs.org/)
- [jq](https://jqlang.github.io/jq/) (`brew install jq`)
- [mkcert](https://github.com/FiloSottile/mkcert) (`brew install mkcert`)
- Nginx (`brew install nginx`)
- PHP (if your project requires a PHP backend service)

## Global Installation

If you have the requirements installed, you can globally install the utility from npm:

```bash
npm install -g magicserve
```

## Updating

If you already have `magicserve` installed and want to update to the latest version, simply run:

```bash
npm update -g magicserve
```

Your `magicserve.json` files in your projects **will not be affected**.

> 💡 You can verify the installed version by running any `magicserve` command — it will be displayed at the top.

## How to Use

Once installed globally, navigate to any folder on your computer that will serve as a "central hub" or "workspace" for your projects, and run:

```bash
magicserve init
```

This command will automatically create a base **`magicserve.json`** file in the current directory. 

### Configuration File: `magicserve.json`

Your central directory maps domains to the local ports of the apps you run yourself. Its structure is this simple:

```json
[
    {
        "domain": "your-project.test",
        "port": 3000
    },
    {
        "domain": "api.your-project.test",
        "port": 3001,
        "tunnel": "my-cool-api-dev"
    }
]
```

**Properties:**
- **`domain`**: The local development domain that will be automatically mapped (e.g. `*.test`).
- **`port`**: The local port where **your** server is listening. Magicserve proxies the domain to `localhost:<port>`; you are responsible for starting that server.
- **`tunnel`**: *(Optional)* Subdomain to securely expose your port to the public internet via `localtunnel` (Great for testing third-party Webhooks like Mercado Libre or local mobile testing). Use `true` for a random subdomain.

Once configured to your liking, start your own servers on those ports, then use the control commands below.

## Available Commands

## Architecture: How it works under the hood

Magicserve instantly orchestrates multiple local tools so you don't have to manage them manually.

```mermaid
flowchart TD
    Dev([👨‍💻 Developer])
    World([🌐 External Webhooks / Web])
    
    subgraph Your Local Machine
        Nginx(Nginx Reverse Proxy with HTTPS)
        LT(LocalTunnel Reverse Tunnel)
        Node((Your Server\ne.g. 3000))
        PHP((Your Server\ne.g. 3001))
    end

    Dev -- "https://your-project.test" --> Nginx
    World -- "https://my-api.loca.lt" --> LT
    
    Nginx -- "localhost:3000" --> Node
    Nginx -- "localhost:3001" --> PHP
    LT -- "Tunnel" --> PHP
```

> Magicserve manages the dashed parts (Nginx proxy, SSL, hosts, tunnel). The servers behind the ports are started and stopped by you.

Within the directory where your `magicserve.json` is located, you have the following magic commands available:

- **`magicserve start`**: For every domain, generates an SSL certificate if needed, adds the `/etc/hosts` entry, writes the Nginx HTTPS proxy to `localhost:<port>`, and opens any configured tunnels. (Start your own servers first or afterward — Magicserve does not launch them.)
- **`magicserve stop`**: Removes the Nginx proxies and `/etc/hosts` entries and closes the tunnels for the domains in your `magicserve.json`. Your servers keep running.
- **`magicserve status`**: Shows whether a server is currently listening on each domain's port, plus the status and public URL of any tunnels.
- **`magicserve stopall`**: Emergency command. Destroys ALL Nginx proxy configs, tunnels, SSL certificates and custom `localhost` entries system-wide, restoring your machine's clean state. (It no longer kills your app servers — those are yours to manage.)

---

### Features in v2.0.0 🔌 (Breaking)

- **You run your own servers.** Magicserve no longer launches `node`/`php` processes — it only sets up the Nginx HTTPS proxy, SSL certificate, `/etc/hosts` entry and optional tunnel pointing at the port you bring up yourself (works with **any** stack: Node, PHP, Python, Go, …).
- **Simpler config.** `magicserve.json` now takes only `domain` + `port` (+ optional `tunnel`). The `path` and `type` properties have been removed.
- **`stop` is non-destructive to your apps.** It tears down the proxy and tunnels only; your servers keep running.
- **`status` probes the port.** It now reports whether something is listening on each port (via `lsof`) instead of tracking a server PID.
- **`stopall` no longer kills app servers** (those are yours to manage); it still purges all proxies, tunnels, certificates and custom `hosts` entries.

> **Migrating from v1.x:** remove `path` and `type` from each entry in your `magicserve.json`, and start your servers yourself before/after running `magicserve start`.

### Features in v1.2.0 🚇

- **Integrated Localtunnel**: Permanently and automatically expose any of your API ports to the internet via the new `tunnel` property in config JSON to seamlessly receive third-party **Webhooks** (Mercado Libre, Stripe, etc).

### Features in v1.1.0 🚀

- **Version Display**: Now you can see the Magicserve version directly in the terminal.
- **Large Body Support**: Nginx and PHP are automatically configured to support up to **100MB** payloads (JSON and file uploads), fixing the "413 Request Entity Too Large" error.
- **Automatic SSL**: Native support for HTTPS via `mkcert`.
