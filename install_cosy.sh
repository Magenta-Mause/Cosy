#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# COSY Installation Script
# ─────────────────────────────────────────────────────────────────────────────
# Usage:  ./install_cosy.sh [OPTIONS]
#
# Options:
#   --method  docker|kubernetes   Deployment method       (default: docker)
#   --path    /path/to/install    Base directory (cosy/ created inside)  (default: /opt)
#   --username <name>             Admin account username   (default: admin)
#   --port    <port>              Port for the reverse proxy (default: 80)
#   --domain  <domain>            Domain for CORS origin   (default: hostname)
#   --default                     Use defaults for all unset options (non-interactive)
#   -h, --help                    Show this help message
# ─────────────────────────────────────────────────────────────────────────────

readonly SCRIPT_VERSION="0.1.0"

# ── Color & helpers ────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
fatal()   { error "$*"; exit 1; }

# ── Constants ────────────────────────────────────────────────────────────────
COSY_TAG="/refs/heads/feature/cosy-50-installation-script" # "v0.0.1"
FRONTEND_TAG="sha-281aad6"
BACKEND_TAG="v0.0.4"
CONFIG_FILES_URL_PREFIX="https://raw.githubusercontent.com/Magenta-Mause/Cosy/${COSY_TAG}/"
HOST_UID=$(id -u) 
DOCKER_GID=$(getent group docker | cut -d: -f3)

# ── Defaults ─────────────────────────────────────────────────────────────────
DEPLOY_METHOD_DEFAULT="docker"
INSTALL_PATH_DEFAULT="/opt"
ADMIN_USERNAME_DEFAULT="admin"
PORT_DEFAULT="80"
DOMAIN_DEFAULT=$(cat /etc/hostname 2>/dev/null || echo "localhost")

# ── Parse CLI arguments ─────────────────────────────────────────────────────
usage() {
    echo -e "${BOLD}COSY Installer v${SCRIPT_VERSION}${NC}"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --method  docker|kubernetes   Deployment method        (default: docker)"
    echo "  --path    /path/to/install    Base directory (cosy/ created inside)  (default: /opt)"
    echo "  --username <name>             Admin account username   (default: admin)"
    echo "  --port    <port>              Port for the reverse proxy (default: 80)"
    echo "  --domain  <domain>            Domain for CORS origin   (default: ${DOMAIN_DEFAULT})"
    echo "  --default                     Use defaults for all unset options (non-interactive)"
    echo "  -h, --help                    Show this help message"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --method)
            DEPLOY_METHOD="$2"; shift 2 ;;
        --path)
            INSTALL_PATH="$2"; shift 2 ;;
        --username)
            ADMIN_USERNAME="$2"; shift 2 ;;
        --port)
            PORT="$2"; shift 2 ;;
        --domain)
            DOMAIN="$2"; shift 2 ;;
        --default)
            USE_DEFAULTS=true; shift ;;
        -h|--help)
            usage ;;
        *)
            fatal "Unknown option: $1\nRun '$0 --help' for usage information." ;;
    esac
done

# ── Interactive prompts (if running in a terminal) ───────────────────────────
if [[ -t 0 ]] && [[ "${USE_DEFAULTS-}" != "true" ]]; then
    echo -e "${BOLD}${CYAN}"
    echo "  ╔═══════════════════════════════════════╗"
    echo "  ║        COSY Installer v${SCRIPT_VERSION}          ║"
    echo "  ╚═══════════════════════════════════════╝"
    echo -e "${NC}"

    # ── Deployment method ────────────────────────────────────────────────────
    if [[ -z "${DEPLOY_METHOD-}" ]]; then
      echo -e "${BOLD}Select deployment method:${NC}"
      echo "  1) Docker  (recommended)"
      echo "  2) Kubernetes"
      echo ""
      read -rp "Enter choice [1]: " method_choice
      method_choice="${method_choice:-1}"
      case "$method_choice" in
        1) DEPLOY_METHOD="docker" ;;
        2) DEPLOY_METHOD="kubernetes" ;;
        *) fatal "Invalid choice '$method_choice'. Please enter 1 or 2." ;;
      esac
    fi

    # ── Installation path ────────────────────────────────────────────────────
    if [[ -z "${INSTALL_PATH-}" ]]; then
      read -rp "Installation path [${INSTALL_PATH_DEFAULT}]: " input_path
      INSTALL_PATH="${input_path:-$INSTALL_PATH_DEFAULT}"
    fi
    
    # ── Admin username ───────────────────────────────────────────────────────
    if [[ -z "${ADMIN_USERNAME-}" ]]; then
      read -rp "Admin username [${ADMIN_USERNAME_DEFAULT}]: " input_user
      ADMIN_USERNAME="${input_user:-$ADMIN_USERNAME_DEFAULT}"
    fi

    # ── Port ─────────────────────────────────────────────────────────────────
    # TODO: check if the input is a valid port number (1-65535)
    if [[ -z "${PORT-}" ]]; then
      read -rp "Port [${PORT_DEFAULT}]: " input_port
      PORT="${input_port:-$PORT_DEFAULT}"
    fi

    # ── Domain ───────────────────────────────────────────────────────────────
    if [[ -z "${DOMAIN-}" ]]; then
      read -rp "Domain [${DOMAIN_DEFAULT}]: " input_domain
      DOMAIN="${input_domain:-$DOMAIN_DEFAULT}"
    fi
fi

# ── Validate deployment method ───────────────────────────────────────────────
DEPLOY_METHOD="${DEPLOY_METHOD:-$DEPLOY_METHOD_DEFAULT}"
PORT="${PORT:-$PORT_DEFAULT}"
ADMIN_USERNAME="${ADMIN_USERNAME:-$ADMIN_USERNAME_DEFAULT}"
DOMAIN="${DOMAIN:-$DOMAIN_DEFAULT}"

case "$DEPLOY_METHOD" in
    docker) ;;
    kubernetes|k8s)
        fatal "Kubernetes deployment is not yet implemented.\n  Kubernetes support is planned for a future release.\n  Please use '--method docker' for now." ;;
    *)
        fatal "Unknown deployment method '${DEPLOY_METHOD}'.\n  Supported methods: docker\n  Kubernetes support is planned for a future release." ;;
esac

# ─────────────────────────────────────────────────────────────────────────────
#  Pre-flight checks
# ─────────────────────────────────────────────────────────────────────────────

# ── Check Docker is installed ────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
    fatal "Docker is not installed or not in PATH.\n\n  To install Docker, follow the official guide:\n    https://docs.docker.com/engine/install/\n\n  After installation, make sure your user is in the 'docker' group:\n    sudo usermod -aG docker \$USER\n  Then log out and log back in."
fi
success "Docker found: $(docker --version)"

# ── Check Docker daemon is running ──────────────────────────────────────────
if ! docker info &>/dev/null; then
    fatal "Docker daemon is not running.\n\n  Try starting it with:\n    sudo systemctl start docker\n\n  If the issue persists, check:\n    sudo systemctl status docker"
fi
success "Docker daemon is running."

# ── Check Docker Compose is available ────────────────────────────────────────
if docker compose version &>/dev/null; then
    COMPOSE_CMD="docker compose"
    success "Docker Compose (plugin) found: $(docker compose version --short 2>/dev/null || echo 'available')"
elif command -v docker-compose &>/dev/null; then
    COMPOSE_CMD="docker-compose"
    success "Docker Compose (standalone) found: $(docker-compose --version)"
else
    fatal "Docker Compose is not installed.\n\n Make sure either the `docker compose` or `docker-compose` command is available."
fi

# ── Check port availability ──────────────────────────────────────────────────
check_port() {
    local port="$1"
    local service="$2"
    if ss -tlnp 2>/dev/null | grep -q ":${port} " || \
       netstat -tlnp 2>/dev/null | grep -q ":${port} "; then
        fatal "Port ${port} (${service}) is already in use.\n\n  Either stop the service using that port or choose a different port:\n    $0 --port <port>"
    fi
}
check_port "$PORT" "nginx"
success "Port ${PORT} is available."

# ─────────────────────────────────────────────────────────────────────────────
#  Generate credentials
# ─────────────────────────────────────────────────────────────────────────────
generate_password() {
  # Generate a 30-character alphanumeric password robust to SIGPIPE.
  local pw
  pw=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 30) || true
  printf '%s' "$pw"
}

POSTGRES_USER="cosy"
POSTGRES_PASSWORD="$(generate_password)"
LOKI_USER="loki-user"
LOKI_PASSWORD="$(generate_password)"
ADMIN_PASSWORD="$(generate_password)"
COSY_INFLUXDB_USERNAME="cosy"
COSY_INFLUXDB_PASSWORD="$(generate_password)"
COSY_INFLUXDB_ADMIN_TOKEN="$(generate_password)"

# ─────────────────────────────────────────────────────────────────────────────
#  Create installation directory
# ─────────────────────────────────────────────────────────────────────────────
# Normalize the installation path so concatenations are predictable:
# - Use default if unset
# - Expand leading tilde (~) to $HOME
# - Strip any trailing slashes
INSTALL_PATH="${INSTALL_PATH:-$INSTALL_PATH_DEFAULT}"
if [[ "${INSTALL_PATH}" = ~* ]]; then
    INSTALL_PATH="${INSTALL_PATH/#\~/$HOME}"
elif [[ "$INSTALL_PATH" != /* ]]; then
    INSTALL_PATH="$PWD/$INSTALL_PATH"
fi
INSTALL_PATH="${INSTALL_PATH%/}"
INSTALL_PATH="${INSTALL_PATH}/cosy"

info "Creating installation directory: ${INSTALL_PATH}"
if ! mkdir -p "$INSTALL_PATH" 2>/dev/null; then
    fatal "Could not create directory '${INSTALL_PATH}'.\n\n  Make sure you have write permissions, or choose a different path:\n    $0 --path /some/other/path"
fi
success "Installation directory ready."

# ── htpasswd ─────────────────────────────────────────────────────────────────
# Save htpasswd under ${INSTALL_PATH}/config/htpasswd
HTPASSWD_DIR="${INSTALL_PATH}/config"
HTPASSWD_PATH="${HTPASSWD_DIR}/htpasswd"
mkdir -p "${HTPASSWD_DIR}"

# Use openssl or htpasswd to create the password hash
if command -v htpasswd &>/dev/null; then
    htpasswd -bc "${HTPASSWD_PATH}" "$LOKI_USER" "$LOKI_PASSWORD" 2>/dev/null
elif command -v openssl &>/dev/null; then
    LOKI_HASH=$(openssl passwd -apr1 "$LOKI_PASSWORD")
    echo "${LOKI_USER}:${LOKI_HASH}" > "${HTPASSWD_PATH}"
else
    # Fallback: use Python if available
    if command -v python3 &>/dev/null; then
        LOKI_HASH=$(python3 -c "
import crypt, random, string
salt = '\$apr1\$' + ''.join(random.choices(string.ascii_letters + string.digits, k=8))
print(crypt.crypt('${LOKI_PASSWORD}', salt))
")
        echo "${LOKI_USER}:${LOKI_HASH}" > "${HTPASSWD_PATH}"
    else
        fatal "Cannot generate htpasswd file.\n\n  Install one of the following:\n    - apache2-utils (provides htpasswd)\n    - openssl\n    - python3\n\n"
    fi
fi
chmod 644 "${HTPASSWD_PATH}"
success "htpasswd created at ${HTPASSWD_PATH}."

# ─────────────────────────────────────────────────────────────────────────────
#  Fetch config files
# ─────────────────────────────────────────────────────────────────────────────
info "Downloading configuration files..."

curl -L -o "${INSTALL_PATH}/config/docker-compose.yml" "${CONFIG_FILES_URL_PREFIX}/config/docker/docker-compose.yml" 2>/dev/null || \
    fatal "Failed to download docker-compose.yml from ${CONFIG_FILES_URL_PREFIX}/docker/docker-compose.yml\n\n  Check your internet connection and try again."
success "docker-compose.yml downloaded."

curl -L -o "${INSTALL_PATH}/config/loki-config.yaml" "${CONFIG_FILES_URL_PREFIX}/config/docker/loki-config.yaml" 2>/dev/null || \
    fatal "Failed to download loki-config.yaml from ${CONFIG_FILES_URL_PREFIX}/docker/loki-config.yaml\n\n  Check your internet connection and try again."
success "loki-config.yaml downloaded."

curl -L -o "${INSTALL_PATH}/config/loki-nginx.conf" "${CONFIG_FILES_URL_PREFIX}/config/docker/loki-nginx.conf" 2>/dev/null || \
    fatal "Failed to download loki-nginx.conf from ${CONFIG_FILES_URL_PREFIX}/docker/loki-nginx.conf\n\n  Check your internet connection and try again."
success "loki-nginx.conf downloaded."

curl -L -o "${INSTALL_PATH}/config/nginx.conf" "${CONFIG_FILES_URL_PREFIX}/config/docker/nginx.conf" 2>/dev/null || \
    fatal "Failed to download nginx.conf from ${CONFIG_FILES_URL_PREFIX}/config/docker/nginx.conf\n\n  Check your internet connection and try again."
success "nginx.conf downloaded."

success "Configuration files downloaded."

# ─────────────────────────────────────────────────────────────────────────────
# Create necessary directories 
# ─────────────────────────────────────────────────────────────────────────────

VOLUME_DIRECTORY="${INSTALL_PATH}/volumes"
mkdir -p "${VOLUME_DIRECTORY}"
success "Volume directory created at ${VOLUME_DIRECTORY}."

# ─────────────────────────────────────────────────────────────────────────────
#  Write .env file for docker-compose
# ─────────────────────────────────────────────────────────────────────────────
info "Creating .env file for docker-compose..."

ENV_FILE="${INSTALL_PATH}/config/.env"
cat > "${ENV_FILE}" <<EOF
# COSY Installer v${SCRIPT_VERSION}
# Generated on $(date -u +"%Y-%m-%dT%H:%MSZ")

# Deployment configuration
HOST_UID=${HOST_UID}
DOCKER_GID=${DOCKER_GID}

# Image tags
BACKEND_IMAGE_TAG=${BACKEND_TAG}
FRONTEND_IMAGE_TAG=${FRONTEND_TAG}

# COSY configuration
ADMIN_USERNAME=${ADMIN_USERNAME}
ADMIN_PASSWORD=${ADMIN_PASSWORD}
PORT=${PORT}
# only http is supported for the installation script for now
COSY_CORS_ALLOWED_ORIGINS=http://${DOMAIN}:${PORT}
VOLUME_DIRECTORY=${VOLUME_DIRECTORY}

# PostgreSQL credentials
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}

# Loki credentials
LOKI_USER=${LOKI_USER}
LOKI_PASSWORD=${LOKI_PASSWORD}

# InfluxDB credentials
COSY_INFLUXDB_USERNAME=${COSY_INFLUXDB_USERNAME}
COSY_INFLUXDB_PASSWORD=${COSY_INFLUXDB_PASSWORD}
COSY_INFLUXDB_ADMIN_TOKEN=${COSY_INFLUXDB_ADMIN_TOKEN}
COSY_INFLUXDB_ORG=cosy-org
COSY_INFLUXDB_BUCKET=cosy-bucket
EOF

chmod 600 "${ENV_FILE}"
success ".env file created at ${ENV_FILE}"

# ─────────────────────────────────────────────────────────────────────────────
#  Start COSY
# ─────────────────────────────────────────────────────────────────────────────
info "Starting COSY services..."
echo ""

cd "$INSTALL_PATH"
LOG_DIR="${INSTALL_PATH}/logs"
mkdir -p "${LOG_DIR}"
LOG_PATH="${LOG_DIR}/compose-up.log"

info "Starting containers with ${COMPOSE_CMD} (output shown below)"

# Stream output to console and save to log; preserve exit status via pipefail
if ! $COMPOSE_CMD -f "${INSTALL_PATH}/config/docker-compose.yml" --env-file "${ENV_FILE}" up -d 2>&1 | tee "${LOG_PATH}"; then
    echo ""
    fatal "Failed to start COSY services.\n\n  Log saved to: ${LOG_PATH}\n\n  Troubleshooting steps:\n    1. Check the logs:  cd ${INSTALL_PATH}/config && ${COMPOSE_CMD} logs\n    2. Ensure Docker has enough resources (RAM, disk space)\n    3. Check if the images can be pulled:  docker pull ghcr.io/magenta-mause/cosy-backend:sha-2d4bdf3\n    4. Verify your internet connection"
fi

# ── Wait for services to be healthy ─────────────────────────────────────────
info "Waiting for services to become ready..."

MAX_RETRIES=60
RETRY_INTERVAL=3
RETRIES=0

while [[ $RETRIES -lt $MAX_RETRIES ]]; do
    if curl -sf "http://127.0.0.1:${PORT}/api/actuator/health" &>/dev/null || \
       curl -sf "http://127.0.0.1:${PORT}" &>/dev/null; then
        break
    fi

    RETRIES=$((RETRIES + 1))
    if [[ $((RETRIES % 10)) -eq 0 ]]; then
        info "Still waiting... (${RETRIES}/${MAX_RETRIES})"
    fi
    sleep "$RETRY_INTERVAL"
done

if [[ $RETRIES -ge $MAX_RETRIES ]]; then
    fatal "Services did not become ready within $((MAX_RETRIES * RETRY_INTERVAL)) seconds."
fi

# ─────────────────────────────────────────────────────────────────────────────
#  Success summary
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║          COSY installation completed successfully!        ║${NC}"
echo -e "${GREEN}${BOLD}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Installation path:${NC}  ${INSTALL_PATH}"
echo -e "  ${BOLD}Deployment method:${NC}  ${DEPLOY_METHOD}"
echo ""
echo -e "  ${CYAN}${BOLD}── Login Credentials ──────────────────────────────────${NC}"
echo -e "  ${BOLD}Username:${NC}           ${ADMIN_USERNAME}"
echo -e "  ${BOLD}Password:${NC}           ${ADMIN_PASSWORD}"
echo ""
echo -e "  ${CYAN}${BOLD}── Access URL ────────────────────────────────────────${NC}"
echo -e "  ${BOLD}COSY:${NC}               ${GREEN}http://${DOMAIN}:${PORT}${NC}"
echo ""
echo -e "  ${YELLOW}⚠  Please save the password above - it will not be shown again.${NC}"
echo ""
echo -e "  ${BOLD}Useful commands:${NC}"
echo -e "    Stop COSY:    cd ${INSTALL_PATH}/config && ${COMPOSE_CMD} down"
echo -e "    View logs:    cd ${INSTALL_PATH}/config && ${COMPOSE_CMD} logs -f"
echo -e "    Restart:      cd ${INSTALL_PATH}/config && ${COMPOSE_CMD} restart"
echo ""
