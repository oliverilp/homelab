#!/usr/bin/env bash
#
# Talos Cluster Upgrade Script
# Performs rolling upgrades of Talos OS and Kubernetes with health checks
#
# Features:
#   - Idempotent: skips nodes/clusters already at target version
#   - Health checks: CNPG PostgreSQL, critical namespace pods
#   - Rolling upgrades: one node at a time with verification
#
# Upgrade order: Talos first (control plane, then workers), then Kubernetes
# Rationale: Talos supports multiple K8s versions, but new K8s may need newer Talos
#
# Usage:
#   ./talos-upgrade.sh [--talos-image <image>] [--k8s-version <version>] [--dry-run]
#
# Examples:
#   ./talos-upgrade.sh --talos-image factory.talos.dev/installer/...:v1.10.0
#   ./talos-upgrade.sh --k8s-version 1.32.0
#   ./talos-upgrade.sh --talos-image factory.talos.dev/installer/...:v1.10.0 --k8s-version 1.32.0
#   ./talos-upgrade.sh --talos-image factory.talos.dev/installer/...:v1.10.0 --dry-run

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

# Cluster VIP for health checks
CLUSTER_VIP="10.1.20.10"

# Control plane nodes (upgraded first)
CONTROLPLANE_NODES=(
    "10.1.20.11"
    "10.1.20.12"
    "10.1.20.13"
)

# Worker nodes (upgraded after control plane)
WORKER_NODES=(
    "10.1.20.21"
    "10.1.20.22"
    "10.1.20.23"
)

# CNPG PostgreSQL clusters to check (namespace/name format)
CNPG_CLUSTERS=(
    "postgresql/postgres-apps"
    "postgresql/postgres-immich"
)

# Namespaces to verify pods are running
CHECK_NAMESPACES=(
    "authentik"
    "immich"
)

# Timeouts and retries
HEALTH_CHECK_TIMEOUT=300      # 5 minutes
HEALTH_CHECK_INTERVAL=10      # Check every 10 seconds
NODE_READY_TIMEOUT=600        # 10 minutes for node to become ready after upgrade

# =============================================================================
# Colors and Output
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()    { echo -e "\n${BOLD}${CYAN}==> $*${NC}"; }

# =============================================================================
# Argument Parsing
# =============================================================================

TALOS_IMAGE=""
K8S_VERSION=""
DRY_RUN=false

print_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Options:
    --talos-image <image>    Talos installer image (optional, required for Talos upgrade)
    --k8s-version <version>  Kubernetes version to upgrade to (optional)
    --dry-run                Show what would be done without making changes
    -h, --help               Show this help message

At least one of --talos-image or --k8s-version must be specified.
Nodes already at the target version will be skipped (idempotent).

Examples:
    # Upgrade Talos only
    $0 --talos-image factory.talos.dev/installer/...:v1.10.0

    # Upgrade Kubernetes only
    $0 --k8s-version 1.32.0

    # Upgrade both Kubernetes and Talos
    $0 --talos-image factory.talos.dev/installer/...:v1.10.0 --k8s-version 1.32.0

    # Dry run to see what would happen
    $0 --talos-image factory.talos.dev/installer/...:v1.10.0 --dry-run
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --talos-image)
            TALOS_IMAGE="$2"
            shift 2
            ;;
        --k8s-version)
            K8S_VERSION="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

if [[ -z "$TALOS_IMAGE" ]] && [[ -z "$K8S_VERSION" ]]; then
    log_error "At least one of --talos-image or --k8s-version must be specified"
    print_usage
    exit 1
fi

# =============================================================================
# Version Utilities
# =============================================================================

# Extract Talos version from image tag (e.g., "v1.10.0" from "factory.talos.dev/...:v1.10.0")
get_talos_target_version() {
    echo "$TALOS_IMAGE" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | tail -1
}

# Get current Talos version on a node
get_node_talos_version() {
    local node_ip="$1"
    talosctl version -n "$node_ip" --short 2>/dev/null | grep "Tag:" | head -1 | awk '{print $2}'
}

# Get current Kubernetes version from a node
get_current_k8s_version() {
    kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.kubeletVersion}' 2>/dev/null | sed 's/^v//'
}

# =============================================================================
# Prerequisite Checks
# =============================================================================

check_prerequisites() {
    log_step "Checking prerequisites"

    local missing=()

    if ! command -v talosctl &>/dev/null; then
        missing+=("talosctl")
    fi

    if ! command -v kubectl &>/dev/null; then
        missing+=("kubectl")
    fi

    if ! command -v jq &>/dev/null; then
        missing+=("jq")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing[*]}"
        exit 1
    fi

    log_success "All required tools available"
}

# =============================================================================
# Health Check Functions
# =============================================================================

check_talos_health() {
    log_info "Running talosctl health check against cluster VIP..."

    if talosctl health -n "$CLUSTER_VIP" --wait-timeout 2m; then
        log_success "Talos cluster health check passed"
        return 0
    else
        log_error "Talos cluster health check failed"
        return 1
    fi
}

check_cnpg_cluster() {
    local namespace="${1%/*}"
    local cluster="${1#*/}"

    # Get cluster status as JSON
    local status_json
    if ! status_json=$(kubectl cnpg status "$cluster" -n "$namespace" -o json 2>/dev/null); then
        log_error "Failed to get status for CNPG cluster $cluster"
        return 1
    fi

    # Extract key metrics from .cluster.status
    local instances ready_instances phase
    instances=$(echo "$status_json" | jq -r '.cluster.status.instances // 0')
    ready_instances=$(echo "$status_json" | jq -r '.cluster.status.readyInstances // 0')
    phase=$(echo "$status_json" | jq -r '.cluster.status.phase // "unknown"')

    # Check health - phase should be "Cluster in healthy state"
    if [[ "$instances" -eq "$ready_instances" ]] && [[ "$phase" == *"healthy"* ]]; then
        log_success "CNPG cluster $namespace/$cluster: $ready_instances/$instances ready ($phase)"
        return 0
    else
        log_error "CNPG cluster $namespace/$cluster: $ready_instances/$instances ready ($phase)"
        return 1
    fi
}

check_all_cnpg_clusters() {
    log_info "Checking CloudNativePG cluster health..."

    local failed=0
    for cluster in "${CNPG_CLUSTERS[@]}"; do
        if ! check_cnpg_cluster "$cluster"; then
            ((failed++))
        fi
    done

    if [[ $failed -gt 0 ]]; then
        log_error "$failed CNPG cluster(s) unhealthy"
        return 1
    fi
    return 0
}

check_namespace_pods() {
    local namespace="$1"

    # Get pod status summary
    local total running not_running
    total=$(kubectl get pods -n "$namespace" --no-headers 2>/dev/null | wc -l | tr -d ' ')
    running=$(kubectl get pods -n "$namespace" --no-headers 2>/dev/null | grep -c "Running" || true)
    not_running=$((total - running))

    if [[ $total -eq 0 ]]; then
        log_warn "No pods found in namespace $namespace"
        return 0
    fi

    if [[ $not_running -eq 0 ]]; then
        log_success "Namespace $namespace: $running/$total pods running"
        return 0
    else
        # Show which pods are not running
        log_error "Namespace $namespace: $running/$total pods running"
        kubectl get pods -n "$namespace" --no-headers 2>/dev/null | grep -v "Running" | while read -r line; do
            log_warn "  Not running: $line"
        done
        return 1
    fi
}

check_all_namespace_pods() {
    log_info "Checking pod status in critical namespaces..."

    local failed=0
    for ns in "${CHECK_NAMESPACES[@]}"; do
        if ! check_namespace_pods "$ns"; then
            ((failed++))
        fi
    done

    if [[ $failed -gt 0 ]]; then
        log_error "$failed namespace(s) have pods not running"
        return 1
    fi
    return 0
}

check_node_ready() {
    local node_ip="$1"

    # Get node name from IP
    local node_name
    node_name=$(kubectl get nodes -o json | jq -r ".items[] | select(.status.addresses[] | select(.type==\"InternalIP\" and .address==\"$node_ip\")) | .metadata.name")

    if [[ -z "$node_name" ]]; then
        log_error "Could not find node with IP $node_ip"
        return 1
    fi

    # Check if node is Ready
    local ready_status
    ready_status=$(kubectl get node "$node_name" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')

    if [[ "$ready_status" == "True" ]]; then
        log_success "Node $node_name ($node_ip) is Ready"
        return 0
    else
        log_warn "Node $node_name ($node_ip) is not Ready"
        return 1
    fi
}

# =============================================================================
# Wait Functions
# =============================================================================

wait_for_health() {
    local description="$1"
    local check_func="$2"
    shift 2

    log_info "Waiting for $description..."

    local elapsed=0
    while [[ $elapsed -lt $HEALTH_CHECK_TIMEOUT ]]; do
        if $check_func "$@"; then
            return 0
        fi
        sleep "$HEALTH_CHECK_INTERVAL"
        elapsed=$((elapsed + HEALTH_CHECK_INTERVAL))
        log_info "Still waiting... ($elapsed/${HEALTH_CHECK_TIMEOUT}s)"
    done

    log_error "Timeout waiting for $description"
    return 1
}

wait_for_node_ready() {
    local node_ip="$1"

    log_info "Waiting for node $node_ip to become Ready..."

    local elapsed=0
    while [[ $elapsed -lt $NODE_READY_TIMEOUT ]]; do
        if check_node_ready "$node_ip"; then
            return 0
        fi
        sleep "$HEALTH_CHECK_INTERVAL"
        elapsed=$((elapsed + HEALTH_CHECK_INTERVAL))
    done

    log_error "Timeout waiting for node $node_ip to become Ready"
    return 1
}

# =============================================================================
# Upgrade Functions
# =============================================================================

upgrade_kubernetes() {
    if [[ -z "$K8S_VERSION" ]]; then
        log_info "No Kubernetes version specified, skipping K8s upgrade"
        return 0
    fi

    log_step "Checking Kubernetes version"

    # Check if already at target version
    local current_version
    current_version=$(get_current_k8s_version)

    if [[ "$current_version" == "$K8S_VERSION" ]]; then
        log_success "Kubernetes already at v$K8S_VERSION, skipping"
        return 0
    fi

    log_info "Kubernetes: v$current_version -> v$K8S_VERSION"

    if $DRY_RUN; then
        log_info "[DRY-RUN] Would run: talosctl upgrade-k8s -n ${CONTROLPLANE_NODES[0]} --to $K8S_VERSION"
        log_success "Kubernetes would be upgraded v$current_version -> v$K8S_VERSION (dry-run)"
        return 0
    fi

    # Use first control plane node for k8s upgrade
    if talosctl upgrade-k8s -n "${CONTROLPLANE_NODES[0]}" --to "$K8S_VERSION"; then
        log_success "Kubernetes upgrade to $K8S_VERSION completed"
    else
        log_error "Kubernetes upgrade failed"
        return 1
    fi

    # Verify cluster health after K8s upgrade
    log_info "Verifying cluster health after Kubernetes upgrade..."
    sleep 30  # Give cluster time to stabilize

    if ! check_all_cnpg_clusters; then
        log_error "CNPG clusters unhealthy after Kubernetes upgrade"
        return 1
    fi

    if ! check_all_namespace_pods; then
        log_error "Pods unhealthy after Kubernetes upgrade"
        return 1
    fi

    log_success "Cluster healthy after Kubernetes upgrade"
}

upgrade_node() {
    local node_ip="$1"
    local node_type="$2"  # "controlplane" or "worker"

    log_step "Checking $node_type node: $node_ip"

    # Check if node is already at target version
    local current_version target_version
    current_version=$(get_node_talos_version "$node_ip")
    target_version=$(get_talos_target_version)

    if [[ "$current_version" == "$target_version" ]]; then
        log_success "Node $node_ip already at $target_version, skipping"
        return 0
    fi

    log_info "Node $node_ip: $current_version -> $target_version"

    # Pre-upgrade health check
    log_info "Pre-upgrade health check for node $node_ip..."
    if ! check_all_cnpg_clusters; then
        log_error "Pre-upgrade CNPG health check failed, aborting"
        return 1
    fi

    if $DRY_RUN; then
        log_info "[DRY-RUN] Would run: talosctl upgrade -n $node_ip --image $TALOS_IMAGE --wait"
        log_success "Node $node_ip would be upgraded $current_version -> $target_version (dry-run)"
        return 0
    fi

    # Perform the upgrade
    log_info "Starting Talos upgrade on $node_ip..."
    if ! talosctl upgrade -n "$node_ip" --image "$TALOS_IMAGE" --wait; then
        log_error "Talos upgrade failed on $node_ip"
        return 1
    fi

    log_success "Talos upgrade completed on $node_ip"

    # Wait for node to become ready
    if ! wait_for_node_ready "$node_ip"; then
        log_error "Node $node_ip did not become Ready after upgrade"
        return 1
    fi

    # Give cluster time to stabilize
    log_info "Waiting 30s for cluster to stabilize..."
    sleep 30

    # Post-upgrade CNPG health check with retry
    log_info "Post-upgrade CNPG health check..."
    if ! wait_for_health "CNPG clusters to be healthy" check_all_cnpg_clusters; then
        log_error "CNPG clusters did not recover after upgrading $node_ip"
        return 1
    fi

    # Post-upgrade namespace pod check
    log_info "Post-upgrade pod health check..."
    if ! wait_for_health "namespace pods to be running" check_all_namespace_pods; then
        log_error "Pods did not recover after upgrading $node_ip"
        return 1
    fi

    log_success "Node $node_ip upgraded and cluster healthy"
}

# =============================================================================
# Main Execution
# =============================================================================

main() {
    echo -e "${BOLD}${CYAN}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║           Talos Cluster Upgrade Script                         ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    if $DRY_RUN; then
        log_warn "DRY-RUN MODE - No changes will be made"
    fi

    if [[ -n "$TALOS_IMAGE" ]]; then
        log_info "Talos image: $TALOS_IMAGE"
        log_info "Talos target: $(get_talos_target_version)"
    else
        log_info "Talos upgrade: skipped (no image specified)"
    fi
    if [[ -n "$K8S_VERSION" ]]; then
        log_info "Kubernetes target: v$K8S_VERSION"
    else
        log_info "Kubernetes upgrade: skipped (no version specified)"
    fi
    log_info "Control plane nodes: ${CONTROLPLANE_NODES[*]}"
    log_info "Worker nodes: ${WORKER_NODES[*]}"
    echo

    # Prerequisites
    check_prerequisites

    # Preflight checks
    log_step "Running preflight checks"

    if ! check_talos_health; then
        log_error "Preflight check failed: Talos cluster unhealthy"
        log_error "Resolve cluster health issues before attempting upgrade"
        exit 1
    fi

    if ! check_all_cnpg_clusters; then
        log_error "Preflight check failed: CNPG clusters unhealthy"
        exit 1
    fi

    if ! check_all_namespace_pods; then
        log_error "Preflight check failed: Critical pods not running"
        exit 1
    fi

    log_success "All preflight checks passed"

    # Show current versions
    log_step "Current cluster versions"
    log_info "Talos versions:"
    talosctl version -n "${CONTROLPLANE_NODES[0]}" --short 2>/dev/null || true
    echo
    log_info "Kubernetes node versions:"
    kubectl get nodes -o wide --no-headers | awk '{print $1, $5, $9}'
    echo

    # Confirm before proceeding
    if ! $DRY_RUN; then
        echo
        log_warn "This will upgrade your cluster. Continue? [y/N] "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            log_info "Upgrade cancelled"
            exit 0
        fi
    fi

    # Upgrade Talos first (before K8s, as new K8s may require newer Talos)
    if [[ -n "$TALOS_IMAGE" ]]; then
        # Control plane nodes first
        log_step "Upgrading Talos on control plane nodes"
        for node in "${CONTROLPLANE_NODES[@]}"; do
            if ! upgrade_node "$node" "controlplane"; then
                log_error "Failed to upgrade control plane node $node"
                log_error "Cluster may be in inconsistent state - manual intervention required"
                exit 1
            fi
        done

        # Worker nodes second
        log_step "Upgrading Talos on worker nodes"
        for node in "${WORKER_NODES[@]}"; do
            if ! upgrade_node "$node" "worker"; then
                log_error "Failed to upgrade worker node $node"
                log_error "Cluster may be in inconsistent state - manual intervention required"
                exit 1
            fi
        done
    else
        log_info "No Talos image specified, skipping Talos upgrade"
    fi

    # Kubernetes upgrade last (after all nodes have new Talos)
    upgrade_kubernetes

    # Final verification
    log_step "Final verification"
    log_info "Talos versions:"
    talosctl version -n "${CONTROLPLANE_NODES[0]}" --short 2>/dev/null || true
    echo
    log_info "Kubernetes node versions:"
    kubectl get nodes -o wide --no-headers | awk '{print $1, $5, $9}'
    echo

    if ! check_talos_health; then
        log_error "Final health check failed"
        exit 1
    fi

    if ! check_all_cnpg_clusters; then
        log_error "Final CNPG health check failed"
        exit 1
    fi

    if ! check_all_namespace_pods; then
        log_error "Final pod health check failed"
        exit 1
    fi

    echo
    log_success "═══════════════════════════════════════════════════════════════"
    if $DRY_RUN; then
        log_success " Dry-run complete - all health checks passed!"
    else
        log_success " Cluster upgrade completed successfully!"
    fi
    log_success "═══════════════════════════════════════════════════════════════"
}

main "$@"
