# Service Users

This repository is designed to be started from a root-owned checkout.

Root is still the entrypoint for setup scripts because the modules need to install packages, write system files, configure Caddy, manage UFW, and start system services. Some service operations can be delegated to a dedicated Linux user after the system-level work is done.

## Default Behavior

If a module's system user variable is empty, the module keeps the old behavior and runs its service operations as root.

Example:

```env
UMAMI_SYSTEM_USER=
UMAMI_SYSTEM_PASSWORD=
UMAMI_SYSTEM_SSH_PUB=""
```

This is simple and matches the original Docker module behavior.

## Optional Docker Service User

Docker-based modules can run Docker Compose operations as a dedicated service user:

* `umami/`
* `uptime-kuma/`
* `netdata/`
* `supabase/`
* `remnawave-panel/`
* `remnawave-node/`

Example:

```env
UMAMI_SYSTEM_USER=umamiadmin
UMAMI_SYSTEM_PASSWORD=changeMeSystemPassword
UMAMI_SYSTEM_SSH_PUB=""
```

When `*_SYSTEM_USER` is set, setup does this:

* creates the Linux user if it does not exist
* reuses the Linux user if it already exists
* updates the user password only when `*_SYSTEM_PASSWORD` is not empty
* adds `*_SYSTEM_SSH_PUB` to `authorized_keys` when it is not empty
* adds the user to the `docker` group
* gives the service install directory to that user
* runs Docker Compose operations as that user
* checks that the user can access Docker before starting the service

The check script reports:

* whether the service user exists
* whether the user is in the `docker` group
* whether the install directory is owned by the user
* whether the user can access Docker

Remnawave uses the same Docker service-user pattern:

```env
REMNAWAVE_PANEL_SYSTEM_USER=remnawaveadmin
REMNAWAVE_PANEL_SYSTEM_PASSWORD=changeMeSystemPassword
REMNAWAVE_PANEL_SYSTEM_SSH_PUB=""
```

```env
REMNAWAVE_NODE_SYSTEM_USER=remnanodeadmin
REMNAWAVE_NODE_SYSTEM_PASSWORD=changeMeSystemPassword
REMNAWAVE_NODE_SYSTEM_SSH_PUB=""
```

## Existing Users

If the user already exists, setup keeps using it.

If `*_SYSTEM_PASSWORD` is set, setup updates the password with `chpasswd`. If it is empty, setup leaves the existing password unchanged.

The scripts do not try to verify an existing password. Linux password hashes are not safely reversible, and checking passwords from automation usually creates more security problems than it solves.

To verify practical access, the setup and check scripts test Docker access as the service user.

## Docker Group Warning

Membership in the `docker` group is a strong privilege.

A user that can control Docker can usually gain root-equivalent control of the host by mounting host paths or starting privileged containers. Treat Docker service users like operational admin users, not like low-privilege application users.

This is why the modules do not add broad passwordless sudo for Docker service users.

## Ghost

The `ghost/` module requires a system user because Ghost CLI and the Ghost installation directory are designed to run outside root.

Ghost uses:

```env
GHOST_SYSTEM_USER=ghostadmin
GHOST_SYSTEM_PASSWORD=change_me_system_user_password
GHOST_SYSTEM_SSH_PUB=""
```

Unlike the Docker modules, Ghost grants passwordless sudo to that user because Ghost CLI needs to configure and restart systemd services during installation.

## Caddy And Ubuntu

The `ubuntu/` module manages base operating system access and is not part of this service-user pattern.

The `caddy/` module stays root-managed because it owns the system reverse proxy, writes `/etc/caddy/Caddyfile`, manages the Caddy service, and opens HTTP/HTTPS firewall rules.

Service modules can still add managed Caddy blocks from their root-started setup scripts.
