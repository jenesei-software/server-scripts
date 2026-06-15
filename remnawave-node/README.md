# Remnawave Node Module

Installs one Remnawave Node with Docker. This module uses only `remnawave-node/.env`.

Remnawave Node is not a normal web panel behind Caddy. It runs with `network_mode: host` and listens directly on `PORT_NODE`; Caddy is not configured by this module.

## Requirements

Before you begin, make sure you have:

* a server running **Ubuntu 24.04**
* root access to the server
* the node domain pointed to the server if `SERVER_DOMAIN` is set
* the ability to open `PORT_NODE/tcp`
* the ability to open inbound proxy ports from `PORT_ARRAY_INBOUNDS`
* the ability to open `80/tcp` and `443/tcp` if the script should issue a TLS certificate with acme.sh

Docker is installed automatically by this module when it is missing.

## Setup

```bash
cd ~/server-scripts/remnawave-node
cp env.example .env
nano .env
```

Change at least:

```env
SERVER_DOMAIN=node.example.com
DOMAIN_MAIL=admin@example.com
PORT_NODE=22222
NODE_SECRET=change_me_super_secret_key
PORT_ARRAY_INBOUNDS=30000,30001
```

Use a real secret for `NODE_SECRET`; the setup script rejects placeholder values.

Then run:

```bash
cd ~/server-scripts/remnawave-node
bash setup-remnawave-node.sh
```

If `SERVER_DOMAIN` is set, the script installs `acme.sh`, issues a certificate, stores it in `REMNAWAVE_NODE_CERT_DIR`, and mounts it into the node container. If `SERVER_DOMAIN` is empty, certificate issuance is skipped and the container starts without `SSL_CERT` and `SSL_KEY`.

## Service User

By default, Remnawave Node Docker Compose operations run as root. To run them as a dedicated Linux user, set:

```env
REMNAWAVE_NODE_SYSTEM_USER=remnanodeadmin
REMNAWAVE_NODE_SYSTEM_PASSWORD=changeMeSystemPassword
REMNAWAVE_NODE_SYSTEM_SSH_PUB=""
```

When `REMNAWAVE_NODE_SYSTEM_USER` is set, setup creates or reuses that user, adds it to the `docker` group, gives it `/opt/remnanode`, and runs Docker Compose operations as that user.

Details: [../wiki/service-users.md](../wiki/service-users.md)

## IPv6

By default:

```env
DISABLE_IPV6=true
```

The setup script writes a sysctl config that disables IPv6 on the host. Set `DISABLE_IPV6=false` only when the node should actively use IPv6. In that mode, the script enables IPv6 forwarding, router advertisements on the selected interface, and `IPV6=yes` in UFW defaults.

## Check

```bash
cd ~/server-scripts/remnawave-node
bash check-setup.sh
```

The check script only reports status. It does not change the server.

It verifies Docker, service user access, IPv6 state, UFW rules, listening ports, certificate files, the compose file, and the `remnanode` container.

## Open Ports

This module opens:

* `PORT_NODE/tcp`
* every TCP port from `PORT_ARRAY_INBOUNDS`
* `80/tcp` and `443/tcp` when `SERVER_DOMAIN` is set for certificate issuance

Caddy is not used by this module.
