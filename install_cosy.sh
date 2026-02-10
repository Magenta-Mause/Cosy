#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# COSY Installation Script
# ─────────────────────────────────────────────────────────────────────────────
# Usage:  ./install_cosy.sh [OPTIONS]
#
# Options:
#   --method  docker|kubernetes   Deployment method       (default: docker)
#   --path    /path/to/install    Installation directory   (default: ~/.cosy)
#   --username <name>             Admin account username   (default: admin)
#   --port-frontend <port>        Frontend port            (default: 3000)
#   --port-backend  <port>        Backend port             (default: 8080)
#   -h, --help                    Show this help message
# ─────────────────────────────────────────────────────────────────────────────

readonly SCRIPT_VERSION="1.0.0"

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

# ── Defaults ─────────────────────────────────────────────────────────────────
DEPLOY_METHOD_DEFAULT="docker"
INSTALL_PATH_DEFAULT="/opt/cosy"
ADMIN_USERNAME_DEFAULT="admin"
FRONTEND_PORT_DEFAULT="3000"
BACKEND_PORT_DEFAULT="8080"

# ── Parse CLI arguments ─────────────────────────────────────────────────────
usage() {
    echo -e "${BOLD}COSY Installer v${SCRIPT_VERSION}${NC}"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --method  docker|kubernetes   Deployment method        (default: docker)"
    echo "  --path    /path/to/install    Installation directory   (default: /opt/cosy)"
    echo "  --username <name>             Admin account username   (default: admin)"
    echo "  --port-frontend <port>        Frontend port            (default: 3000)"
    echo "  --port-backend  <port>        Backend port             (default: 8080)"
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
        --port-frontend)
            FRONTEND_PORT="$2"; shift 2 ;;
        --port-backend)
            BACKEND_PORT="$2"; shift 2 ;;
        -h|--help)
            usage ;;
        *)
            fatal "Unknown option: $1\nRun '$0 --help' for usage information." ;;
    esac
done

# ── Interactive prompts (if running in a terminal) ───────────────────────────
if [[ -t 0 ]]; then
    echo -e "${BOLD}${CYAN}"
    echo "  ╔═══════════════════════════════════════╗"
    echo "  ║        COSY Installer v${SCRIPT_VERSION}          ║"
    echo "  ╚═══════════════════════════════════════╝"
    echo -e "${NC}"

    # ── Deployment method ────────────────────────────────────────────────────
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

    # ── Ports ────────────────────────────────────────────────────────────────
    read -rp "Frontend port [${FRONTEND_PORT}]: " input_fe_port
    FRONTEND_PORT="${input_fe_port:-$FRONTEND_PORT}"

    read -rp "Backend port [${BACKEND_PORT}]: " input_be_port
    BACKEND_PORT="${input_be_port:-$BACKEND_PORT}"

    echo ""
fi

# ── Validate deployment method ───────────────────────────────────────────────
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
    fatal "Docker Compose is not installed.\n\n  Install the Docker Compose plugin:\n    sudo apt-get install docker-compose-plugin   # Debian/Ubuntu\n    sudo dnf install docker-compose-plugin        # Fedora\n\n  Or see: https://docs.docker.com/compose/install/"
fi

# ── Check port availability ──────────────────────────────────────────────────
check_port() {
    local port="$1"
    local service="$2"
    if ss -tlnp 2>/dev/null | grep -q ":${port} " || \
       netstat -tlnp 2>/dev/null | grep -q ":${port} "; then
        fatal "Port ${port} (${service}) is already in use.\n\n  Either stop the service using that port or choose a different port:\n    $0 --port-frontend <port>  (for frontend)\n    $0 --port-backend  <port>  (for backend)"
    fi
}
check_port "$FRONTEND_PORT" "frontend"
check_port "$BACKEND_PORT" "backend"
success "Ports ${FRONTEND_PORT} (frontend) and ${BACKEND_PORT} (backend) are available."

# ─────────────────────────────────────────────────────────────────────────────
#  Generate credentials
# ─────────────────────────────────────────────────────────────────────────────
generate_password() {
    # 24-character alphanumeric password
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24
}

POSTGRES_USER="cosy"
POSTGRES_PASSWORD="$(generate_password)"
LOKI_USER="loki"
LOKI_PASSWORD="$(generate_password)"
ADMIN_PASSWORD="$(generate_password)"

# ─────────────────────────────────────────────────────────────────────────────
#  Create installation directory
# ─────────────────────────────────────────────────────────────────────────────
info "Creating installation directory: ${INSTALL_PATH}"
if ! mkdir -p "$INSTALL_PATH" 2>/dev/null; then
    fatal "Could not create directory '${INSTALL_PATH}'.\n\n  Make sure you have write permissions, or choose a different path:\n    $0 --path /some/other/path"
fi
success "Installation directory ready."

# ─────────────────────────────────────────────────────────────────────────────
#  Generate configuration files
# ─────────────────────────────────────────────────────────────────────────────

# ── .env ─────────────────────────────────────────────────────────────────────
info "Generating environment configuration..."
cat > "${INSTALL_PATH}/.env" <<EOF
# COSY Environment Configuration – generated on $(date -Iseconds)
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
LOKI_USER=${LOKI_USER}
LOKI_PASSWORD=${LOKI_PASSWORD}
COSY_ADMIN_USERNAME=${ADMIN_USERNAME}
COSY_ADMIN_PASSWORD=${ADMIN_PASSWORD}
EOF
chmod 600 "${INSTALL_PATH}/.env"
success ".env file created."

# ── docker-compose.yml ──────────────────────────────────────────────────────
info "Generating docker-compose.yml..."
cat > "${INSTALL_PATH}/docker-compose.yml" <<EOF
services:
  backend:
    image: ghcr.io/magenta-mause/cosy-backend:sha-2d4bdf3
    container_name: cosy-backend
    ports:
      - "127.0.0.1:${BACKEND_PORT}:8080"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    group_add:
      - "988"
    environment:
      - SPRING_DATASOURCE_USERNAME=\${POSTGRES_USER}
      - SPRING_DATASOURCE_PASSWORD=\${POSTGRES_PASSWORD}
      - SPRING_DATASOURCE_URL=jdbc:postgresql://database:5432/cosydb
      - COSY_ENGINE_DOCKER_SOCKET_PATH=unix:///var/run/docker.sock
      - COSY_LOKI_URL=http://loki-nginx-proxy:80
      - COSY_LOKI_USER=\${LOKI_USER}
      - COSY_LOKI_PASSWORD=\${LOKI_PASSWORD}
      - COSY_ADMIN_USERNAME=\${COSY_ADMIN_USERNAME}
      - COSY_ADMIN_PASSWORD=\${COSY_ADMIN_PASSWORD}
    depends_on:
      database:
        condition: service_started
      loki:
        condition: service_started
      loki-nginx-proxy:
        condition: service_started
    networks:
      - cosy-network
    restart: unless-stopped

  frontend:
    image: ghcr.io/magenta-mause/cosy-frontend:sha-b006d97
    container_name: cosy-frontend
    ports:
      - "127.0.0.1:${FRONTEND_PORT}:80"
    depends_on:
      backend:
        condition: service_started
    networks:
      - cosy-network
    restart: unless-stopped

  database:
    image: postgres:16
    container_name: cosy-database
    environment:
      - POSTGRES_DB=cosydb
      - POSTGRES_USER=\${POSTGRES_USER}
      - POSTGRES_PASSWORD=\${POSTGRES_PASSWORD}
    volumes:
      - postgres-data:/var/lib/postgresql/data
    networks:
      - cosy-network
    restart: unless-stopped

  loki:
    image: grafana/loki:2.9.4
    container_name: cosy-loki
    command: -config.file=/etc/loki/loki-config.yaml
    volumes:
      - loki-data:/loki
      - ./loki-config.yaml:/etc/loki/loki-config.yaml:ro
    networks:
      - cosy-network
    restart: unless-stopped

  loki-nginx-proxy:
    image: nginx:1.25
    container_name: cosy-loki-nginx
    volumes:
      - ./loki-nginx.conf:/etc/nginx/nginx.conf:ro
      - ./htpasswd:/etc/nginx/htpasswd:ro
    networks:
      - cosy-network
    depends_on:
      loki:
        condition: service_started
    restart: unless-stopped

volumes:
  postgres-data:
  loki-data:

networks:
  cosy-network:
EOF
success "docker-compose.yml created."

# ── loki-config.yaml ────────────────────────────────────────────────────────
info "Generating Loki configuration..."
cat > "${INSTALL_PATH}/loki-config.yaml" <<'EOF'
auth_enabled: false

server:
  http_listen_port: 3100

common:
  path_prefix: /loki
  storage:
    filesystem:
      chunks_directory: /loki/chunks
      rules_directory: /loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: "2020-10-24"
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

limits_config:
  reject_old_samples: true
  reject_old_samples_max_age: 168h
  max_query_series: 100000

analytics:
  reporting_enabled: false
EOF
success "loki-config.yaml created."

# ── loki-nginx.conf ─────────────────────────────────────────────────────────
info "Generating Loki nginx proxy configuration..."
cat > "${INSTALL_PATH}/loki-nginx.conf" <<'EOF'
events {
    worker_connections 1024;
}

http {
    upstream loki {
        server loki:3100;
    }

    server {
        listen 80;

        auth_basic "Loki";
        auth_basic_user_file /etc/nginx/htpasswd;

        location / {
            proxy_pass http://loki;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        }
    }
}
EOF
success "loki-nginx.conf created."

# ── htpasswd ─────────────────────────────────────────────────────────────────
info "Generating htpasswd for Loki authentication..."
# Use openssl or htpasswd to create the password hash
if command -v htpasswd &>/dev/null; then
    htpasswd -bc "${INSTALL_PATH}/htpasswd" "$LOKI_USER" "$LOKI_PASSWORD" 2>/dev/null
elif command -v openssl &>/dev/null; then
    LOKI_HASH=$(openssl passwd -apr1 "$LOKI_PASSWORD")
    echo "${LOKI_USER}:${LOKI_HASH}" > "${INSTALL_PATH}/htpasswd"
else
    # Fallback: use Python if available
    if command -v python3 &>/dev/null; then
        LOKI_HASH=$(python3 -c "
import crypt, random, string
salt = '\$apr1\$' + ''.join(random.choices(string.ascii_letters + string.digits, k=8))
print(crypt.crypt('${LOKI_PASSWORD}', salt))
")
        echo "${LOKI_USER}:${LOKI_HASH}" > "${INSTALL_PATH}/htpasswd"
    else
        fatal "Cannot generate htpasswd file.\n\n  Install one of the following:\n    - apache2-utils (provides htpasswd)\n    - openssl\n    - python3\n\n  On Debian/Ubuntu: sudo apt-get install apache2-utils"
    fi
fi
chmod 600 "${INSTALL_PATH}/htpasswd"
success "htpasswd created."

# ─────────────────────────────────────────────────────────────────────────────
#  Start COSY
# ─────────────────────────────────────────────────────────────────────────────
info "Starting COSY services..."
echo ""

cd "$INSTALL_PATH"

if ! $COMPOSE_CMD up -d 2>&1; then
    echo ""
    fatal "Failed to start COSY services.\n\n  Troubleshooting steps:\n    1. Check the logs:  cd ${INSTALL_PATH} && ${COMPOSE_CMD} logs\n    2. Ensure Docker has enough resources (RAM, disk space)\n    3. Check if the images can be pulled:  docker pull ghcr.io/magenta-mause/cosy-backend:sha-2d4bdf3\n    4. Verify your internet connection"
fi

# ── Wait for services to be healthy ─────────────────────────────────────────
info "Waiting for services to become ready..."

MAX_RETRIES=60
RETRY_INTERVAL=3
RETRIES=0

while [[ $RETRIES -lt $MAX_RETRIES ]]; do
    if curl -sf "http://127.0.0.1:${BACKEND_PORT}/actuator/health" &>/dev/null || \
       curl -sf "http://127.0.0.1:${BACKEND_PORT}" &>/dev/null; then
        break
    fi

    RETRIES=$((RETRIES + 1))
    if [[ $((RETRIES % 10)) -eq 0 ]]; then
        info "Still waiting... (${RETRIES}/${MAX_RETRIES})"
    fi
    sleep "$RETRY_INTERVAL"
done

if [[ $RETRIES -ge $MAX_RETRIES ]]; then
    warn "Services did not become ready within $((MAX_RETRIES * RETRY_INTERVAL)) seconds."
    warn "They may still be starting up. Check with: cd ${INSTALL_PATH} && ${COMPOSE_CMD} logs -f"
    echo ""
fi

# ─────────────────────────────────────────────────────────────────────────────
#  Success summary
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║          COSY installation completed successfully!       ║${NC}"
echo -e "${GREEN}${BOLD}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Installation path:${NC}  ${INSTALL_PATH}"
echo -e "  ${BOLD}Deployment method:${NC}  Docker"
echo ""
echo -e "  ${CYAN}${BOLD}── Login Credentials ──────────────────────────────────${NC}"
echo -e "  ${BOLD}Username:${NC}           ${ADMIN_USERNAME}"
echo -e "  ${BOLD}Password:${NC}           ${ADMIN_PASSWORD}"
echo ""
echo -e "  ${CYAN}${BOLD}── Access URLs ────────────────────────────────────────${NC}"
echo -e "  ${BOLD}Frontend:${NC}           ${GREEN}http://localhost:${FRONTEND_PORT}${NC}"
echo -e "  ${BOLD}Backend API:${NC}        http://localhost:${BACKEND_PORT}"
echo ""
echo -e "  ${YELLOW}⚠  Please save the password above – it will not be shown again.${NC}"
echo ""
echo -e "  ${BOLD}Useful commands:${NC}"
echo -e "    Stop COSY:    cd ${INSTALL_PATH} && ${COMPOSE_CMD} down"
echo -e "    View logs:    cd ${INSTALL_PATH} && ${COMPOSE_CMD} logs -f"
echo -e "    Restart:      cd ${INSTALL_PATH} && ${COMPOSE_CMD} restart"
echo ""
