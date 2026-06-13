# Caddy Module

Caddy installation and optional reverse proxy configuration. This module uses only `caddy/.env`.

## Requirements

Before you begin, make sure you have:

* a server running **Ubuntu 24.04**
* root access to the server
* a domain name already pointed to the server if you want Caddy to issue TLS certificates
* the ability to open `80/tcp` and `443/tcp` from the internet

## Setup

With reverse proxy configuration:

```bash
cp env.example .env
nano .env
sudo bash setup-caddy.sh
```

Install-only mode:

```bash
sudo bash setup-caddy.sh
```

If `.env` is missing, the setup script installs and starts Caddy without replacing `/etc/caddy/Caddyfile`.

Use `CADDYFILE` to change the config path:

```env
CADDYFILE=/etc/caddy/Caddyfile
```

## Check

```bash
sudo bash check-setup.sh
```

The check script only reports status. It does not change the server.

It verifies the Caddy command, service state, apt repository files, Caddyfile validation, UFW HTTP/HTTPS rules, and listening ports `80` and `443`.

## Open Ports

This module opens:

* `80/tcp`
* `443/tcp`
