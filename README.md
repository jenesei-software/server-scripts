# Server Scripts

This repository is a collection of isolated server setup scripts.

Each folder is a separate module. A module keeps its own scripts, its own `env.example`, and its own local `.env` file. Scripts should not depend on another module's `.env` unless that dependency is explicitly documented.

## Requirements

Before you begin, make sure you have:

* a server running **Ubuntu 24.04**
* root access to the server
* a non-root sudo user for modules that must not run as root, such as `ghost/`
* a domain name already pointed to the server if you want Caddy to issue TLS certificates
* a valid SSH public key for the `ubuntu/` module
* the ability to open the required ports from the internet

## Structure

```text
.
|-- README.md
|-- caddy/
|   |-- env.example
|   |-- README.md
|   |-- check-setup.sh
|   `-- setup-caddy.sh
|-- ghost/
|   |-- env.example
|   |-- README.md
|   |-- check-setup.sh
|   `-- setup-ghost.sh
|-- umami/
|   |-- env.example
|   |-- README.md
|   |-- check-setup.sh
|   `-- setup-umami.sh
|-- ubuntu/
|   |-- env.example
|   |-- README.md
|   |-- setup-ubuntu.sh
|   `-- check-setup.sh
`-- wiki/
    |-- caddy.md
    |-- ghost.md
    |-- umami.md
    `-- ubuntu.md
```

## Modules

### `ubuntu/`

Base Ubuntu hardening and SSH setup.

Use only `ubuntu/.env`:

```bash
cd ubuntu
cp env.example .env
nano .env
sudo bash setup-ubuntu.sh
sudo bash check-setup.sh
```

Documentation: [wiki/ubuntu.md](wiki/ubuntu.md)

### `caddy/`

Caddy installation and optional reverse proxy configuration.

Base install without a domain:

```bash
cd caddy
sudo bash setup-caddy.sh
sudo bash check-setup.sh
```

If `caddy/.env` is missing, or if `CADDY_DOMAIN` and `CADDY_UPSTREAM` are empty, the script installs and starts Caddy without replacing the current Caddyfile. Service modules can add their own domains later.

Documentation: [wiki/caddy.md](wiki/caddy.md)

### `ghost/`

One production Ghost instance behind Caddy.

Use only `ghost/.env`:

```bash
cd ghost
cp env.example .env
nano .env
bash setup-ghost.sh
bash check-setup.sh
```

Run this module as a non-root sudo user. Do not run it with `sudo bash`.

Documentation: [wiki/ghost.md](wiki/ghost.md)

### `umami/`

One Umami Analytics instance behind Caddy.

Use only `umami/.env`:

```bash
cd umami
cp env.example .env
nano .env
sudo bash setup-umami.sh
sudo bash check-setup.sh
```

Documentation: [wiki/umami.md](wiki/umami.md)

## Firewall Summary

The Ubuntu module opens:

* `PORT_SSH/tcp`

The Caddy module opens:

* `80/tcp`
* `443/tcp`

The Ghost module does not open public ports directly. Ghost listens on a local port, and Caddy proxies public HTTP/HTTPS traffic to it.

The Umami module does not open public ports directly. Umami listens on a local port, and Caddy proxies public HTTP/HTTPS traffic to it.

The Caddy module installs UFW if needed and adds the HTTP/HTTPS rules. It does not force-enable UFW by itself, because enabling a firewall from an isolated Caddy script could affect SSH access on servers that did not run the Ubuntu module first.

## Rules For New Modules

* Put each install target in its own folder.
* Put module-specific variables in that folder's `env.example`.
* Make scripts default to that folder's `.env`.
* Keep module docs in `wiki/<module>.md`.
* Avoid reading root `.env` files.
