#!/usr/bin/env bash
#
# etcd Defragmentation Script
# Rolling defrag of the control plane etcd members, one node at a time.
#
# Why: compaction (kube-apiserver runs it every 5m by default) frees pages
# *inside* the etcd database file but never shrinks the file. Only defrag
# returns the space to the filesystem. A large gap between "DB SIZE" and
# "IN USE" in `talosctl etcd status` is the signature — measured 860 MB
# allocated vs 246 MB in use (28.5%) on 2026-08-06, i.e. ~600 MB per master
# reclaimable on an 18.76 GiB /var.
#
# Per the Talos docs, defrag is resource-intensive and must run on one node at
# a time. This script enforces that: it verifies quorum before each node, does
# the leader last (forfeiting leadership first so the election happens on our
# terms), and re-checks health before moving on.
#
# https://docs.siderolabs.com/talos/v1.13/build-and-extend-talos/cluster-operations-and-maintenance/etcd-maintenance
#
# Usage:
#   ./etcd-defrag.sh [--dry-run] [--skip-snapshot] [--snapshot-dir <dir>]
#
# Examples:
#   ./etcd-defrag.sh --dry-run     # show the plan, touch nothing
#   ./etcd-defrag.sh               # snapshot, then rolling defrag
#   ./etcd-defrag.sh --skip-snapshot

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

CONTROLPLANE_NODES=(
    "10.1.20.11"
    "10.1.20.12"
    "10.1.20.13"
)

# Only used to give `talosctl health` an explicit node list. Without one it
# falls back to cluster discovery, which returns the workers' 10.1.11.0/24
# storage-mesh addresses (see talos/patches/storage-net-worker-0*.yaml). That
# mesh is a direct 10G triangle between the Proxmox hosts with no route from a
# workstation, so every apid probe against it times out and the check hangs.
WORKER_NODES=(
    "10.1.20.21"
    "10.1.20.22"
    "10.1.20.23"
)

QUORUM_TIMEOUT=180        # Max wait for etcd quorum to return after a defrag
QUORUM_INTERVAL=5         # Poll interval while waiting
SETTLE_SECONDS=15         # Grace period after a defrag before health polling

# =============================================================================
# Colors and Output
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()    { echo -e "\n${BOLD}${CYAN}==> $*${NC}"; }

# =============================================================================
# Argument Parsing
# =============================================================================

DRY_RUN=false
SKIP_SNAPSHOT=false
SNAPSHOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

print_usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Options:
    --dry-run                Show what would be done without making changes
    --skip-snapshot          Do not take an etcd snapshot first (not advised)
    --snapshot-dir <dir>     Where to write the snapshot (default: repo root)
    -h, --help               Show this help message

The snapshot is written as etcd-snapshot-<timestamp>.db. The repo's .gitignore
already excludes *.db, but the file is a full copy of cluster state — including
every Secret — so move it somewhere safe or delete it when you are done.
EOF
}

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)       DRY_RUN=true; shift ;;
        --skip-snapshot) SKIP_SNAPSHOT=true; shift ;;
        --snapshot-dir)  SNAPSHOT_DIR="$2"; shift 2 ;;
        -h|--help)       print_usage; exit 0 ;;
        *)               log_error "Unknown option: $1"; print_usage; exit 1 ;;
    esac
done

# =============================================================================
# Prerequisite Checks
# =============================================================================

check_prerequisites() {
    log_step "Checking prerequisites"

    if ! command -v talosctl &>/dev/null; then
        log_error "talosctl not found in PATH"
        exit 1
    fi

    if ! talos_node "${CONTROLPLANE_NODES[0]}" etcd status &>/dev/null; then
        log_error "Cannot reach etcd on ${CONTROLPLANE_NODES[0]} — check your talosconfig"
        exit 1
    fi

    log_success "talosctl available and etcd reachable"
}

# =============================================================================
# etcd Helpers
# =============================================================================

# Raw status table for all members, printed as-is.
show_etcd_status() {
    talosctl -n "$(IFS=,; echo "${CONTROLPLANE_NODES[*]}")" etcd status 2>/dev/null || true
}

# Pin the endpoint as well as the node, so the request is served by that node's
# own apid rather than whichever endpoint talosctl picks from the talosconfig.
# Targeting is verified per node after each defrag regardless — see defrag_node.
talos_node() {
    local node="$1"; shift
    talosctl -e "$node" -n "$node" "$@"
}

# One status line for a node, data rows only (no header). Never fails: a node
# that is mid-defrag or briefly unreachable must yield an empty string for the
# callers to poll on, not a non-zero exit that `set -e`/`pipefail` turns fatal.
node_status_line() {
    local node="$1"
    talos_node "$node" etcd status 2>/dev/null | awk -v ip="$node" '$1 == ip' || true
}

# In-use percentage as an integer, from the "(28.48%)" column. Empty if the
# line cannot be parsed.
node_in_use_pct() {
    node_status_line "$1" | awk '{gsub(/[()%]/, "", $7); printf "%.0f", $7}'
}

# Member ID of a node. Column 2 of the status table.
get_member_id() {
    node_status_line "$1" | awk '{print $2}'
}

# Leader member ID as seen by a node. Columns 3-4 are "DB SIZE" ("860 MB") and
# 5-7 are "IN USE" ("246 MB (28.55%)"), so LEADER lands on field 8. If Talos
# ever changes the column layout this returns junk, so every caller treats an
# unexpected value as "unknown" rather than acting on it.
get_leader_id() {
    node_status_line "$1" | awk '{print $8}'
}

# Healthy = every member answers, and they all name the same leader.
#
# The loop variable MUST stay local. Bash scoping is dynamic: an unlocalized
# `for node in ...` here reassigns the caller's `node`, and since defrag_node
# calls this before reading its target, every later reference resolved to the
# last element of CONTROLPLANE_NODES instead. That is what sent all three
# defrags of 2026-08-06 to 10.1.20.13.
check_etcd_quorum() {
    local leaders=() ids=() n line

    for n in "${CONTROLPLANE_NODES[@]}"; do
        line="$(node_status_line "$n")"
        [[ -z "$line" ]] && return 1

        ids+=("$(echo "$line" | awk '{print $2}')")
        leaders+=("$(echo "$line" | awk '{print $8}')")
    done

    [[ ${#ids[@]} -eq ${#CONTROLPLANE_NODES[@]} ]] || return 1

    local first="${leaders[0]}"
    [[ -n "$first" ]] || return 1
    for l in "${leaders[@]}"; do
        [[ "$l" == "$first" ]] || return 1
    done

    return 0
}

wait_for_etcd_quorum() {
    local elapsed=0

    log_info "Waiting for etcd quorum to settle..."
    while [[ $elapsed -lt $QUORUM_TIMEOUT ]]; do
        if check_etcd_quorum; then
            log_success "All ${#CONTROLPLANE_NODES[@]} members healthy and agreeing on a leader"
            return 0
        fi
        sleep "$QUORUM_INTERVAL"
        elapsed=$((elapsed + QUORUM_INTERVAL))
    done

    log_error "etcd quorum did not return within ${QUORUM_TIMEOUT}s"
    return 1
}

check_alarms() {
    log_step "Checking etcd alarms"

    local output
    output="$(talosctl -n "$(IFS=,; echo "${CONTROLPLANE_NODES[*]}")" etcd alarm list 2>/dev/null || true)"

    # An empty table (header only, or nothing) means no alarms are set.
    if [[ -z "$(echo "$output" | awk 'NR > 1 && NF')" ]]; then
        log_success "No etcd alarms set"
        return 0
    fi

    echo "$output"
    log_warn "An alarm is set. A NOSPACE alarm makes etcd read-only and will NOT"
    log_warn "clear on its own — after this defrag finishes, run:"
    log_warn "  talosctl -n ${CONTROLPLANE_NODES[0]} etcd alarm disarm"
}

# =============================================================================
# Defrag
# =============================================================================

take_snapshot() {
    log_step "Taking etcd snapshot"

    local path="${SNAPSHOT_DIR}/etcd-snapshot-$(date +%Y%m%d-%H%M%S).db"

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] talosctl -e ${CONTROLPLANE_NODES[0]} -n ${CONTROLPLANE_NODES[0]} etcd snapshot $path"
        return 0
    fi

    if talos_node "${CONTROLPLANE_NODES[0]}" etcd snapshot "$path"; then
        log_success "Snapshot written to $path"
        log_warn "This file contains every Secret in the cluster — move or delete it when done"
    else
        log_error "Snapshot failed — not proceeding with defrag"
        exit 1
    fi
}

defrag_node() {
    local node="$1"

    log_step "Defragmenting $node"

    if ! check_etcd_quorum; then
        log_error "etcd is not healthy — refusing to defrag $node"
        return 1
    fi

    local before
    before="$(node_status_line "$node")"
    log_info "Before: $(echo "$before" | awk '{print $3, $4, "allocated,", $5, $6, $7, "in use"}')"

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] talosctl -n $node etcd defrag"
        return 0
    fi

    if ! talos_node "$node" etcd defrag; then
        log_error "Defrag failed on $node"
        return 1
    fi

    log_info "Defrag issued, letting the member settle (${SETTLE_SECONDS}s)..."
    sleep "$SETTLE_SECONDS"

    if ! wait_for_etcd_quorum; then
        log_error "Cluster did not recover after defragging $node — stopping here"
        return 1
    fi

    local after
    after="$(node_status_line "$node")"
    log_info "After:  $(echo "$after" | awk '{print $3, $4, "allocated,", $5, $6, $7, "in use"}')"

    # Prove the defrag landed on the member we targeted. A freshly defragged
    # file is almost entirely live data, so in-use should jump to ~100%; if it
    # is still low, the request went somewhere else (see talos_node above) and
    # continuing would silently skip nodes.
    local pct
    pct="$(node_in_use_pct "$node")"
    if [[ -z "$pct" ]]; then
        log_error "Could not read in-use % for $node — cannot confirm the defrag"
        return 1
    fi
    if [[ "$pct" -lt 90 ]]; then
        log_error "$node is still only ${pct}% in use — the defrag did NOT take effect on this member"
        log_error "Check: talosctl -e $node -n $node logs etcd | grep defragmenting"
        return 1
    fi

    log_success "$node defragmented (${pct}% in use)"
}

# =============================================================================
# Main
# =============================================================================

main() {
    echo -e "${BOLD}${CYAN}"
    echo "============================================"
    echo "  etcd Rolling Defragmentation"
    echo "============================================"
    echo -e "${NC}"

    [[ "$DRY_RUN" == true ]] && log_warn "DRY RUN — no changes will be made"

    check_prerequisites
    check_alarms

    log_step "Current etcd status"
    show_etcd_status

    if ! check_etcd_quorum; then
        log_error "etcd is not healthy right now. Fix that before defragmenting."
        exit 1
    fi
    log_success "Quorum healthy"

    # Defrag followers first and the leader last, so the one disruptive moment
    # (leadership transfer) happens once, at the end, against members that have
    # already been compacted.
    local leader_id followers=() leader_node="" node
    leader_id="$(get_leader_id "${CONTROLPLANE_NODES[0]}")"

    for node in "${CONTROLPLANE_NODES[@]}"; do
        if [[ -n "$leader_id" && "$(get_member_id "$node")" == "$leader_id" ]]; then
            leader_node="$node"
        else
            followers+=("$node")
        fi
    done

    if [[ -z "$leader_node" ]]; then
        log_warn "Could not identify the leader — defragmenting in listed order"
        followers=("${CONTROLPLANE_NODES[@]}")
    else
        log_info "Leader is $leader_node (member $leader_id) — it goes last"
    fi

    [[ "$SKIP_SNAPSHOT" == false ]] && take_snapshot

    for node in "${followers[@]}"; do
        defrag_node "$node" || exit 1
    done

    if [[ -n "$leader_node" ]]; then
        log_step "Forfeiting leadership on $leader_node"
        if [[ "$DRY_RUN" == true ]]; then
            log_info "[DRY RUN] talosctl -e $leader_node -n $leader_node etcd forfeit-leadership"
        elif talos_node "$leader_node" etcd forfeit-leadership; then
            log_success "Leadership moved off $leader_node"
            sleep "$SETTLE_SECONDS"
            wait_for_etcd_quorum || exit 1
        else
            log_warn "forfeit-leadership failed — defragmenting the leader in place"
        fi

        defrag_node "$leader_node" || exit 1
    fi

    log_step "Final etcd status"
    show_etcd_status

    log_step "Verifying cluster health"
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY RUN] talosctl health --server=false --control-plane-nodes ... --worker-nodes ..."
    else
        # Explicit node lists + --server=false: skip Talos cluster discovery,
        # which advertises the workers on the unroutable 10.1.11.0/24 Ceph mesh
        # and makes this check hang on apid timeouts.
        talosctl health \
            --server=false \
            --control-plane-nodes "$(IFS=,; echo "${CONTROLPLANE_NODES[*]}")" \
            --worker-nodes "$(IFS=,; echo "${WORKER_NODES[*]}")" \
            --wait-timeout 2m || {
            log_error "Cluster health check failed — investigate before walking away"
            exit 1
        }
    fi

    echo -e "\n${BOLD}${GREEN}Defragmentation complete.${NC}\n"
}

main "$@"
