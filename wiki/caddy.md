# Caddy Module

The `caddy/` module installs Caddy and can optionally write a reverse proxy Caddyfile. It is isolated from the Ubuntu module and reads only `caddy/.env` by default.

## Files

```text
caddy/
|-- env.example
|-- README.md
|-- check-setup.sh
`-- setup-caddy.sh
```

## What It Does

`setup-caddy.sh`:

* adds the official Caddy apt repository
* installs `caddy`
* installs UFW if it is missing
* opens `80/tcp` and `443/tcp` in UFW
* writes `/etc/caddy/Caddyfile` when `CADDY_DOMAIN` and `CADDY_UPSTREAM` are set
* validates the Caddyfile with `caddy validate`
* enables and reloads the Caddy service

`check-setup.sh` checks the Caddy command, service state, apt repository files, Caddyfile validation, UFW rules, and listening ports.

The script does not require `ubuntu/.env`.

## Requirements

Before you begin, make sure you have:

* a server running **Ubuntu 24.04**
* root access to the server
* a domain name already pointed to the server if you want Caddy to issue TLS certificates
* the ability to open `80/tcp` and `443/tcp` from the internet

## Prepare Env

Use a local Caddy env only:

```bash
cd caddy
cp env.example .env
nano .env
```

Variables:

```env
CADDY_DOMAIN=
CADDY_UPSTREAM=
CADDY_EMAIL=
CADDYFILE=
```

Example:

```env
CADDY_DOMAIN=example.com
CADDY_UPSTREAM=http://127.0.0.1:8080
CADDY_EMAIL=admin@example.com
CADDYFILE=/etc/caddy/Caddyfile
```

If `caddy/.env` is missing, the script installs and starts Caddy without replacing `/etc/caddy/Caddyfile`.
If `CADDYFILE` is empty or omitted, the default is `/etc/caddy/Caddyfile`.

## Run

From the repository root:

```bash
cd caddy
cp env.example .env
nano .env
sudo bash setup-caddy.sh
```

After setup, verify the installation:

```bash
sudo bash check-setup.sh
```

Install-only mode:

```bash
cd caddy
sudo bash setup-caddy.sh
```

In install-only mode, the script does not write a new Caddyfile.

Fresh server example:

```bash
apt update && apt install -y git
git clone https://github.com/jenesei-software/server-scripts.git
cd server-scripts/caddy
cp env.example .env
nano .env
sudo bash setup-caddy.sh
```

## Open Ports

This module opens:

* `80/tcp`
* `443/tcp`

These ports are required for normal Caddy HTTP/HTTPS traffic and automatic TLS.

The module adds UFW rules but does not force-enable UFW. If UFW is already active, the rules apply immediately. If UFW is inactive, the rules are stored for when UFW is enabled later.

## Verify

Run the module check:

```bash
cd caddy
sudo bash check-setup.sh
```

Manual Caddy checks:

```bash
systemctl status caddy
caddy validate --config /etc/caddy/Caddyfile
```

Reload Caddy:

```bash
sudo systemctl reload caddy
```

Show firewall rules:

```bash
sudo ufw status numbered
```

## Important Notes

* For automatic TLS, `CADDY_DOMAIN` must point to this server.
* Ports `80/tcp` and `443/tcp` must be reachable from the internet.
* Put the upstream application behind Caddy on a local port, for example `http://127.0.0.1:8080`.
