# Netdata Module

Installs one Netdata instance with Docker Compose behind Caddy. This module uses only `netdata/.env`.

## Requirements

Before you begin, make sure you have:

* a server running **Ubuntu 24.04**
* root access to the server
* Caddy installed on the server if `NETDATA_CONFIGURE_CADDY=true`
* a domain name already pointed to the server
* the ability to open `80/tcp` and `443/tcp` from the internet

Docker is installed automatically by this module when it is missing.

## Setup

Run the Caddy module first if this server does not have Caddy yet:

```bash
cd ~/server-scripts/caddy
bash setup-caddy.sh
```

Then prepare Netdata:

```bash
cd ~/server-scripts/netdata
cp env.example .env
nano .env
bash setup-netdata.sh
```

Change `NETDATA_BASIC_AUTH_PASSWORD` before running the setup. The script stops if the placeholder password is still present.

The script installs Docker Engine, Docker Compose plugin, writes `/opt/netdata/docker-compose.yml`, starts Netdata, and adds a managed Caddy reverse proxy block.

Netdata listens locally on `NETDATA_BIND_IP:NETDATA_PORT`; Caddy serves the public `NETDATA_URL`.

## Service User

By default, Docker Compose operations run as root. To run them as a dedicated Linux user, set:

```env
NETDATA_SYSTEM_USER=netdataadmin
NETDATA_SYSTEM_PASSWORD=changeMeSystemPassword
NETDATA_SYSTEM_SSH_PUB=""
```

When `NETDATA_SYSTEM_USER` is set, setup creates or reuses that user, adds it to the `docker` group, gives it `/opt/netdata`, and runs Docker Compose as that user.

Details: [../wiki/service-users.md](../wiki/service-users.md)

## Caddy Basic Auth

Netdata does not have an app login in this setup, so Caddy basic auth is enabled by default:

```env
NETDATA_BASIC_AUTH_ENABLED=true
NETDATA_BASIC_AUTH_USER=admin
NETDATA_BASIC_AUTH_PASSWORD=change_me_netdata_password
```

The setup script hashes `NETDATA_BASIC_AUTH_PASSWORD` before writing it to `/etc/caddy/Caddyfile`.

## Caddy Domain Conflicts

If `NETDATA_URL` already exists in `/etc/caddy/Caddyfile`, the setup script checks the existing block.

* If it already points to `NETDATA_BIND_IP:NETDATA_PORT`, the script keeps it.
* If it points somewhere else, the script asks whether to replace it.
* If it was previously created by this module, the script updates the managed block.

Set `NETDATA_CADDY_OVERWRITE_DOMAIN=true` to replace an occupied domain without asking.
Set `NETDATA_CADDY_OVERWRITE_DOMAIN=false` to always stop instead.

Set `NETDATA_CONFIGURE_CADDY=false` to install Netdata without changing Caddy.

## Check

```bash
cd ~/server-scripts/netdata
bash check-setup.sh
```

The check script only reports status. It does not change the server.

It verifies Docker, Docker Compose, the Netdata container, local API endpoint, Caddy config, and UFW HTTP/HTTPS rules.

## Open Ports

This module does not open public ports directly. Public HTTP/HTTPS ports are handled by the Caddy module:

* `80/tcp`
* `443/tcp`
