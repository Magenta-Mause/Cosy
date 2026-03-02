#!/bin/sh
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# COSY Uninstallation Script
# ─────────────────────────────────────────────────────────────────────────────
# Usage:  ./uninstall_cosy.sh <command> [OPTIONS]
#
# Commands:
#   docker                        Remove a Docker Compose installation
#   kubernetes (k8s)              Remove a Kubernetes installation
#
# Run './uninstall_cosy.sh <command> --help' for command-specific options.
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
K8S_NAMESPACE_DEFAULT="cosy"
SKIP_CONFIRM=false

# ── Help messages ────────────────────────────────────────────────────────────
usage() {
    echo -e "${BOLD}COSY Uninstaller${NC}"
    echo ""
    echo "Usage: $0 <command> [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  docker                        Remove a Docker Compose installation"
    echo "  kubernetes, k8s               Remove a Kubernetes installation"
    echo ""
    echo "Run '$0 <command> --help' for command-specific options."
    echo ""
    echo "Options:"
    echo "  -h, --help                    Show this help message"
    exit 0
}

usage_docker() {
    echo -e "${BOLD}COSY Uninstaller - Docker${NC}"
    echo ""
    echo "Usage: $0 docker [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --path    /path/to/install    Base directory that contains the cosy/ folder"
    echo "                                (default: /opt → looks for /opt/cosy)"
    echo "  -y, --yes                     Skip confirmation prompt"
    echo "  -h, --help                    Show this help message"
    exit 0
}

usage_kubernetes() {
    echo -e "${BOLD}COSY Uninstaller - Kubernetes${NC}"
    echo ""
    echo "Usage: $0 kubernetes [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --namespace <ns>              Kubernetes namespace to delete"
    echo "                                (default: ${K8S_NAMESPACE_DEFAULT})"
    echo "  -y, --yes                     Skip confirmation prompt"
    echo "  -h, --help                    Show this help message"
    exit 0
}

# ── Parse subcommand ─────────────────────────────────────────────────────────
if [[ $# -eq 0 ]]; then
    usage
fi

case "$1" in
    docker)
        UNINSTALL_METHOD="docker"; shift ;;
    kubernetes|k8s)
        UNINSTALL_METHOD="kubernetes"; shift ;;
    -h|--help)
        usage ;;
    *)
        fatal "Unknown command: $1\nRun '$0 --help' for usage information." ;;
esac

# ── Parse flags for the selected command ─────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        # ── Docker-only flags ────────────────────────────────────────────────
        --path)
            [[ "$UNINSTALL_METHOD" != "docker" ]] && fatal "--path is only supported for the 'docker' command.\nRun '$0 ${UNINSTALL_METHOD} --help' for usage information."
            INSTALL_PATH="$2"; shift 2 ;;
        # ── Kubernetes-only flags ────────────────────────────────────────────
        --namespace)
            [[ "$UNINSTALL_METHOD" != "kubernetes" ]] && fatal "--namespace is only supported for the 'kubernetes' command.\nRun '$0 ${UNINSTALL_METHOD} --help' for usage information."
            K8S_NAMESPACE="$2"; shift 2 ;;
        # ── Shared flags ─────────────────────────────────────────────────────
        -y|--yes)
            SKIP_CONFIRM=true; shift ;;
        -h|--help)
            [[ "$UNINSTALL_METHOD" == "docker" ]] && usage_docker || usage_kubernetes ;;
        *)
            fatal "Unknown option: $1\nRun '$0 ${UNINSTALL_METHOD} --help' for usage information." ;;
    esac
done


# ═══════════════════════════════════════════════════════════════════════════════
#  Docker uninstallation
# ═══════════════════════════════════════════════════════════════════════════════
uninstall_docker() {
    # ── Resolve installation path ────────────────────────────────────────────
    INSTALL_PATH="${INSTALL_PATH:-$INSTALL_PATH_DEFAULT}"

    if [[ "${INSTALL_PATH}" = ~* ]]; then
        INSTALL_PATH="${INSTALL_PATH/#\~/$HOME}"
    elif [[ "$INSTALL_PATH" != /* ]]; then
        INSTALL_PATH="$PWD/$INSTALL_PATH"
    fi

    INSTALL_PATH="${INSTALL_PATH%/}"
    COSY_DIR="${INSTALL_PATH}/cosy"

    # ── Check that a COSY installation exists ────────────────────────────────
    if [[ ! -d "${COSY_DIR}" ]]; then
        if [[ "${INSTALL_PATH}" != "${INSTALL_PATH_DEFAULT}" ]]; then
            fatal "No COSY installation found at ${COSY_DIR}.\n\n  Make sure the path is correct."
        else
            fatal "No COSY installation found at the default location (${COSY_DIR}).\n\n  If COSY was installed in a custom location, specify it with:\n    $0 docker --path /path/to/base"
        fi
    fi

    COMPOSE_FILE="${COSY_DIR}/config/docker-compose.yml"
    ENV_FILE="${COSY_DIR}/config/.env"

    if [[ ! -f "${COMPOSE_FILE}" ]]; then
        fatal "docker-compose.yml not found at ${COMPOSE_FILE}.\n  The installation appears to be incomplete or corrupted."
    fi

    # ── Detect docker compose command ────────────────────────────────────────
    if docker compose version &>/dev/null; then
        COMPOSE_CMD="docker compose"
    elif command -v docker-compose &>/dev/null; then
        COMPOSE_CMD="docker-compose"
    else
        fatal "Docker Compose is not installed.\n  Cannot stop and remove COSY containers without it."
    fi

    # ── Confirmation ─────────────────────────────────────────────────────────
    echo ""
    echo -e "${BOLD}${RED}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${RED}║                COSY Uninstallation (Docker)               ║${NC}"
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
        read -rp "Are you sure you want to continue? [Y/n]: " confirm
        case "${confirm}" in
            [nN]|[nN][oO]) 
                info "Uninstallation cancelled."
                exit 0
                ;;
        esac
    fi

    # ── Stop and remove containers, volumes, and networks ────────────────────
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

    # ── Remove any gameserver containers with cosy- prefix ──────────────────────
    info "Checking for gameserver containers..."

    # Collect all containers with cosy- prefix
    local -a containers=()
    mapfile -t containers < <(docker ps -a --format '{{.Names}}' | grep "^cosy-" || true)

    # Remove each container
    for container_name in "${containers[@]}"; do
        if [[ -n "$container_name" ]]; then
            info "Removing gameserver container: ${container_name}"
            docker rm -f "${container_name}" 2>/dev/null || true
        fi
    done

    if [[ ${#containers[@]} -eq 0 ]]; then
        success "No gameserver containers found."
    else
        success "Removed ${#containers[@]} gameserver container(s)."
    fi

    # ── Remove systemd service ────────────────────────────────────────────────
    local service_file="/etc/systemd/system/cosy.service"
    if [[ -f "$service_file" ]]; then
        info "Removing systemd service..."
        systemctl stop cosy.service 2>/dev/null || true
        systemctl disable cosy.service 2>/dev/null || true
        rm -f "$service_file"
        systemctl daemon-reload
        success "systemd service removed."
    else
        info "No systemd service found, skipping."
    fi

    # ── Delete installation directory ────────────────────────────────────────
    info "Deleting installation directory: ${COSY_DIR}"

    if rm -rf "${COSY_DIR}"; then
        success "Installation directory deleted."
    else
        warn "Could not fully remove ${COSY_DIR}. You may need to run with sudo."
    fi
}


# ═══════════════════════════════════════════════════════════════════════════════
#  Kubernetes uninstallation
# ═══════════════════════════════════════════════════════════════════════════════
uninstall_kubernetes() {
    K8S_NAMESPACE="${K8S_NAMESPACE:-$K8S_NAMESPACE_DEFAULT}"

    # ── Pre-flight checks ────────────────────────────────────────────────────
    if ! command -v kubectl &>/dev/null; then
        fatal "kubectl is not installed or not in PATH.\n\n  To install kubectl, follow the official guide:\n    https://kubernetes.io/docs/tasks/tools/"
    fi

    # If running under sudo, try to reuse the original user's kubeconfig
    if [[ -n "${SUDO_USER-}" && -z "${KUBECONFIG-}" ]]; then
        local original_home
        original_home=$(getent passwd "$SUDO_USER" | cut -d: -f6 || true)
        if [[ -n "$original_home" && -f "$original_home/.kube/config" ]]; then
            export KUBECONFIG="$original_home/.kube/config"
            info "Using KUBECONFIG from ${original_home}/.kube/config (SUDO_USER=${SUDO_USER})"
        fi
    fi

    if ! kubectl get nodes &>/dev/null; then
        fatal "Cannot connect to a Kubernetes cluster.\n\n  Make sure your kubeconfig is set up correctly:\n    kubectl cluster-info"
    fi

    # ── Check that namespace exists ──────────────────────────────────────────
    if ! kubectl get namespace "$K8S_NAMESPACE" &>/dev/null; then
        fatal "Namespace '${K8S_NAMESPACE}' does not exist.\n\n  If COSY was installed in a custom namespace, specify it with:\n    $0 kubernetes --namespace <ns>"
    fi

    # ── Confirmation ─────────────────────────────────────────────────────────
    echo ""
    echo -e "${BOLD}${RED}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${RED}║             COSY Uninstallation (Kubernetes)              ║${NC}"
    echo -e "${BOLD}${RED}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BOLD}Namespace:${NC}  ${K8S_NAMESPACE}"
    echo ""
    echo -e "  ${YELLOW}This will:${NC}"
    echo -e "    • Delete the Kubernetes namespace '${K8S_NAMESPACE}'"
    echo -e "    • Remove all deployments, services, secrets, and PVCs within it"
    echo ""

    if [[ "${SKIP_CONFIRM}" != "true" ]]; then
        read -rp "Are you sure you want to continue? [Y/n]: " confirm
        case "${confirm}" in
            [nN]|[nN][oO]) 
                info "Uninstallation cancelled."
                exit 0
                ;;
        esac
    fi

    # ── Delete namespace ─────────────────────────────────────────────────────
    info "Deleting namespace '${K8S_NAMESPACE}'..."

    if kubectl delete namespace "$K8S_NAMESPACE" 2>&1; then
        success "Namespace '${K8S_NAMESPACE}' deleted."
    else
        fatal "Failed to delete namespace '${K8S_NAMESPACE}'.\n\n  Try manually:\n    kubectl delete namespace ${K8S_NAMESPACE}"
    fi
}


# ═══════════════════════════════════════════════════════════════════════════════
#  Dispatch
# ═══════════════════════════════════════════════════════════════════════════════
case "$UNINSTALL_METHOD" in
    docker)     uninstall_docker ;;
    kubernetes) uninstall_kubernetes ;;
esac

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}${BOLD}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}${BOLD}║         COSY has been uninstalled successfully!   :(      ║${NC}"
echo -e "${BLUE}${BOLD}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
