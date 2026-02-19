#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# COSY Uninstallation Script
# ─────────────────────────────────────────────────────────────────────────────
# Usage:  ./uninstall_cosy.sh [OPTIONS]
#
# Options:
#   --path    /path/to/install    Base directory that contains the cosy/ folder
#                                 (default: /opt → looks for /opt/cosy)
#   -y, --yes                     Skip confirmation prompt
#   -h, --help                    Show this help message
# ─────────────────────────────────────────────────────────────────────────────

# ── Color & helpers ──────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
fatal()   { error "$*"; exit 1; }

# ── Defaults ─────────────────────────────────────────────────────────────────
INSTALL_PATH_DEFAULT="/opt"
SKIP_CONFIRM=false

# ── Parse CLI arguments ─────────────────────────────────────────────────────
usage() {
    echo -e "${BOLD}COSY Uninstaller${NC}"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --path    /path/to/install    Base directory that contains the cosy/ folder"
    echo "                                (default: /opt → looks for /opt/cosy)"
    echo "  -y, --yes                     Skip confirmation prompt"
    echo "  -h, --help                    Show this help message"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --path)
            INSTALL_PATH="$2"; shift 2 ;;
        -y|--yes)
            SKIP_CONFIRM=true; shift ;;
        -h|--help)
            usage ;;
        *)
            fatal "Unknown option: $1\nRun '$0 --help' for usage information." ;;
    esac
done

# ── Resolve installation path ────────────────────────────────────────────────
INSTALL_PATH="${INSTALL_PATH:-$INSTALL_PATH_DEFAULT}"

# Expand tilde
if [[ "${INSTALL_PATH}" = ~* ]]; then
    INSTALL_PATH="${INSTALL_PATH/#\~/$HOME}"
fi

# Resolve relative paths
if [[ "$INSTALL_PATH" != /* ]]; then
    INSTALL_PATH="$PWD/$INSTALL_PATH"
fi

INSTALL_PATH="${INSTALL_PATH%/}"
COSY_DIR="${INSTALL_PATH}/cosy"

# ── Check that a COSY installation exists ────────────────────────────────────
if [[ ! -d "${COSY_DIR}" ]]; then
    if [[ -n "${INSTALL_PATH:-}" && "${INSTALL_PATH}" != "${INSTALL_PATH_DEFAULT}" ]]; then
        fatal "No COSY installation found at ${COSY_DIR}.\n\n  Make sure the path is correct."
    else
        fatal "No COSY installation found at the default location (${COSY_DIR}).\n\n  If COSY was installed in a custom location, specify it with:\n    $0 --path /path/to/base"
    fi
fi

COMPOSE_FILE="${COSY_DIR}/config/docker-compose.yml"
ENV_FILE="${COSY_DIR}/config/.env"

if [[ ! -f "${COMPOSE_FILE}" ]]; then
    fatal "docker-compose.yml not found at ${COMPOSE_FILE}.\n  The installation appears to be incomplete or corrupted."
fi

# ── Detect docker compose command ────────────────────────────────────────────
if docker compose version &>/dev/null; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose &>/dev/null; then
    COMPOSE_CMD="docker-compose"
else
    fatal "Docker Compose is not installed.\n  Cannot stop and remove COSY containers without it."
fi

# ── Confirmation ─────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${RED}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${RED}║                COSY Uninstallation                        ║${NC}"
echo -e "${BOLD}${RED}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Installation directory:${NC}  ${COSY_DIR}"
echo ""
echo -e "  ${YELLOW}This will:${NC}"
echo -e "    • Stop and remove all COSY containers"
echo -e "    • Remove all Docker volumes (database, logs, etc.)"
echo -e "    • Remove the Docker network"
echo -e "    • Delete all files in ${COSY_DIR}"
echo ""

if [[ "${SKIP_CONFIRM}" != "true" ]]; then
    read -rp "Are you sure you want to continue? [y/N]: " confirm
    case "${confirm}" in
        [yY]|[yY][eE][sS]) ;;
        *)
            info "Uninstallation cancelled."
            exit 0
            ;;
    esac
fi

# ── Stop and remove containers, volumes, and networks ────────────────────────
info "Stopping and removing COSY containers, volumes, and networks..."

COMPOSE_ARGS=(-f "${COMPOSE_FILE}")
if [[ -f "${ENV_FILE}" ]]; then
    COMPOSE_ARGS+=(--env-file "${ENV_FILE}")
fi

if $COMPOSE_CMD "${COMPOSE_ARGS[@]}" down --volumes --remove-orphans 2>&1; then
    success "Containers, volumes, and networks removed."
else
    warn "docker compose down encountered errors (some resources may already have been removed)."
fi

# ── Remove any leftover containers by name ───────────────────────────────────
info "Checking for leftover containers..."
CONTAINER_NAMES=("cosy-backend" "cosy-nginx" "cosy-loki" "cosy-loki-nginx" "cosy-influx")

for name in "${CONTAINER_NAMES[@]}"; do
    if docker ps -a --format '{{.Names}}' | grep -q "^${name}$"; then
        info "Removing leftover container: ${name}"
        docker rm -f "${name}" 2>/dev/null || true
    fi
done
success "No leftover containers."

# ── Delete installation directory ────────────────────────────────────────────
info "Deleting installation directory: ${COSY_DIR}"

if rm -rf "${COSY_DIR}"; then
    success "Installation directory deleted."
else
    warn "Could not fully remove ${COSY_DIR}. You may need to run with sudo."
fi

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}${BOLD}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}${BOLD}║         COSY has been uninstalled successfully!   :(      ║${NC}"
echo -e "${BLUE}${BOLD}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
