# Caddy Module

Caddy installation and optional reverse proxy configuration. This module uses only `caddy/.env`.

## Requirements

Before you begin, make sure you have:

* a server running **Ubuntu 24.04**
* root access to the server
* a domain name already pointed to the server if you want Caddy to issue TLS certificates
* the ability to open `80/tcp` and `443/tcp` from the internet

## Setup

Base install without a domain:

```bash
sudo bash setup-caddy.sh
```

This installs and starts Caddy without replacing `/etc/caddy/Caddyfile`.

You can also keep a local `.env` with empty domain values:

```bash
cp env.example .env
nano .env
sudo bash setup-caddy.sh
```

When `CADDY_DOMAIN` and `CADDY_UPSTREAM` are empty, the script does not write a site block. Service modules such as `ghost/` and `umami/` can add their own domains later.

Optional reverse proxy configuration:

```env
CADDY_DOMAIN=example.com
CADDY_UPSTREAM=http://127.0.0.1:8080
CADDY_EMAIL=admin@example.com
```

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
