# Ghost Module

Installs one production Ghost instance behind Caddy. This module uses only `ghost/.env`.

Run this module as root from the same `~/server-scripts` checkout. The script creates or updates the Ghost system user from `ghost/.env`, then runs Ghost CLI as that user.

## Requirements

Before you begin, make sure you have:

* a server running **Ubuntu 24.04**
* root access to the server
* Caddy installed on the server
* a domain name already pointed to the server
* the ability to open `80/tcp` and `443/tcp` from the internet

## Before Setup

Run the Caddy module first so Caddy is installed:

```bash
cd ~/server-scripts/caddy
bash setup-caddy.sh
```

Then prepare Ghost:

```bash
cd ~/server-scripts/ghost
cp env.example .env
nano .env
```

Set the system user variables in `.env`:

```env
GHOST_SYSTEM_USER=ghostadmin
GHOST_SYSTEM_PASSWORD=change_me_system_user_password
GHOST_SYSTEM_SSH_PUB=""
```

## Setup

```bash
cd ~/server-scripts/ghost
bash setup-ghost.sh
```

The script installs Node.js, MySQL, Ghost-CLI, creates the Ghost database/user, installs Ghost, and adds a managed Caddy reverse proxy block.

Ghost listens locally on `GHOST_BIND_IP:GHOST_PORT`; Caddy serves the public `GHOST_URL`.

The script creates `/etc/sudoers.d/90-server-scripts-ghost-<GHOST_SYSTEM_USER>` so Ghost-CLI can configure and restart systemd services without an interactive password prompt.

## Caddy Domain Conflicts

If `GHOST_URL` already exists in `/etc/caddy/Caddyfile`, the setup script checks the existing block.

* If it already points to `GHOST_BIND_IP:GHOST_PORT`, the script keeps it.
* If it points somewhere else, the script asks whether to replace it.
* If it was previously created by this module, the script updates the managed block.

Set `GHOST_CADDY_OVERWRITE_DOMAIN=true` to replace an occupied domain without asking.
Set `GHOST_CADDY_OVERWRITE_DOMAIN=false` to always stop instead.

Set `GHOST_CONFIGURE_CADDY=false` to install Ghost without changing Caddy.

## Check

```bash
cd ~/server-scripts/ghost
bash check-setup.sh
```

The check script only reports status. It does not change the server.

It verifies Node.js, Ghost-CLI, MySQL, the Ghost install directory, the Ghost listener port, Caddy config, and UFW HTTP/HTTPS rules.

## Open Ports

This module does not open public ports directly. Public HTTP/HTTPS ports are handled by the Caddy module:

* `80/tcp`
* `443/tcp`
