# Ubuntu Module

Base Ubuntu hardening and SSH setup. This module uses only `ubuntu/.env`.

## Requirements

Before you begin, make sure you have:

* a server running **Ubuntu 24.04**
* root access to the server
* a valid SSH public key
* the ability to open `PORT_SSH/tcp` from the internet

## Setup

```bash
cd ~/server-scripts/ubuntu
cp env.example .env
nano .env
bash setup-ubuntu.sh
```

Keep the current root SSH session open after setup and test the new SSH login in another terminal:

```bash
ssh USER_NAME@YOUR_SERVER_IP -p PORT_SSH
```

## Check

```bash
cd ~/server-scripts/ubuntu
bash check-setup.sh
```

The check script only reports status. It does not change the server.

It verifies base commands, `fail2ban`, SSH, UFW, the configured SSH port, and IPv6 state when `DISABLE_IPV6` is set.

## Open Ports

This module opens:

* `PORT_SSH/tcp`
