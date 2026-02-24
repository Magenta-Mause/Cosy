#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# COSY Installation Script
# ─────────────────────────────────────────────────────────────────────────────
# Usage:  ./install_cosy.sh <command> [OPTIONS]
#
# Commands:
#   docker                        Deploy using Docker Compose
#   kubernetes (k8s)              Deploy to a Kubernetes cluster
#
# Run './install_cosy.sh <command> --help' for command-specific options.
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
COSY_TAG="v0.0.1"
FRONTEND_TAG="sha-281aad6"
BACKEND_TAG="sha-ed7c08f"
CONFIG_FILES_URL_PREFIX="https://raw.githubusercontent.com/Magenta-Mause/Cosy/${COSY_TAG}/"

K8S_NAMESPACE="cosy"
INFLUXDB_ORG="cosy-org"
INFLUXDB_BUCKET="cosy-bucket"

# ── Defaults ─────────────────────────────────────────────────────────────────
INSTALL_PATH_DEFAULT="/opt"
ADMIN_USERNAME_DEFAULT="admin"
PORT_DEFAULT="80"
DOMAIN_DEFAULT=$(cat /etc/hostname 2>/dev/null || echo "localhost")

# Initialized here; overridden during Docker pre-flight check
COMPOSE_CMD="docker compose"

# ── Parse CLI arguments ─────────────────────────────────────────────────────
usage() {
    echo -e "${BOLD}COSY Installer v${SCRIPT_VERSION}${NC}"
    echo ""
    echo "Usage: $0 <command> [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  docker                        Deploy using Docker Compose"
    echo "  kubernetes, k8s               Deploy to a Kubernetes cluster"
    echo ""
    echo "Run '$0 <command> --help' for command-specific options."
    echo ""
    echo "Options:"
    echo "  -h, --help                    Show this help message"
    exit 0
}

usage_docker() {
    echo -e "${BOLD}COSY Installer v${SCRIPT_VERSION} - Docker deployment${NC}"
    echo ""
    echo "Usage: $0 docker [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --path     /path/to/install   Base directory (cosy/ created inside)  (default: /opt)"
    echo "  --port     <port>             Port for the reverse proxy / CORS     (default: 80)"
    echo "  --username <name>             Admin account username               (default: admin)"
    echo "  --domain   <domain>           Domain for CORS configuration        (default: ${DOMAIN_DEFAULT})"
    echo "  --default                     Use defaults for all unset options (non-interactive)"
    echo "  -h, --help                    Show this help message"
    exit 0
}

usage_kubernetes() {
    echo -e "${BOLD}COSY Installer v${SCRIPT_VERSION} - Kubernetes deployment${NC}"
    echo ""
    echo "Usage: $0 kubernetes [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --username <name>             Admin account username               (default: admin)"
    echo "  --domain   <domain>           Domain for CORS / ingress host       (default: ${DOMAIN_DEFAULT})"
    echo "  --default                     Use defaults for all unset options (non-interactive)"
    echo "  -h, --help                    Show this help message"
    exit 0
}

validate_port() {
    local port="$1"
    if ! [[ "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
        fatal "Invalid port number: ${port}\n\n  Port must be a number between 1 and 65535."
    fi
}

# ── Parse subcommand (optional – prompted interactively if omitted) ────────────
case "${1-}" in
    docker)
        DEPLOY_METHOD="docker"; shift ;;
    kubernetes|k8s)
        DEPLOY_METHOD="kubernetes"; shift ;;
    -h|--help)
        usage ;;
    "")
        ;; # no subcommand – deployment method will be prompted interactively
    -*)
        fatal "Please provide a subcommand before any flags.\nRun '$0 --help' for usage information." ;;
    *)
        fatal "Unknown command: $1\nRun '$0 --help' for usage information." ;;
esac

# ── Parse flags for the selected command ─────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        # ── Docker-only flags ────────────────────────────────────────────────
        --path)
            [[ "$DEPLOY_METHOD" != "docker" ]] && fatal "--path is only supported for the 'docker' command.\nRun '$0 ${DEPLOY_METHOD} --help' for usage information."
            INSTALL_PATH="$2"; shift 2 ;;
        --port)
            [[ "$DEPLOY_METHOD" != "docker" ]] && fatal "--port is only supported for the 'docker' command.\nRun '$0 ${DEPLOY_METHOD} --help' for usage information."
            PORT="$2"; shift 2 ;;
        # ── Shared flags ─────────────────────────────────────────────────────
        --username)
            ADMIN_USERNAME="$2"; shift 2 ;;
        --domain)
            DOMAIN="$2"; shift 2 ;;
        --default)
            USE_DEFAULTS=true; shift ;;
        -h|--help)
            [[ "$DEPLOY_METHOD" == "docker" ]] && usage_docker || usage_kubernetes ;;
        *)
            fatal "Unknown option: $1\nRun '$0 ${DEPLOY_METHOD} --help' for usage information." ;;
    esac
done

# ── Interactive prompts (if running in a terminal) ───────────────────────────
if [[ -t 0 ]] && [[ "${USE_DEFAULTS-}" != "true" ]]; then
    echo -e "${BOLD}${CYAN}"
    echo "  ╔═══════════════════════════════════════╗"
    echo "  ║        COSY Installer v${SCRIPT_VERSION}          ║"
    echo "  ╚═══════════════════════════════════════╝"
    echo -e "${NC}"

    # ── Deployment method ───────────────────────────────────────────────────
    if [[ -z "${DEPLOY_METHOD-}" ]]; then
      echo -e "${BOLD}Select deployment method:${NC}"
      echo "  1) Docker  (default)"
      echo "  2) Kubernetes"
      echo ""
      read -rp "Enter choice [1]: " method_choice
      case "${method_choice:-1}" in
        1) DEPLOY_METHOD="docker" ;;
        2) DEPLOY_METHOD="kubernetes" ;;
        *) fatal "Invalid choice '${method_choice}'. Please enter 1 or 2." ;;
      esac
      echo ""
    fi
    info "Deployment method: ${DEPLOY_METHOD}"
    echo ""

    # ── Installation path (Docker only) ──────────────────────────────────────
    if [[ "$DEPLOY_METHOD" == "docker" && -z "${INSTALL_PATH-}" ]]; then
      read -rp "Installation path [${INSTALL_PATH_DEFAULT}]: " input_path
      INSTALL_PATH="${input_path:-$INSTALL_PATH_DEFAULT}"
    fi

    # ── Admin username ───────────────────────────────────────────────────────
    if [[ -z "${ADMIN_USERNAME-}" ]]; then
      read -rp "Admin username [${ADMIN_USERNAME_DEFAULT}]: " input_user
      ADMIN_USERNAME="${input_user:-$ADMIN_USERNAME_DEFAULT}"
    fi

    # ── Port (Docker only) ───────────────────────────────────────────────────
    if [[ "$DEPLOY_METHOD" == "docker" && -z "${PORT-}" ]]; then
      read -rp "Port [${PORT_DEFAULT}]: " input_port
      PORT="${input_port:-$PORT_DEFAULT}"
      validate_port "$PORT"
    fi

    # ── Domain ───────────────────────────────────────────────────────────────
    if [[ -z "${DOMAIN-}" ]]; then
      read -rp "Domain [${DOMAIN_DEFAULT}]: " input_domain
      DOMAIN="${input_domain:-$DOMAIN_DEFAULT}"
    fi
fi

# ── Apply defaults ───────────────────────────────────────────────────────────
DEPLOY_METHOD="${DEPLOY_METHOD:-docker}"
PORT="${PORT:-$PORT_DEFAULT}"
ADMIN_USERNAME="${ADMIN_USERNAME:-$ADMIN_USERNAME_DEFAULT}"
DOMAIN="${DOMAIN:-$DOMAIN_DEFAULT}"

# Validate port (only for Docker)
[[ "$DEPLOY_METHOD" == "docker" ]] && validate_port "$PORT"

# Build CORS origin and access URL
if [[ "$PORT" == "80" ]]; then
    COSY_CORS_ORIGIN="http://${DOMAIN}"
    ACCESS_URL="http://${DOMAIN}"
else
    COSY_CORS_ORIGIN="http://${DOMAIN}:${PORT}"
    ACCESS_URL="http://${DOMAIN}:${PORT}"
fi

# ─────────────────────────────────────────────────────────────────────────────
#  Shared helpers
# ─────────────────────────────────────────────────────────────────────────────
K8S_TEMP_DIR=""
setup_k8s_temp_dir() {
    K8S_TEMP_DIR=$(mktemp -d) || fatal "Could not create temporary directory for K8s manifests"
    trap "rm -rf '$K8S_TEMP_DIR' 2>/dev/null; exit" EXIT
    info "K8s manifests will be downloaded to: ${K8S_TEMP_DIR}"
}

generate_password() {
  local pw
  pw=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 30) || true
  printf '%s' "$pw"
}

generate_htpasswd() {
    local user="$1" pass="$2"
    if command -v htpasswd &>/dev/null; then
        htpasswd -nb "$user" "$pass" 2>/dev/null
    elif command -v openssl &>/dev/null; then
        local hash
        hash=$(openssl passwd -apr1 "$pass")
        echo "${user}:${hash}"
    elif command -v python3 &>/dev/null; then
        python3 -c "
import crypt, random, string
salt = '\$apr1\$' + ''.join(random.choices(string.ascii_letters + string.digits, k=8))
print('${user}:' + crypt.crypt('${pass}', salt))
"
    else
        fatal "Cannot generate htpasswd.\n\n  Install one of: apache2-utils (htpasswd), openssl, or python3."
    fi
}

save_credentials_file() {
    local creds_file="${INSTALL_PATH}/credentials.txt"
    cat > "$creds_file" <<EOF
# COSY Credentials - Generated by Installer v${SCRIPT_VERSION}
# Generated on $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# ⚠  Keep this file secure!

DEPLOY_METHOD=${DEPLOY_METHOD}

ADMIN_USERNAME=${ADMIN_USERNAME}
ADMIN_PASSWORD=${ADMIN_PASSWORD}

POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}

LOKI_USER=${LOKI_USER}
LOKI_PASSWORD=${LOKI_PASSWORD}

COSY_INFLUXDB_USERNAME=${COSY_INFLUXDB_USERNAME}
COSY_INFLUXDB_PASSWORD=${COSY_INFLUXDB_PASSWORD}
COSY_INFLUXDB_ADMIN_TOKEN=${COSY_INFLUXDB_ADMIN_TOKEN}

COSY_CORS_ORIGIN=${COSY_CORS_ORIGIN}
EOF
    chmod 600 "$creds_file"
    success "Credentials saved to ${creds_file}"
}

# ─────────────────────────────────────────────────────────────────────────────
#  Generate credentials (shared by all deployment methods)
# ─────────────────────────────────────────────────────────────────────────────
POSTGRES_USER="cosy"
POSTGRES_PASSWORD="$(generate_password)"
LOKI_USER="loki-user"
LOKI_PASSWORD="$(generate_password)"
ADMIN_PASSWORD="$(generate_password)"
COSY_INFLUXDB_USERNAME="cosy"
COSY_INFLUXDB_PASSWORD="$(generate_password)"
COSY_INFLUXDB_ADMIN_TOKEN="$(generate_password)"

# ─────────────────────────────────────────────────────────────────────────────
#  Normalize installation path (called during deployment)
# ─────────────────────────────────────────────────────────────────────────────
normalize_install_path() {
    INSTALL_PATH="${INSTALL_PATH:-$INSTALL_PATH_DEFAULT}"
    if [[ "${INSTALL_PATH}" = ~* ]]; then
        INSTALL_PATH="${INSTALL_PATH/#\~/$HOME}"
    elif [[ "$INSTALL_PATH" != /* ]]; then
        INSTALL_PATH="$PWD/$INSTALL_PATH"
    fi
    INSTALL_PATH="${INSTALL_PATH%/}"
    INSTALL_PATH="${INSTALL_PATH}/cosy"
}

setup_installation_directory() {
    info "Creating installation directory: ${INSTALL_PATH}"
    if ! mkdir -p "$INSTALL_PATH" 2>/dev/null; then
        fatal "Could not create directory '${INSTALL_PATH}'.\n\n  Make sure you have write permissions, or choose a different path:\n    $0 --path /some/other/path"
    fi
    success "Installation directory ready."
}


# ═══════════════════════════════════════════════════════════════════════════════
# ██████╗  ██████╗  ██████╗██╗  ██╗███████╗██████╗
# ██╔══██╗██╔═══██╗██╔════╝██║ ██╔╝██╔════╝██╔══██╗
# ██║  ██║██║   ██║██║     █████╔╝ █████╗  ██████╔╝
# ██║  ██║██║   ██║██║     ██╔═██╗ ██╔══╝  ██╔══██╗
# ██████╔╝╚██████╔╝╚██████╗██║  ██╗███████╗██║  ██║
# ╚═════╝  ╚═════╝  ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝
# ═══════════════════════════════════════════════════════════════════════════════

# ── Docker: Pre-flight checks ───────────────────────────────────────────────
check_docker_prerequisites() {
    if ! command -v docker &>/dev/null; then
        fatal "Docker is not installed or not in PATH.\n\n  To install Docker, follow the official guide:\n    https://docs.docker.com/engine/install/\n\n  After installation, make sure your user is in the 'docker' group:\n    sudo usermod -aG docker \$USER\n  Then log out and log back in."
    fi
    success "Docker found: $(docker --version)"

    if ! docker info &>/dev/null; then
        fatal "Docker daemon is not running.\n\n  Try starting it with:\n    sudo systemctl start docker\n\n  If the issue persists, check:\n    sudo systemctl status docker"
    fi
    success "Docker daemon is running."

    if docker compose version &>/dev/null; then
        COMPOSE_CMD="docker compose"
        success "Docker Compose (plugin) found: $(docker compose version --short 2>/dev/null || echo 'available')"
    elif command -v docker-compose &>/dev/null; then
        COMPOSE_CMD="docker-compose"
        success "Docker Compose (standalone) found: $(docker-compose --version)"
    else
        fatal "Docker Compose is not installed.\n\n  Make sure either the \`docker compose\` or \`docker-compose\` command is available."
    fi

    if ss -tlnp 2>/dev/null | grep -q ":${PORT} " || \
       netstat -tlnp 2>/dev/null | grep -q ":${PORT} "; then
        fatal "Port ${PORT} (nginx) is already in use.\n\n  Either stop the service using that port or choose a different port:\n    $0 --port <port>"
    fi
    success "Port ${PORT} is available."
}

# ── Docker: Write htpasswd file ─────────────────────────────────────────────
write_docker_htpasswd() {
    local htpasswd_dir="${INSTALL_PATH}/config"
    local htpasswd_path="${htpasswd_dir}/htpasswd"
    mkdir -p "$htpasswd_dir"

    local htpasswd_line
    htpasswd_line=$(generate_htpasswd "$LOKI_USER" "$LOKI_PASSWORD")
    echo "$htpasswd_line" > "$htpasswd_path"
    chmod 644 "$htpasswd_path"
    success "htpasswd created at ${htpasswd_path}."
}

# ── Docker: Download configuration files ────────────────────────────────────
download_docker_configs() {
    info "Downloading configuration files..."
    local config_dir="${INSTALL_PATH}/config"
    mkdir -p "$config_dir"

    local -a files=("docker-compose.yml" "loki-config.yaml" "loki-nginx.conf" "nginx.conf")
    for f in "${files[@]}"; do
        curl -L -o "${config_dir}/${f}" "${CONFIG_FILES_URL_PREFIX}/config/docker/${f}" 2>/dev/null \
            || fatal "Failed to download ${f} from ${CONFIG_FILES_URL_PREFIX}/config/docker/${f}\n\n  Check your internet connection and try again."
        success "${f} downloaded."
    done
    success "All configuration files downloaded."
}

# ── Docker: Write .env file for docker-compose ──────────────────────────────
write_docker_env_file() {
    info "Creating .env file for docker-compose..."
    local env_file="${INSTALL_PATH}/config/.env"

    local host_uid docker_gid volume_dir
    host_uid=$(id -u)
    docker_gid=$(getent group docker | cut -d: -f3)
    volume_dir="${INSTALL_PATH}/volumes"

    cat > "$env_file" <<EOF
# COSY Installer v${SCRIPT_VERSION}
# Generated on $(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Deployment configuration
HOST_UID=${host_uid}
DOCKER_GID=${docker_gid}

# Image tags
BACKEND_IMAGE_TAG=${BACKEND_TAG}
FRONTEND_IMAGE_TAG=${FRONTEND_TAG}

# COSY configuration
ADMIN_USERNAME=${ADMIN_USERNAME}
ADMIN_PASSWORD=${ADMIN_PASSWORD}
PORT=${PORT}
COSY_CORS_ALLOWED_ORIGINS=${COSY_CORS_ORIGIN}
VOLUME_DIRECTORY=${volume_dir}

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
COSY_INFLUXDB_ORG=${INFLUXDB_ORG}
COSY_INFLUXDB_BUCKET=${INFLUXDB_BUCKET}
EOF

    chmod 600 "$env_file"
    success ".env file created at ${env_file}"
}

# ── Docker: Start services ──────────────────────────────────────────────────
start_docker_services() {
    info "Starting COSY services..."
    echo ""
    cd "$INSTALL_PATH"

    local log_dir="${INSTALL_PATH}/logs"
    mkdir -p "$log_dir"
    local log_path="${log_dir}/compose-up.log"
    local env_file="${INSTALL_PATH}/config/.env"

    info "Starting containers with ${COMPOSE_CMD} (output shown below)"
    if ! $COMPOSE_CMD -f "${INSTALL_PATH}/config/docker-compose.yml" --env-file "$env_file" up -d 2>&1 | tee "$log_path"; then
        echo ""
        fatal "Failed to start COSY services.\n\n  Log saved to: ${log_path}\n\n  Troubleshooting steps:\n    1. Check the logs:  cd ${INSTALL_PATH}/config && ${COMPOSE_CMD} logs\n    2. Ensure Docker has enough resources (RAM, disk space)\n    3. Verify your internet connection"
    fi
}

# ── Docker: Wait for health ─────────────────────────────────────────────────
wait_for_docker_health() {
    info "Waiting for services to become ready..."
    local max_retries=60 interval=3 retries=0

    while [[ $retries -lt $max_retries ]]; do
        if curl -sf "http://127.0.0.1:${PORT}/api/actuator/health" &>/dev/null || \
           curl -sf "http://127.0.0.1:${PORT}" &>/dev/null; then
            break
        fi
        retries=$((retries + 1))
        if [[ $((retries % 10)) -eq 0 ]]; then
            info "Still waiting... (${retries}/${max_retries})"
        fi
        sleep "$interval"
    done

    if [[ $retries -ge $max_retries ]]; then
        fatal "Services did not become ready within $((max_retries * interval)) seconds."
    fi
}

# ── Docker: Main deployment function ────────────────────────────────────────
deploy_docker() {
    normalize_install_path
    setup_installation_directory
    check_docker_prerequisites
    write_docker_htpasswd
    download_docker_configs

    mkdir -p "${INSTALL_PATH}/volumes"
    success "Volume directory created."

    write_docker_env_file
    save_credentials_file
    start_docker_services
    wait_for_docker_health
}


# ═══════════════════════════════════════════════════════════════════════════════
# ██╗  ██╗ █████╗ ███████╗
# ██║ ██╔╝██╔══██╗██╔════╝
# █████╔╝ ╚█████╔╝███████╗
# ██╔═██╗ ██╔══██╗╚════██║
# ██║  ██╗╚█████╔╝███████║
# ╚═╝  ╚═╝ ╚════╝ ╚══════╝
# ═══════════════════════════════════════════════════════════════════════════════

# ── K8s: Download manifests ────────────────────────────────────────────────
download_k8s_manifests() {
    info "Downloading K8s manifests..."
    
    # Define all manifest files to download
    local -A manifest_files=(
        [postgres]="pvc.yaml service.yaml statefulset.yaml"
        [loki]="configmap.yaml pvc.yaml deployment.yaml service.yaml"
        [loki-nginx]="configmap.yaml deployment.yaml service.yaml"
        [influxdb]="pvc-data.yaml pvc-config.yaml deployment.yaml service.yaml"
        [backend]="deployment.yaml service.yaml"
        [frontend]="deployment.yaml service.yaml"
        [ingress]="frontend.yaml backend.yaml"
    )
    
    for subdir in "${!manifest_files[@]}"; do
        mkdir -p "${K8S_TEMP_DIR}/${subdir}"
        for file in ${manifest_files[$subdir]}; do
            curl -L -o "${K8S_TEMP_DIR}/${subdir}/${file}" "${CONFIG_FILES_URL_PREFIX}/config/k8s/${subdir}/${file}" 2>/dev/null \
                || fatal "Failed to download ${subdir}/${file}\n\n  Check your internet connection and try again."
            success "  ${subdir}/${file} downloaded."
        done
    done
    success "All K8s manifests downloaded."
}

# ── K8s: Pre-flight checks ──────────────────────────────────────────────────
check_k8s_prerequisites() {
    if ! command -v kubectl &>/dev/null; then
        fatal "kubectl is not installed or not in PATH.\n\n  To install kubectl, follow the official guide:\n    https://kubernetes.io/docs/tasks/tools/"
    fi
    success "kubectl found: $(kubectl version --client 2>/dev/null | head -1)"

    # If running under sudo, try to reuse the original user's kubeconfig
    if [[ -n "${SUDO_USER-}" && -z "${KUBECONFIG-}" ]]; then
      original_home=$(getent passwd "$SUDO_USER" | cut -d: -f6 || true)
      if [[ -n "$original_home" && -f "$original_home/.kube/config" ]]; then
        export KUBECONFIG="$original_home/.kube/config"
        info "Using KUBECONFIG from ${original_home}/.kube/config (SUDO_USER=${SUDO_USER})"
      fi
    fi

    if ! kubectl get nodes &>/dev/null; then
      fatal "Cannot connect to a Kubernetes cluster.\n\n  Make sure your kubeconfig is set up correctly:\n    kubectl cluster-info"
    fi
      success "Kubernetes cluster is reachable."
}

# ── K8s: Create namespace ───────────────────────────────────────────────────
create_k8s_namespace() {
    info "Creating namespace '${K8S_NAMESPACE}'..."
    kubectl create namespace "$K8S_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    success "Namespace '${K8S_NAMESPACE}' ready."
}

# ── K8s: Create secrets ─────────────────────────────────────────────────────
create_k8s_secrets() {
    info "Creating Kubernetes secrets in namespace '${K8S_NAMESPACE}'..."

    # PostgreSQL credentials
    kubectl create secret generic cosy-postgresql-credentials \
        --namespace="$K8S_NAMESPACE" \
        --from-literal=postgresql-username="$POSTGRES_USER" \
        --from-literal=postgresql-password="$POSTGRES_PASSWORD" \
        --dry-run=client -o yaml | kubectl apply -f -
    success "Secret 'cosy-postgresql-credentials' created."

    # Loki credentials (used by the backend to authenticate with the loki nginx proxy)
    kubectl create secret generic cosy-loki-credentials \
        --namespace="$K8S_NAMESPACE" \
        --from-literal=user="$LOKI_USER" \
        --from-literal=password="$LOKI_PASSWORD" \
        --dry-run=client -o yaml | kubectl apply -f -
    success "Secret 'cosy-loki-credentials' created."

    # Loki htpasswd (mounted as a file by the nginx auth proxy)
    local htpasswd_line
    htpasswd_line=$(generate_htpasswd "$LOKI_USER" "$LOKI_PASSWORD")
    kubectl create secret generic loki-htpasswd \
        --namespace="$K8S_NAMESPACE" \
        --from-literal=htpasswd="$htpasswd_line" \
        --dry-run=client -o yaml | kubectl apply -f -
    success "Secret 'loki-htpasswd' created."

    # InfluxDB secrets
    kubectl create secret generic cosy-influxdb-secrets \
        --namespace="$K8S_NAMESPACE" \
        --from-literal=DOCKER_INFLUXDB_INIT_PASSWORD="$COSY_INFLUXDB_PASSWORD" \
        --from-literal=DOCKER_INFLUXDB_INIT_ADMIN_TOKEN="$COSY_INFLUXDB_ADMIN_TOKEN" \
        --dry-run=client -o yaml | kubectl apply -f -
    success "Secret 'cosy-influxdb-secrets' created."

    # Application secrets (admin credentials)
    kubectl create secret generic cosy-app-secrets \
        --namespace="$K8S_NAMESPACE" \
        --from-literal=admin-username="$ADMIN_USERNAME" \
        --from-literal=admin-password="$ADMIN_PASSWORD" \
        --dry-run=client -o yaml | kubectl apply -f -
    success "Secret 'cosy-app-secrets' created."
}

# ── K8s: PostgreSQL (StatefulSet + Service + PVC) ────────────────────────────
apply_k8s_postgres() {
    info "Deploying PostgreSQL..."
    kubectl apply -n "$K8S_NAMESPACE" -f "${K8S_TEMP_DIR}/postgres/"
    info "PostgreSQL deployed."
}

# ── K8s: Loki (Deployment + Service + PVC + ConfigMap) ───────────────────────
apply_k8s_loki() {
    info "Deploying Loki..."
    kubectl apply -n "$K8S_NAMESPACE" -f "${K8S_TEMP_DIR}/loki/"
    info "Loki deployed."
}

# ── K8s: Loki nginx auth proxy (Deployment + Service + ConfigMap) ────────────
apply_k8s_loki_nginx_proxy() {
    info "Deploying Loki nginx auth proxy..."
    kubectl apply -n "$K8S_NAMESPACE" -f "${K8S_TEMP_DIR}/loki-nginx/"
    info "Loki nginx auth proxy deployed."
}

# ── K8s: InfluxDB (Deployment + Service + PVCs) ─────────────────────────────
apply_k8s_influxdb() {
    info "Deploying InfluxDB..."
    local manifest_dir="${K8S_TEMP_DIR}/influxdb"
    # Replace placeholders with actual values in all files
    find "$manifest_dir" -name "*.yaml" -type f -exec sed -i "s/INFLUXDB_BUCKET_PLACEHOLDER/${INFLUXDB_BUCKET}/g" {} \;
    find "$manifest_dir" -name "*.yaml" -type f -exec sed -i "s/INFLUXDB_ORG_PLACEHOLDER/${INFLUXDB_ORG}/g" {} \;
    find "$manifest_dir" -name "*.yaml" -type f -exec sed -i "s/COSY_INFLUXDB_USERNAME_PLACEHOLDER/${COSY_INFLUXDB_USERNAME}/g" {} \;
    kubectl apply -n "$K8S_NAMESPACE" -f "$manifest_dir/"
    info "InfluxDB deployed."
}

# ── K8s: Backend (Deployment + Service) ──────────────────────────────────────
apply_k8s_backend() {
    info "Deploying backend..."
    local manifest_dir="${K8S_TEMP_DIR}/backend"
    # Replace placeholders with actual values in all files
    find "$manifest_dir" -name "*.yaml" -type f -exec sed -i "s|BACKEND_TAG_PLACEHOLDER|${BACKEND_TAG}|g" {} \;
    find "$manifest_dir" -name "*.yaml" -type f -exec sed -i "s|INFLUXDB_ORG_PLACEHOLDER|${INFLUXDB_ORG}|g" {} \;
    find "$manifest_dir" -name "*.yaml" -type f -exec sed -i "s|INFLUXDB_BUCKET_PLACEHOLDER|${INFLUXDB_BUCKET}|g" {} \;
    find "$manifest_dir" -name "*.yaml" -type f -exec sed -i "s|COSY_CORS_ORIGIN_PLACEHOLDER|${COSY_CORS_ORIGIN}|g" {} \;
    kubectl apply -n "$K8S_NAMESPACE" -f "$manifest_dir/"
    info "Backend deployed."
}

# ── K8s: Frontend (Deployment + Service) ─────────────────────────────────────
apply_k8s_frontend() {
    info "Deploying frontend..."
    local manifest_dir="${K8S_TEMP_DIR}/frontend"
    # Replace placeholders with actual values in all files
    find "$manifest_dir" -name "*.yaml" -type f -exec sed -i "s|FRONTEND_TAG_PLACEHOLDER|${FRONTEND_TAG}|g" {} \;
    kubectl apply -n "$K8S_NAMESPACE" -f "$manifest_dir/"
    info "Frontend deployed."
}

# ── K8s: Ingresses (dynamically generated with the configured domain) ────────
apply_k8s_ingresses() {
    info "Creating ingresses for domain '${DOMAIN}'..."
    local manifest_dir="${K8S_TEMP_DIR}/ingress"
    # Replace domain placeholder with actual domain in all files
    find "$manifest_dir" -name "*.yaml" -type f -exec sed -i "s|DOMAIN_PLACEHOLDER|${DOMAIN}|g" {} \;
    kubectl apply -n "$K8S_NAMESPACE" -f "$manifest_dir/"
    info "Ingresses created for '${DOMAIN}'."
}

# ── K8s: Wait for all workloads to become ready ─────────────────────────────
wait_for_k8s_ready() {
    info "Waiting for all pods to become ready..."

    local -a deployments=("cosy-backend" "cosy-frontend" "cosy-loki" "cosy-loki-nginx" "cosy-influxdb")
    for name in "${deployments[@]}"; do
        info "  Waiting for deployment/${name}..."
        if ! kubectl rollout status deployment/"$name" -n "$K8S_NAMESPACE" --timeout=300s 2>/dev/null; then
            warn "Deployment '${name}' did not become ready within timeout."
        fi
    done

    info "  Waiting for statefulset/cosy-postgres..."
    if ! kubectl rollout status statefulset/cosy-postgres -n "$K8S_NAMESPACE" --timeout=180s 2>/dev/null; then
        warn "StatefulSet 'cosy-postgres' did not become ready within timeout."
    fi

    success "All Kubernetes resources deployed."
}

# ── K8s: Main deployment function ────────────────────────────────────────────
deploy_kubernetes() {
    check_k8s_prerequisites
    setup_k8s_temp_dir
    create_k8s_namespace
    create_k8s_secrets
    download_k8s_manifests

    info "Applying Kubernetes manifests..."
    apply_k8s_postgres
    apply_k8s_loki
    apply_k8s_loki_nginx_proxy
    apply_k8s_influxdb
    apply_k8s_backend
    apply_k8s_frontend
    apply_k8s_ingresses
    wait_for_k8s_ready
}


# ═══════════════════════════════════════════════════════════════════════════════
#  Dispatch & Summary
# ═══════════════════════════════════════════════════════════════════════════════

case "$DEPLOY_METHOD" in
    docker)     deploy_docker ;;
    kubernetes) deploy_kubernetes ;;
esac

# ─────────────────────────────────────────────────────────────────────────────
#  Success summary
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║          COSY installation completed successfully!        ║${NC}"
echo -e "${GREEN}${BOLD}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
if [[ "$DEPLOY_METHOD" == "docker" ]]; then
    echo -e "  ${BOLD}Installation path:${NC}  ${INSTALL_PATH}"
fi
echo -e "  ${BOLD}Deployment method:${NC}  ${DEPLOY_METHOD}"
if [[ "$DEPLOY_METHOD" == "kubernetes" ]]; then
    echo -e "  ${BOLD}Namespace:${NC}          ${K8S_NAMESPACE}"
fi
echo ""
echo -e "  ${CYAN}${BOLD}── Login Credentials ──────────────────────────────────${NC}"
echo -e "  ${BOLD}Username:${NC}           ${ADMIN_USERNAME}"
echo -e "  ${BOLD}Password:${NC}           ${ADMIN_PASSWORD}"
echo ""
echo -e "  ${CYAN}${BOLD}── Access URL ────────────────────────────────────────${NC}"
echo -e "  ${BOLD}COSY:${NC}               ${GREEN}${ACCESS_URL}${NC}"
echo ""
echo -e "  ${YELLOW}⚠  Please save the password above - it will not be shown again.${NC}"
if [[ "$DEPLOY_METHOD" == "docker" ]]; then
    echo -e "  ${YELLOW}   Credentials are also saved at: ${INSTALL_PATH}/credentials.txt${NC}"
fi
echo ""
if [[ "$DEPLOY_METHOD" == "docker" ]]; then
    echo -e "  ${BOLD}Useful commands:${NC}"
    echo -e "    Stop COSY:    cd ${INSTALL_PATH}/config && ${COMPOSE_CMD} down"
    echo -e "    View logs:    cd ${INSTALL_PATH}/config && ${COMPOSE_CMD} logs -f"
    echo -e "    Restart:      cd ${INSTALL_PATH}/config && ${COMPOSE_CMD} restart"
else
    echo -e "  ${BOLD}Useful commands:${NC}"
    echo -e "    Get pods:     kubectl get pods -n ${K8S_NAMESPACE}"
    echo -e "    View logs:    kubectl logs -n ${K8S_NAMESPACE} deployment/cosy-backend"
    echo -e "    Restart:      kubectl rollout restart -n ${K8S_NAMESPACE} deployment/cosy-backend"
    echo -e "    Uninstall:    kubectl delete namespace ${K8S_NAMESPACE}"
fi
echo ""
