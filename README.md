# Magicserve 🪄

*[Leer en Español](README.es.md)*

Magicserve is a CLI tool for managing local web development environments. Its goal is to start, stop, and manage the state of multiple local servers (`node` and `php`) simultaneously, automatically set up a Reverse Proxy (Nginx), and generate SSL certificates via `mkcert` to assign them a dynamic local domain (e.g. `your-project.test`).

## Requirements

Before using `magicserve`, you must have the following installed on your development machine:
- [Node.js and npm](https://nodejs.org/)
- [jq](https://jqlang.github.io/jq/) (`brew install jq`)
- [mkcert](https://github.com/FiloSottile/mkcert) (`brew install mkcert`)
- Nginx (`brew install nginx`)
- PHP (if your project requires a PHP backend service)

## Global Installation

If you have the requirements installed, you can globally install the utility using npm directly from GitHub:

```bash
npm install -g davidlomas/magicserve
```

> **Note:** You can also publish it to the public npm registry and use `npm install -g magicserve`.

## How to Use

Once installed globally, navigate to any folder on your computer that will serve as a "central hub" or "workspace" for your projects, and run:

```bash
magicserve init
```

This command will automatically create a base **`magicserve.json`** file in the current directory. 

### Configuration File: `magicserve.json`

Your central directory manages and starts the applications referenced within the **`magicserve.json`**. Its structure is this simple:

```json
[
    {
        "path": "../your-frontend-project",
        "domain": "your-project.test",
        "type": "node",
        "port": 3000
    },
    {
        "path": "../your-backend-api",
        "domain": "api.your-project.test",
        "type": "php",
        "port": 3001
    }
]
```

**Properties:**
- **`path`**: Relative or absolute path to the project's directory where the server should run.
- **`domain`**: The local development domain that will be automatically mapped (e.g. `*.test`).
- **`type`**: `node` (Runs using `npm run dev`) or `php` (Runs the PHP built-in server using `php -S`).
- **`port`**: The internal port the service will use.

Once configured or modified to your liking, you can use the control commands.

## Available Commands

Within the directory where your `magicserve.json` is located, you have the following magic commands available:

- **`magicserve start`**: Starts all services declared in `magicserve.json` on the defined ports, generates dynamic SSL certificates if necessary, and configures Nginx.
- **`magicserve stop`**: Orderly stops the active services mentioned in your `magicserve.json`.
- **`magicserve status`**: Shows a terminal output of which projects are currently active and their PIDs.
- **`magicserve stopall`**: Emergency command. Finds and destroys ALL active daemons, related Nginx configurations, certificates, processes, and purges all custom localhost entries system-wide, restoring your computer's clean state.
