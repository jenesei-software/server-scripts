# Remnawave Panel Module

Installs Remnawave Panel and the bundled subscription page behind Caddy. This module uses only `remnawave-panel/.env`.

The panel listens locally on `REMNAWAVE_PANEL_BIND_IP:REMNAWAVE_PANEL_PORT`. The bundled subscription page listens locally on `SUBSCRIPTION_PAGE_BIND_IP:SUBSCRIPTION_PAGE_PORT`. Caddy serves both public domains.

## Requirements

Before you begin, make sure you have:

* a server running **Ubuntu 24.04**
* root access to the server
* Caddy installed on the server if `REMNAWAVE_PANEL_CONFIGURE_CADDY=true`
* one domain for the panel
* one separate domain or subdomain for the bundled subscription page
* the ability to open `80/tcp` and `443/tcp` from the internet

Docker is installed automatically by this module when it is missing.

## Before Setup

Run the Caddy module first if this server does not have Caddy yet:

```bash
cd ~/server-scripts/caddy
bash setup-caddy.sh
```

Then prepare Remnawave Panel:

```bash
cd ~/server-scripts/remnawave-panel
cp env.example .env
nano .env
```

Change at least:

```env
PANEL_DOMAIN=panel.example.com
SUBSCRIPTION_PAGE_DOMAIN=sub.panel.example.com
```

Leave `REMNAWAVE_API_TOKEN` empty for the first panel setup. You will create it after the first admin login.

## Setup

```bash
cd ~/server-scripts/remnawave-panel
bash setup-remnawave-panel.sh
```

The script downloads the official Remnawave Panel compose and env sample into `/opt/remnawave`, generates secrets, starts the panel stack, and adds a managed Caddy reverse proxy block.

Open `https://PANEL_DOMAIN`, create the first super-admin account, then create an API token in Remnawave Dashboard -> Settings -> API Tokens.

Put that token into `remnawave-panel/.env`:

```env
REMNAWAVE_API_TOKEN=your_token_here
```

Then deploy the bundled subscription page:

```bash
cd ~/server-scripts/remnawave-panel
bash setup-subscription-page.sh
```

The subscription page must be served from the root of its own domain or subdomain. Do not mount it under a Caddy path like `/subscription`.

## Service User

By default, Remnawave Docker Compose operations run as root. To run them as a dedicated Linux user, set:

```env
REMNAWAVE_PANEL_SYSTEM_USER=remnawaveadmin
REMNAWAVE_PANEL_SYSTEM_PASSWORD=changeMeSystemPassword
REMNAWAVE_PANEL_SYSTEM_SSH_PUB=""
```

When `REMNAWAVE_PANEL_SYSTEM_USER` is set, setup creates or reuses that user, adds it to the `docker` group, gives it `/opt/remnawave`, and runs Remnawave Docker operations as that user.

Details: [../wiki/service-users.md](../wiki/service-users.md)

## Caddy Domain Conflicts

If `PANEL_DOMAIN` or `SUBSCRIPTION_PAGE_DOMAIN` already exists in `/etc/caddy/Caddyfile`, the setup scripts check the existing block.

* If it already points to the configured local upstream, the script keeps it.
* If it points somewhere else, the script asks whether to replace it.
* If it was previously created by this module, the script updates the managed block.

Set `REMNAWAVE_PANEL_CADDY_OVERWRITE_DOMAIN=true` to replace an occupied domain without asking.
Set `REMNAWAVE_PANEL_CADDY_OVERWRITE_DOMAIN=false` to always stop instead.

Set `REMNAWAVE_PANEL_CONFIGURE_CADDY=false` to install Remnawave without changing Caddy.

## Check

```bash
cd ~/server-scripts/remnawave-panel
bash check-setup.sh
```

The check script only reports status. It does not change the server.

It verifies Docker, Remnawave files, containers, Docker network, local health endpoints, Caddy config, and UFW HTTP/HTTPS rules.

## Open Ports

This module does not open public ports directly. Public HTTP/HTTPS ports are handled by the Caddy module:

* `80/tcp`
* `443/tcp`

By default, panel, metrics, and subscription page ports are bound to `127.0.0.1`.
