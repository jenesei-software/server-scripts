#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE_INPUT="${1:-}"
DOCKER_KEYRING="/etc/apt/keyrings/docker.gpg"
DOCKER_SOURCE_LIST="/etc/apt/sources.list.d/docker.list"
NODE_KEYRING="/etc/apt/keyrings/nodesource.gpg"
NODE_SOURCE_LIST="/etc/apt/sources.list.d/nodesource.list"
CHROME_KEYRING="/etc/apt/keyrings/google-chrome.gpg"
CHROME_SOURCE_LIST="/etc/apt/sources.list.d/google-chrome.list"
SUDO=()
DOCKER_CMD=()

LOG_COLOR='\033[1;36m'
LOG_RESET='\033[0m'

timestamp() { date '+%F %T'; }
log_line() {
  local level="$1"
  shift
  printf '%b[%s] %-7s%b %s\n' "$LOG_COLOR" "$(timestamp)" "$level" "$LOG_RESET" "$*"
}

ok() { log_line "OK" "$*"; }
warn() { log_line "WARN" "$*"; }
err() { log_line "ERROR" "$*"; }
info() { log_line "INFO" "$*"; }
section() { echo; log_line "SECTION" "$*"; }
fail() { log_line "ERROR" "$*" >&2; exit 1; }
is_windows_interop_path() { [[ "$1" == /mnt/c/* || "$1" == *.exe ]]; }

find_linux_command() {
  local command_name="$1"
  local command_path
  local fixed_path

  for fixed_path in "/usr/local/bin/$command_name" "/usr/bin/$command_name" "/bin/$command_name"; do
    if [[ -x "$fixed_path" ]] && ! is_windows_interop_path "$fixed_path"; then
      printf '%s\n' "$fixed_path"
      return 0
    fi
  done

  command -v "$command_name" >/dev/null 2>&1 || return 1
  command_path="$(command -v "$command_name")"
  is_windows_interop_path "$command_path" && return 1

  printf '%s\n' "$command_path"
}

load_nvm_if_available() {
  local nvm_sh

  NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  for nvm_sh in "$NVM_DIR/nvm.sh" "$HOME/.nvm/nvm.sh"; do
    [[ -s "$nvm_sh" ]] || continue
    # shellcheck disable=SC1090
    . "$nvm_sh"
    return
  done
}

init_privileges() {
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    SUDO=()
  elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
    SUDO=(sudo)
  else
    SUDO=()
  fi
}

docker_cmd() {
  if (( ${#DOCKER_CMD[@]} > 0 )); then
    "${DOCKER_CMD[@]}" "$@"
    return
  fi

  if docker info >/dev/null 2>&1; then
    DOCKER_CMD=(docker)
  elif (( ${#SUDO[@]} > 0 )) && sudo docker info >/dev/null 2>&1; then
    DOCKER_CMD=(sudo docker)
  else
    DOCKER_CMD=(docker)
  fi

  "${DOCKER_CMD[@]}" "$@"
}

find_linux_chrome() {
  local candidate
  local chrome_path

  if [[ -n "${WEB_AUDIT_CHROME_PATH:-}" ]]; then
    [[ -x "$WEB_AUDIT_CHROME_PATH" ]] || return 1
    is_windows_interop_path "$WEB_AUDIT_CHROME_PATH" && return 1
    printf '%s\n' "$WEB_AUDIT_CHROME_PATH"
    return 0
  fi

  for candidate in google-chrome-stable google-chrome chromium chromium-browser; do
    if command -v "$candidate" >/dev/null 2>&1; then
      chrome_path="$(command -v "$candidate")"
      is_windows_interop_path "$chrome_path" && continue
      printf '%s\n' "$chrome_path"
      return 0
    fi
  done

  return 1
}

resolve_env_path() {
  local candidate="$1"
  local candidate_dir
  local candidate_base

  if [[ "$candidate" = /* ]]; then
    printf '%s\n' "$candidate"
  elif [[ -f "$candidate" ]]; then
    candidate_dir="$(cd -- "$(dirname -- "$candidate")" && pwd)"
    candidate_base="$(basename -- "$candidate")"
    printf '%s/%s\n' "$candidate_dir" "$candidate_base"
  elif [[ -f "$SCRIPT_DIR/$candidate" ]]; then
    candidate_dir="$(cd -- "$(dirname -- "$SCRIPT_DIR/$candidate")" && pwd)"
    candidate_base="$(basename -- "$SCRIPT_DIR/$candidate")"
    printf '%s/%s\n' "$candidate_dir" "$candidate_base"
  else
    printf '%s/%s\n' "$SCRIPT_DIR" "$candidate"
  fi
}

absolute_module_path() {
  local value="$1"
  local value_dir
  local value_base

  if [[ "$value" = /* ]]; then
    printf '%s\n' "$value"
    return
  fi

  value_dir="$(cd -- "$SCRIPT_DIR/$(dirname -- "$value")" && pwd)"
  value_base="$(basename -- "$value")"
  printf '%s/%s\n' "$value_dir" "$value_base"
}

resolve_env_file() {
  if [[ -n "$ENV_FILE_INPUT" ]]; then
    ENV_FILE="$(resolve_env_path "$ENV_FILE_INPUT")"
    return
  fi

  if [[ -f "$SCRIPT_DIR/.env" ]]; then
    ENV_FILE="$SCRIPT_DIR/.env"
    return
  fi

  ENV_FILE=""
}

load_env() {
  resolve_env_file

  if [[ -n "$ENV_FILE" && -f "$ENV_FILE" ]]; then
    info "Loading environment from $ENV_FILE"
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
  elif [[ -n "$ENV_FILE" ]]; then
    warn "Environment file not found: $ENV_FILE"
  else
    info "Environment file is optional for this module; using defaults"
  fi

  WEB_AUDIT_RESULTS_DIR="$(absolute_module_path "${WEB_AUDIT_RESULTS_DIR:-reports}")"
  WEB_AUDIT_CHROME_PATH="${WEB_AUDIT_CHROME_PATH:-}"
  WEB_AUDIT_LHCI_CHROME_FLAGS="${WEB_AUDIT_LHCI_CHROME_FLAGS:---no-sandbox --disable-dev-shm-usage --disable-gpu --disable-setuid-sandbox}"
  WEB_AUDIT_SITESPEED_IMAGE="${WEB_AUDIT_SITESPEED_IMAGE:-sitespeedio/sitespeed.io:41.3.3}"
}

check_cmd() {
  if command -v "$1" >/dev/null 2>&1; then
    ok "Command found: $1"
  else
    err "Command not found: $1"
  fi
}

check_system() {
  section "Base system"
  check_cmd curl
  check_cmd jq
  check_cmd zip
  check_cmd tar
  check_cmd timeout
}

check_lighthouse_dependencies() {
  local chrome_path
  local lhci_path
  local node_path
  local npm_path
  local smoke_dir
  local chrome_flags=()

  section "Lighthouse CI dependencies"
  load_nvm_if_available

  if node_path="$(find_linux_command node)"; then
    ok "Linux Node.js command found: $node_path"
    info "Node.js version: $("$node_path" --version)"
  elif command -v node >/dev/null 2>&1; then
    err "Node.js resolves to a Windows/non-Linux command: $(command -v node)"
  else
    err "Command not found: node"
  fi

  if npm_path="$(find_linux_command npm)"; then
    ok "Linux npm command found: $npm_path"
    info "npm version: $("$npm_path" --version)"
  elif command -v npm >/dev/null 2>&1; then
    err "npm resolves to a Windows/non-Linux command: $(command -v npm)"
  else
    err "Command not found: npm"
  fi
  if lhci_path="$(find_linux_command lhci)"; then
    ok "Linux Lighthouse CI command found: $lhci_path"
    info "Lighthouse CI version: $("$lhci_path" --version)"
  elif command -v lhci >/dev/null 2>&1; then
    err "Lighthouse CI resolves to a Windows/non-Linux command: $(command -v lhci)"
  elif [[ -x "$SCRIPT_DIR/.tools/lhci/node_modules/.bin/lhci" ]]; then
    ok "Local Lighthouse CI command found: $SCRIPT_DIR/.tools/lhci/node_modules/.bin/lhci"
    info "Lighthouse CI version: $("$SCRIPT_DIR/.tools/lhci/node_modules/.bin/lhci" --version)"
  else
    err "Lighthouse CI CLI is not installed globally or locally"
  fi

  if [[ -n "$WEB_AUDIT_CHROME_PATH" ]] && is_windows_interop_path "$WEB_AUDIT_CHROME_PATH"; then
    err "WEB_AUDIT_CHROME_PATH points to Windows Chrome: $WEB_AUDIT_CHROME_PATH"
  elif chrome_path="$(find_linux_chrome)"; then
    ok "Linux Chrome/Chromium executable found: $chrome_path"
    info "$("$chrome_path" --version)"

    if command -v timeout >/dev/null 2>&1; then
      read -r -a chrome_flags <<< "$WEB_AUDIT_LHCI_CHROME_FLAGS"
      smoke_dir="$(mktemp -d)"
      if timeout --foreground 30s "$chrome_path" \
        --headless=new \
        "${chrome_flags[@]}" \
        --disable-background-networking \
        --disable-component-update \
        --disable-sync \
        --metrics-recording-only \
        --no-default-browser-check \
        --no-first-run \
        --user-data-dir="$smoke_dir" \
        --dump-dom about:blank > "$smoke_dir/chrome-smoke.log" 2>&1; then
        ok "Headless Chrome smoke test passed"
      elif grep -q '<html' "$smoke_dir/chrome-smoke.log"; then
        warn "Headless Chrome produced DOM but did not exit cleanly within 30s"
      else
        err "Headless Chrome smoke test failed"
      fi
      rm -rf "$smoke_dir"
    else
      warn "Skipping Chrome smoke test because timeout command is missing"
    fi
  else
    err "Linux Google Chrome/Chromium is not installed or WEB_AUDIT_CHROME_PATH is not executable"
  fi

  [[ -f "$NODE_KEYRING" ]] && ok "NodeSource keyring is present" || warn "NodeSource keyring is missing: $NODE_KEYRING"
  [[ -f "$NODE_SOURCE_LIST" ]] && ok "NodeSource apt source is present" || warn "NodeSource apt source is missing: $NODE_SOURCE_LIST"
  [[ -f "$CHROME_KEYRING" ]] && ok "Google Chrome keyring is present" || warn "Google Chrome keyring is missing: $CHROME_KEYRING"
  [[ -f "$CHROME_SOURCE_LIST" ]] && ok "Google Chrome apt source is present" || warn "Google Chrome apt source is missing: $CHROME_SOURCE_LIST"
}

check_sitespeed_dependencies() {
  section "sitespeed.io dependencies"
  check_cmd docker

  if command -v docker >/dev/null 2>&1; then
    info "Docker version: $(docker --version)"
    if docker_cmd info >/dev/null 2>&1; then
      ok "Docker daemon is reachable"
    else
      err "Docker daemon is not reachable"
    fi

    if docker_cmd image inspect "$WEB_AUDIT_SITESPEED_IMAGE" >/dev/null 2>&1; then
      ok "sitespeed.io image is present: $WEB_AUDIT_SITESPEED_IMAGE"
    else
      warn "sitespeed.io image is not pulled yet: $WEB_AUDIT_SITESPEED_IMAGE"
    fi
  fi

  [[ -f "$DOCKER_KEYRING" ]] && ok "Docker keyring is present" || warn "Docker keyring is missing: $DOCKER_KEYRING"
  [[ -f "$DOCKER_SOURCE_LIST" ]] && ok "Docker apt source is present" || warn "Docker apt source is missing: $DOCKER_SOURCE_LIST"
}

check_reports() {
  section "Reports"
  if [[ -d "$WEB_AUDIT_RESULTS_DIR" ]]; then
    ok "Reports directory exists: $WEB_AUDIT_RESULTS_DIR"
    info "Recent report archives:"
    find "$WEB_AUDIT_RESULTS_DIR" -type f -name '*.zip' -printf '%TY-%Tm-%Td %TH:%TM %p\n' 2>/dev/null | sort -r | head -n 10 || true
  else
    warn "Reports directory does not exist yet: $WEB_AUDIT_RESULTS_DIR"
  fi
}

main() {
  init_privileges
  load_env
  check_system
  check_lighthouse_dependencies
  check_sitespeed_dependencies
  check_reports
}

main "$@"
