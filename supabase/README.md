# Supabase Module

Installs one self-hosted Supabase project with the official Docker Compose files. This module uses only `supabase/.env`.

The script copies Supabase's `docker/` project into `/opt/supabase`, generates Supabase secrets with the official helper scripts, starts the stack with Docker Compose, and adds a managed Caddy reverse proxy block.

## Requirements

Before you begin, make sure you have:

* a server running **Ubuntu 24.04**
* root access to the server
* Caddy installed on the server if `SUPABASE_CONFIGURE_CADDY=true`
* a domain name already pointed to the server
* the ability to open `80/tcp` and `443/tcp` from the internet
* at least **4 GB RAM**, with **8 GB+ RAM** recommended

Docker is installed automatically by this module when it is missing.

## Setup

Run the Caddy module first if this server does not have Caddy yet:

```bash
cd ~/server-scripts/caddy
bash setup-caddy.sh
```

Then prepare Supabase:

```bash
cd ~/server-scripts/supabase
cp env.example .env
nano .env
bash setup-supabase.sh
```

Change these values before running setup:

```env
SUPABASE_URL=https://supabase.example.com
SUPABASE_SITE_URL=https://app.example.com
SUPABASE_DASHBOARD_PASSWORD=changeMeDashboardPassword
SUPABASE_POSTGRES_PASSWORD=changeMePostgresPassword
SUPABASE_POOLER_TENANT_ID=default
```

Use only letters and digits in `SUPABASE_DASHBOARD_PASSWORD` and `SUPABASE_POSTGRES_PASSWORD`.
Do not leave unquoted spaces in `supabase/.env`, because the setup script loads it as a shell file.

The script installs Docker Engine, Docker Compose plugin, copies the official Supabase Docker project to `/opt/supabase`, generates API keys and secrets, starts Supabase, and adds a managed Caddy reverse proxy block.

Supabase Kong listens locally on `SUPABASE_BIND_IP:SUPABASE_KONG_HTTP_PORT`; Caddy serves the public `SUPABASE_URL`.

## Service User

By default, Supabase Docker Compose operations run as root. To run them as a dedicated Linux user, set:

```env
SUPABASE_SYSTEM_USER=supabaseadmin
SUPABASE_SYSTEM_PASSWORD=changeMeSystemPassword
SUPABASE_SYSTEM_SSH_PUB=""
```

When `SUPABASE_SYSTEM_USER` is set, setup creates or reuses that user, adds it to the `docker` group, gives it `/opt/supabase`, and runs Supabase Docker operations as that user.

Details: [../wiki/service-users.md](../wiki/service-users.md)

## Caddy Domain Conflicts

If `SUPABASE_URL` already exists in `/etc/caddy/Caddyfile`, the setup script checks the existing block.

* If it already points to `SUPABASE_BIND_IP:SUPABASE_KONG_HTTP_PORT`, the script keeps it.
* If it points somewhere else, the script asks whether to replace it.
* If it was previously created by this module, the script updates the managed block.

Set `SUPABASE_CADDY_OVERWRITE_DOMAIN=true` to replace an occupied domain without asking.
Set `SUPABASE_CADDY_OVERWRITE_DOMAIN=false` to always stop instead.

Set `SUPABASE_CONFIGURE_CADDY=false` to install Supabase without changing Caddy.

## Check

```bash
cd ~/server-scripts/supabase
bash check-setup.sh
```

The check script only reports status. It does not change the server.

It verifies Docker, Docker Compose, Supabase project files, containers, local Kong API access, Supavisor ports, Caddy config, and UFW HTTP/HTTPS rules.

## Useful Commands

View service status:

```bash
cd /opt/supabase
sh run.sh status
```

View logs:

```bash
cd /opt/supabase
sh run.sh logs
```

Show generated credentials:

```bash
cd /opt/supabase
sh run.sh secrets
```

Restart Supabase:

```bash
cd /opt/supabase
sh run.sh restart
```

Stop Supabase:

```bash
cd /opt/supabase
sh run.sh stop
```

## Open Ports

This module does not open public ports directly. Public HTTP/HTTPS ports are handled by the Caddy module:

* `80/tcp`
* `443/tcp`

By default, Supabase Kong and Supavisor ports are bound to `127.0.0.1`.
