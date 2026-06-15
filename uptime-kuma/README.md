# Uptime Kuma Module

Installs one Uptime Kuma instance with Docker Compose behind Caddy. This module uses only `uptime-kuma/.env`.

## Requirements

Before you begin, make sure you have:

* a server running **Ubuntu 24.04**
* root access to the server
* Caddy installed on the server if `UPTIME_KUMA_CONFIGURE_CADDY=true`
* a domain name already pointed to the server
* the ability to open `80/tcp` and `443/tcp` from the internet

Docker is installed automatically by this module when it is missing.

## Setup

Run the Caddy module first if this server does not have Caddy yet:

```bash
cd ~/server-scripts/caddy
bash setup-caddy.sh
```

Then prepare Uptime Kuma:

```bash
cd ~/server-scripts/uptime-kuma
cp env.example .env
nano .env
bash setup-uptime-kuma.sh
```

The script installs Docker Engine, Docker Compose plugin, writes `/opt/uptime-kuma/docker-compose.yml`, starts Uptime Kuma, and adds a managed Caddy reverse proxy block.

Uptime Kuma listens locally on `UPTIME_KUMA_BIND_IP:UPTIME_KUMA_PORT`; Caddy serves the public `UPTIME_KUMA_URL`.

Open `UPTIME_KUMA_URL` and create the first admin account.

## Service User

By default, Docker Compose operations run as root. To run them as a dedicated Linux user, set:

```env
UPTIME_KUMA_SYSTEM_USER=uptimeadmin
UPTIME_KUMA_SYSTEM_PASSWORD=changeMeSystemPassword
UPTIME_KUMA_SYSTEM_SSH_PUB=""
```

When `UPTIME_KUMA_SYSTEM_USER` is set, setup creates or reuses that user, adds it to the `docker` group, gives it `/opt/uptime-kuma`, and runs Docker Compose as that user.

Details: [../wiki/service-users.md](../wiki/service-users.md)

## Caddy Domain Conflicts

If `UPTIME_KUMA_URL` already exists in `/etc/caddy/Caddyfile`, the setup script checks the existing block.

* If it already points to `UPTIME_KUMA_BIND_IP:UPTIME_KUMA_PORT`, the script keeps it.
* If it points somewhere else, the script asks whether to replace it.
* If it was previously created by this module, the script updates the managed block.

Set `UPTIME_KUMA_CADDY_OVERWRITE_DOMAIN=true` to replace an occupied domain without asking.
Set `UPTIME_KUMA_CADDY_OVERWRITE_DOMAIN=false` to always stop instead.

Set `UPTIME_KUMA_CONFIGURE_CADDY=false` to install Uptime Kuma without changing Caddy.

## Check

```bash
cd ~/server-scripts/uptime-kuma
bash check-setup.sh
```

The check script only reports status. It does not change the server.

It verifies Docker, Docker Compose, the Uptime Kuma container, local HTTP endpoint, Caddy config, and UFW HTTP/HTTPS rules.

## Open Ports

This module does not open public ports directly. Public HTTP/HTTPS ports are handled by the Caddy module:

* `80/tcp`
* `443/tcp`
