# Web Audits Module

The `web-audits/` module runs website performance and quality audits with Lighthouse CI and sitespeed.io.

References:

* https://github.com/GoogleChrome/lighthouse-ci/blob/main/docs/getting-started.md
* https://googlechrome.github.io/lighthouse-ci/docs/configuration.html
* https://www.sitespeed.io/documentation/sitespeed.io/installation/
* https://www.sitespeed.io/documentation/sitespeed.io/docker/

## Files

```text
web-audits/
|-- env.example
|-- run-web-audit.sh
`-- check-setup.sh
```

## Run

Interactive mode:

```bash
cd ~/server-scripts/web-audits
bash run-web-audit.sh
```

Run it as your normal SSH user. The script asks for `sudo` only when it needs to install packages, manage Docker, or clean up Docker after a sitespeed.io run.

## Running Without Sudo

The audit itself can run without `sudo` when the server is already prepared.

For Lighthouse CI without `sudo`, the user needs:

* write access to `web-audits/` for local tools and reports
* `node` and `npm` already installed
* Google Chrome or Google Chrome Stable already installed and available in `PATH`
* `jq`, `zip`, `tar`, and `curl` already installed

The script installs `@lhci/cli` locally into `web-audits/.tools/`, so global `npm install -g` is not required.

For sitespeed.io without `sudo`, the user needs:

* Docker already installed
* Docker service already running
* access to Docker without sudo, for example membership in the `docker` group
* write access to `web-audits/reports/`

One-time Docker group setup by an admin:

```bash
sudo usermod -aG docker ubuntu
```

Then log out and log back in, or run:

```bash
newgrp docker
```

Check:

```bash
docker info
```

If `docker info` works without `sudo`, sitespeed.io can run without `sudo`.

Important: membership in the `docker` group is effectively root-level access on the host. Treat that user as an admin user.

Non-interactive mode:

```bash
cd ~/server-scripts/web-audits
bash run-web-audit.sh https://example.com all
```

With a custom env file:

```bash
bash run-web-audit.sh .env https://example.com lighthouse
```

Test types:

* `all`
* `lighthouse`
* `sitespeed`

If the URL does not include a protocol, the script prepends `https://`.

## Sparse Checkout

You can keep only this module on a server and still use `git pull` by cloning the repository with sparse checkout:

```bash
ssh root@YOUR_SERVER_IP
apt update && apt install -y git
git clone --filter=blob:none --sparse https://github.com/jenesei-software/ubuntu.git server-scripts-web-audits
cd server-scripts-web-audits
git sparse-checkout set web-audits wiki
```

Run:

```bash
cd ~/server-scripts-web-audits/web-audits
bash run-web-audit.sh https://example.com all
```

Update later:

```bash
cd ~/server-scripts-web-audits
git pull
```

This works because sparse checkout still keeps the Git repository metadata. A downloaded zip of only `web-audits/` cannot use `git pull`.

## Dependencies

The script installs missing dependencies through `sudo` when needed.

Lighthouse CI dependencies:

* Node.js
* Google Chrome stable
* `@lhci/cli`

sitespeed.io dependencies:

* Docker Engine
* Docker Compose plugin
* `sitespeedio/sitespeed.io:<tag>`

The sitespeed.io image is pinned in `web-audits/.env` because changing image tags can change browser versions and report results.

The sitespeed.io container is started as a one-shot container with `--rm`, a unique name, and labels for this module. If the script is interrupted, it stops that container. If Docker was inactive before the audit and the script started Docker only for this run, Docker is stopped again after the report is written. If Docker was already active, it is left alone so other services on the server keep running.

## Report Layout

Default:

```text
web-audits/reports/<site>/<timestamp>/
```

Inside a full run:

```text
<timestamp>/
|-- lighthouse-ci/
|   |-- lighthouserc.json
|   `-- reports/
|       |-- manifest.json
|       |-- *.report.html
|       `-- *.report.json
|-- sitespeed/
|   `-- sitespeed-result/
|-- logs/
|   |-- lighthouse-ci.log
|   `-- sitespeed.log
|-- metadata.json
`-- summary.txt
```

If `WEB_AUDIT_CREATE_ZIP=true`, the script also creates:

```text
web-audits/reports/<site>/<timestamp>.zip
```

## Env

```env
WEB_AUDIT_RESULTS_DIR=reports
WEB_AUDIT_DEFAULT_TEST=all
WEB_AUDIT_NODE_MAJOR=22
WEB_AUDIT_LHCI_VERSION=latest
WEB_AUDIT_LHCI_RUNS=3
WEB_AUDIT_LHCI_TIMEOUT=10m
WEB_AUDIT_LHCI_MAX_WAIT_FOR_LOAD=45000
WEB_AUDIT_LHCI_MAX_WAIT_FOR_FCP=30000
WEB_AUDIT_SITESPEED_IMAGE=sitespeedio/sitespeed.io:41.3.3
WEB_AUDIT_SITESPEED_BROWSER=chrome
WEB_AUDIT_SITESPEED_RUNS=3
WEB_AUDIT_SITESPEED_CONNECTIVITY=native
WEB_AUDIT_SITESPEED_TIMEOUT=30m
WEB_AUDIT_CREATE_ZIP=true
WEB_AUDIT_STOP_DOCKER_AFTER_RUN=true
```

## Timeouts

Lighthouse should not run for tens of minutes on one page. The module uses two layers of protection:

* `WEB_AUDIT_LHCI_MAX_WAIT_FOR_LOAD` and `WEB_AUDIT_LHCI_MAX_WAIT_FOR_FCP` are passed into Lighthouse settings in milliseconds.
* `WEB_AUDIT_LHCI_TIMEOUT` wraps the whole `lhci collect` command.

If a run is already stuck, press `Ctrl+C`. If the terminal does not return, inspect and stop the related processes:

```bash
ps aux | grep -E 'lhci|lighthouse|chrome' | grep -v grep
```

Then stop only the relevant process IDs:

```bash
kill PID
```

## Download To Windows

Download one archive from Windows PowerShell. Use the SSH user and exact archive path printed in `summary.txt`:

```powershell
scp SSH_USER@SERVER_IP:/path/to/server-scripts/web-audits/reports/example.com/20260623-153000.zip C:\Users\YOUR_USER\Downloads\
```

With a custom SSH port:

```powershell
scp -P PORT SSH_USER@SERVER_IP:/path/to/server-scripts/web-audits/reports/example.com/20260623-153000.zip C:\Users\YOUR_USER\Downloads\
```

Download all reports:

```powershell
scp -r SSH_USER@SERVER_IP:/path/to/server-scripts/web-audits/reports C:\Users\YOUR_USER\Downloads\web-audits-reports
```

WinSCP path:

```text
/path/to/server-scripts/web-audits/reports
```

## Check

```bash
cd ~/server-scripts/web-audits
bash check-setup.sh
```

The check script verifies installed commands, apt repository files, the configured sitespeed.io Docker image, and recent report archives.
