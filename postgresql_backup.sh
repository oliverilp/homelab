#!/bin/bash

# PostgreSQL CNPG Backup Script
# Creates organized logical backups of all PostgreSQL databases in homelab
# Automatically detects primary pods and discovers all databases
# Usage: ./postgresql_backup.sh

set -euo pipefail

# Configuration
BACKUP_BASE_DIR="$HOME/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$BACKUP_BASE_DIR/backup_$TIMESTAMP"

# Kubernetes namespace
NAMESPACE="postgresql"

# Global variables for discovered clusters and databases
CLUSTERS=()
CLUSTER_PRIMARIES=()
CLUSTER_DATABASES=()

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

# Helper functions for working with parallel arrays
get_cluster_index() {
    local cluster=$1
    for i in "${!CLUSTERS[@]}"; do
        if [[ "${CLUSTERS[$i]}" == "$cluster" ]]; then
            echo "$i"
            return
        fi
    done
    echo "-1"
}

get_cluster_primary() {
    local cluster=$1
    local index=$(get_cluster_index "$cluster")
    if [[ $index -ge 0 ]]; then
        echo "${CLUSTER_PRIMARIES[$index]}"
    fi
}

get_cluster_databases() {
    local cluster=$1
    local index=$(get_cluster_index "$cluster")
    if [[ $index -ge 0 ]]; then
        echo "${CLUSTER_DATABASES[$index]}"
    fi
}

add_cluster() {
    local cluster=$1
    local primary=$2
    local databases=$3
    CLUSTERS+=("$cluster")
    CLUSTER_PRIMARIES+=("$primary")
    CLUSTER_DATABASES+=("$databases")
}

# Function to check if kubectl is available and cluster is accessible
check_prerequisites() {
    log "Checking prerequisites..."
    
    if ! command -v kubectl &> /dev/null; then
        error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    if ! kubectl get ns "$NAMESPACE" &> /dev/null; then
        error "Cannot access namespace '$NAMESPACE' or cluster is not reachable"
        exit 1
    fi
    
    success "Prerequisites check passed"
}

# Function to discover CNPG clusters and their primary pods
discover_clusters() {
    log "Discovering CNPG clusters and primary pods..."
    
    local clusters
    clusters=$(kubectl get clusters -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)
    
    if [[ -z "$clusters" ]]; then
        error "No CNPG clusters found in namespace '$NAMESPACE'"
        exit 1
    fi
    
    for cluster in $clusters; do
        log "Checking cluster: $cluster"
        
        # Get current primary pod
        local primary_pod
        primary_pod=$(kubectl get cluster -n "$NAMESPACE" "$cluster" -o jsonpath='{.status.currentPrimary}' 2>/dev/null || true)
        
        if [[ -z "$primary_pod" ]]; then
            warning "Could not determine primary pod for cluster '$cluster', skipping..."
            continue
        fi
        
        # Verify pod is running
        if kubectl get pod -n "$NAMESPACE" "$primary_pod" &> /dev/null; then
            add_cluster "$cluster" "$primary_pod" ""
            success "Found cluster '$cluster' with primary pod '$primary_pod'"
        else
            warning "Primary pod '$primary_pod' for cluster '$cluster' is not running, skipping..."
        fi
    done
    
    if [[ ${#CLUSTERS[@]} -eq 0 ]]; then
        error "No accessible clusters found with running primary pods"
        exit 1
    fi
}

# Function to discover databases in a cluster
discover_databases() {
    local cluster=$1
    local primary_pod=$(get_cluster_primary "$cluster")
    
    log "Discovering databases in cluster '$cluster'..."
    
    # Query PostgreSQL to get all databases excluding system databases
    local databases
    databases=$(kubectl exec -n "$NAMESPACE" "$primary_pod" -- psql -U postgres -t -c "
        SELECT datname FROM pg_database 
        WHERE datname NOT IN ('postgres', 'template0', 'template1') 
        AND datallowconn = true
        ORDER BY datname;" 2>/dev/null | tr -d ' ' | grep -v '^$' || true)
    
    # Update the databases for this cluster
    local index=$(get_cluster_index "$cluster")
    if [[ $index -ge 0 ]]; then
        CLUSTER_DATABASES[$index]="$databases"
        if [[ -n "$databases" ]]; then
            success "Found databases in '$cluster': $(echo "$databases" | tr '\n' ' ')"
        else
            warning "No user databases found in cluster '$cluster'"
        fi
    fi
}

# Function to get user preferences interactively
get_user_preferences() {
    echo -e "${BLUE}"
    echo "=========================================="
    echo "  PostgreSQL Backup Configuration"
    echo "=========================================="
    echo -e "${NC}"
    
    echo "Discovered clusters:"
    for i in "${!CLUSTERS[@]}"; do
        local cluster="${CLUSTERS[$i]}"
        local primary="${CLUSTER_PRIMARIES[$i]}"
        local db_list="${CLUSTER_DATABASES[$i]}"
        echo "  - $cluster (primary: $primary)"
        if [[ -n "$db_list" ]]; then
            echo "    Databases: $(echo "$db_list" | tr '\n' ', ' | sed 's/, $//')"
        else
            echo "    Databases: none"
        fi
    done
    echo ""
    
    # Ask about backup types
    echo "What types of backups would you like to create?"
    echo "1) Clean only (migration-friendly, no permissions)"
    echo "2) Full only (with all permissions and metadata)"
    echo "3) Both clean and full (recommended)"
    read -p "Enter your choice [1-3] (default: 3): " backup_type_choice
    backup_type_choice=${backup_type_choice:-3}
    
    # Ask about cluster backups
    echo ""
    read -p "Create full cluster backups (pg_dumpall) for disaster recovery? [Y/n]: " cluster_backup_choice
    cluster_backup_choice=${cluster_backup_choice:-Y}
    
    echo ""
    log "Configuration confirmed. Starting backup process..."
}

# Function to create directory structure
create_directories() {
    log "Creating backup directory structure..."
    
    mkdir -p "$BACKUP_DIR"
    
    # Create directories for each discovered cluster
    for cluster in "${CLUSTERS[@]}"; do
        mkdir -p "$BACKUP_DIR/$cluster"
        
        # Create subdirectories based on backup type choice
        case $backup_type_choice in
            1) mkdir -p "$BACKUP_DIR/$cluster/clean" ;;
            2) mkdir -p "$BACKUP_DIR/$cluster/full" ;;
            3) mkdir -p "$BACKUP_DIR/$cluster"/{clean,full} ;;
        esac
    done
    
    success "Created directory structure at: $BACKUP_DIR"
}

# Function to backup individual database (clean version)
backup_database_clean() {
    local cluster_primary=$1
    local database_name=$2
    local output_file=$3
    
    log "Creating clean backup of database '$database_name'..."
    
    kubectl exec -n "$NAMESPACE" "$cluster_primary" -- pg_dump \
        -U postgres \
        -d "$database_name" \
        --verbose \
        --clean \
        --no-acl \
        --no-owner \
        --no-privileges \
        --format=plain \
        > "$output_file"
    
    success "Clean backup completed: $(basename "$output_file")"
}

# Function to backup individual database (full version with all metadata)
backup_database_full() {
    local cluster_primary=$1
    local database_name=$2
    local output_file=$3
    
    log "Creating full backup of database '$database_name'..."
    
    kubectl exec -n "$NAMESPACE" "$cluster_primary" -- pg_dump \
        -U postgres \
        -d "$database_name" \
        --verbose \
        --clean \
        --format=plain \
        > "$output_file"
    
    success "Full backup completed: $(basename "$output_file")"
}

# Function to backup entire cluster
backup_cluster_full() {
    local cluster_primary=$1
    local output_file=$2
    
    log "Creating full cluster backup..."
    
    kubectl exec -n "$NAMESPACE" "$cluster_primary" -- pg_dumpall \
        -U postgres \
        --verbose \
        --clean \
        > "$output_file"
    
    success "Full cluster backup completed: $(basename "$output_file")"
}

# Function to backup a single cluster
backup_cluster() {
    local cluster=$1
    local primary_pod=$(get_cluster_primary "$cluster")
    local cluster_dir="$BACKUP_DIR/$cluster"
    local databases=$(get_cluster_databases "$cluster")
    
    log "Starting backup of cluster '$cluster'..."
    
    if [[ -z "$databases" ]]; then
        warning "No databases found in cluster '$cluster', skipping individual database backups"
    else
        # Backup individual databases
        while IFS= read -r database; do
            [[ -z "$database" ]] && continue
            
            # Clean backups
            if [[ $backup_type_choice -eq 1 || $backup_type_choice -eq 3 ]]; then
                backup_database_clean "$primary_pod" "$database" "$cluster_dir/clean/${database}_clean.sql"
            fi
            
            # Full backups
            if [[ $backup_type_choice -eq 2 || $backup_type_choice -eq 3 ]]; then
                backup_database_full "$primary_pod" "$database" "$cluster_dir/full/${database}_full.sql"
            fi
        done <<< "$databases"
    fi
    
    # Full cluster backup
    if [[ $cluster_backup_choice =~ ^[Yy] ]]; then
        backup_cluster_full "$primary_pod" "$cluster_dir/cluster_full.sql"
    fi
    
    success "Cluster '$cluster' backup completed"
}

# Function to backup all clusters
backup_all_clusters() {
    log "Starting backup of all clusters..."
    
    local cluster_pids=()
    
    # Start backup processes in parallel
    for cluster in "${CLUSTERS[@]}"; do
        backup_cluster "$cluster" &
        cluster_pids+=($!)
    done
    
    # Wait for all backup processes to complete
    for pid in "${cluster_pids[@]}"; do
        wait "$pid"
    done
    
    success "All cluster backups completed"
}

# Function to generate backup summary
generate_summary() {
    log "Generating backup summary..."
    
    local summary_file="$BACKUP_DIR/backup_summary.txt"
    
    cat > "$summary_file" << EOF
PostgreSQL Backup Summary
========================
Backup Date: $(date)
Backup Directory: $BACKUP_DIR

Cluster Information:
EOF
    
    # Add discovered cluster information
    for i in "${!CLUSTERS[@]}"; do
        local cluster="${CLUSTERS[$i]}"
        local primary="${CLUSTER_PRIMARIES[$i]}"
        local db_list="${CLUSTER_DATABASES[$i]}"
        echo "- $cluster primary: $primary" >> "$summary_file"
        if [[ -n "$db_list" ]]; then
            echo "  Databases: $(echo "$db_list" | tr '\n' ', ' | sed 's/, $//')" >> "$summary_file"
        else
            echo "  Databases: none" >> "$summary_file"
        fi
    done
    
    # Determine backup type description
    local backup_type_desc
    case $backup_type_choice in
        1) backup_type_desc="Clean only" ;;
        2) backup_type_desc="Full only" ;;
        3) backup_type_desc="Both clean and full" ;;
        *) backup_type_desc="Unknown" ;;
    esac
    
    # Determine cluster backup choice
    local cluster_backup_desc
    if [[ $cluster_backup_choice =~ ^[Yy] ]]; then
        cluster_backup_desc="Yes"
    else
        cluster_backup_desc="No"
    fi
    
    cat >> "$summary_file" << EOF

Backup Configuration:
- Backup Type: $backup_type_desc
- Cluster Backups: $cluster_backup_desc

File Structure:
EOF
    
    # Add directory tree
    tree "$BACKUP_DIR" >> "$summary_file" 2>/dev/null || find "$BACKUP_DIR" -type f | sort >> "$summary_file"
    
    # Add file sizes
    echo "" >> "$summary_file"
    echo "File Sizes:" >> "$summary_file"
    echo "===========" >> "$summary_file"
    find "$BACKUP_DIR" -name "*.sql" -exec ls -lh {} \; | awk '{print $5 " " $9}' >> "$summary_file"
    
    # Calculate total backup size
    local total_size=$(du -sh "$BACKUP_DIR" | cut -f1)
    echo "" >> "$summary_file"
    echo "Total Backup Size: $total_size" >> "$summary_file"
    
    success "Summary generated: backup_summary.txt"
}

# Main function
main() {
    echo -e "${GREEN}"
    echo "=================================="
    echo "  PostgreSQL CNPG Backup Script"
    echo "=================================="
    echo -e "${NC}"
    
    # Phase 1: Discovery and prerequisites
    check_prerequisites
    discover_clusters
    
    # Discover databases for each cluster
    for cluster in "${CLUSTERS[@]}"; do
        discover_databases "$cluster"
    done
    
    # Phase 2: Interactive configuration
    get_user_preferences
    
    # Phase 3: Execute backup
    create_directories
    backup_all_clusters
    generate_summary
    
    echo -e "${GREEN}"
    echo "=================================="
    echo "  Backup Process Completed!"
    echo "=================================="
    echo -e "${NC}"
    echo "Backup location: $BACKUP_DIR"
    echo "Summary: $BACKUP_DIR/backup_summary.txt"
    
    # Display final directory structure
    echo ""
    log "Final backup structure:"
    tree "$BACKUP_DIR" 2>/dev/null || find "$BACKUP_DIR" -type f | sort
}

# Trap to handle interruptions
trap 'error "Backup interrupted! Cleaning up..."; rm -rf "$BACKUP_DIR" 2>/dev/null; exit 1' INT TERM

# Run main function
main "$@"
