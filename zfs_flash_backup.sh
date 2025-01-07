#!/bin/bash

# Configuration
DATASET="docker_vm_nvme/system/flash_backup"  # ZFS dataset name
DESTINATION_POOL="zfs_backup/snapshots/docker_vm_nvme_system"       # ZFS destination pool and dataset
TAR_NAME="flash_$(date +%Y-%m-%d).tar"
SNAPSHOT_NAME="snapshot_$(date +%Y%m%d_%H%M%S)"  # Timestamp-based snapshot name

# Functions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

error_exit() {
    log "ERROR: $1"
    exit 1
}

# Ensure running as root
if [ "$(id -u)" -ne 0 ]; then
    error_exit "This script must be run as root!"
fi

# Create tarball of /boot directly in SOURCE_PATH
log "Creating tarball /mnt/${DATASET}/${TAR_NAME} from /boot..."
tar cvf "/mnt/${DATASET}/${TAR_NAME}" /boot || error_exit "Failed to create tarball."

# Create snapshot for the entire dataset
log "Creating snapshot ${SNAPSHOT_NAME} for ${DATASET}..."
zfs snapshot "${DATASET}@${SNAPSHOT_NAME}" || error_exit "Failed to create snapshot for dataset."

# Send dataset snapshot to destination
log "Sending dataset snapshot to ${DESTINATION_POOL}..."
zfs send "${DATASET}@${SNAPSHOT_NAME}" | zfs receive -F "${DESTINATION_POOL}/$(basename ${DATASET})" || error_exit "Failed to send dataset snapshot."

# Keep only the last 3 backups
log "Cleaning up old backups in ${DESTINATION_POOL}..."
zfs list -H -t snapshot -o name -s creation "${DESTINATION_POOL}/$(basename ${DATASET})" | \
    grep -E "${DESTINATION_POOL}/$(basename ${DATASET})@.*" | \
    head -n -3 | while read -r SNAP; do
    log "Removing old snapshot: ${SNAP}"
    zfs destroy "${SNAP}" || error_exit "Failed to remove old snapshot ${SNAP}."
done

log "Dataset snapshot successfully sent to ${DESTINATION_POOL}."
