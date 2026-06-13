# Umami Module

Installs one Umami Analytics instance with Docker Compose and PostgreSQL. This module uses only `umami/.env`.

## Requirements

Before you begin, make sure you have:

* a server running **Ubuntu 24.04**
* root access to the server
* Caddy installed on the server if `UMAMI_CONFIGURE_CADDY=true`
* a domain name already pointed to the server
* the ability to open `80/tcp` and `443/tcp` from the internet

Docker is installed automatically by this module when it is missing.

## Setup

Run the Caddy module first if this server does not have Caddy yet:

```bash
cd ~/server-scripts/caddy
bash setup-caddy.sh
```

Then prepare Umami:

```bash
cd ~/server-scripts/umami
cp env.example .env
nano .env
bash setup-umami.sh
```

The script installs Docker Engine, Docker Compose plugin, writes `/opt/umami/docker-compose.yml`, starts Umami with PostgreSQL, and adds a managed Caddy reverse proxy block.

Umami listens locally on `UMAMI_BIND_IP:UMAMI_PORT`; Caddy serves the public `UMAMI_URL`.

Use only letters, digits, dots, underscores, dashes, and equals signs in `UMAMI_DB_PASSWORD` and `UMAMI_APP_SECRET`.

## Caddy Domain Conflicts

If `UMAMI_URL` already exists in `/etc/caddy/Caddyfile`, the setup script checks the existing block.

* If it already points to `UMAMI_BIND_IP:UMAMI_PORT`, the script keeps it.
* If it points somewhere else, the script asks whether to replace it.
* If it was previously created by this module, the script updates the managed block.

Set `UMAMI_CADDY_OVERWRITE_DOMAIN=true` to replace an occupied domain without asking.
Set `UMAMI_CADDY_OVERWRITE_DOMAIN=false` to always stop instead.

Set `UMAMI_CONFIGURE_CADDY=false` to install Umami without changing Caddy.

## Check

```bash
cd ~/server-scripts/umami
bash check-setup.sh
```

The check script only reports status. It does not change the server.

It verifies Docker, Docker Compose, containers, Umami heartbeat, Caddy config, and UFW HTTP/HTTPS rules.

## Login

Default credentials:

```text
admin / umami
```

Change the default password immediately after the first login.

## Open Ports

This module does not open public ports directly. Public HTTP/HTTPS ports are handled by the Caddy module:

* `80/tcp`
* `443/tcp`
