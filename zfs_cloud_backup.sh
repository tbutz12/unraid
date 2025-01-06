#!/bin/bash

# Enable error handling and set error trap
set -e
trap 'echo "[ERROR] Error occurred at line $LINENO while executing command: $BASH_COMMAND"' ERR

# Variables
POOL="/mnt/zfs_backup"                     # Replace with your ZFS pool name
DATASET="snapshots"                        # Replace with your dataset name
SNAPSHOT_DIR="${POOL}/${DATASET}"          # Directory for storing backups
REMOTE="/mnt/remotes/OMEGA.TB.SERVER_google/My\ Drive/unRAID\ Backups/snapshots" # Google Drive remote path

# Function to log command execution
execute_command() {
    local COMMAND="$1"
    echo "[INFO] Executing: $COMMAND"
    eval "$COMMAND"
}

for dir in "$SNAPSHOT_DIR" "$REMOTE"; do
    if [ ! -d "$dir" ]; then
        echo "[ERROR] Directory '$dir' does not exist, please ensure variables are set correctly."
        exit 1
    fi
done

# Fetch snapshots for the dataset
SNAPSHOTS=$(zfs list -t snapshot -H -o name -s creation | grep "^zfs_backup/snapshots")
if [ -n "$SNAPSHOTS" ]; then
    echo "[INFO] Snapshots for dataset '$DATASET':"
    echo "$SNAPSHOTS"
else
    echo "[ERROR] No snapshots found for dataset '$DATASET'"
    exit 1
fi

# Extract unique datasets from snapshots
DATASETS=$(echo "$SNAPSHOTS" | awk -F'@' '{print $1}' | sort | uniq)

for DATASET in $DATASETS; do
    # Find the latest two snapshots for the current dataset
    LATEST_SNAPSHOTS=$(echo "$SNAPSHOTS" | grep "^${DATASET}@" | tail -n 2)

    if [ -n "$LATEST_SNAPSHOTS" ]; then
        echo "[INFO] Latest two snapshots for dataset '$DATASET':"
        echo "$LATEST_SNAPSHOTS"

        for SNAPSHOT in $LATEST_SNAPSHOTS; do
            # Sanitize snapshot name for file path
            SANITIZED_SNAPSHOT=$(echo ${SNAPSHOT} | sed 's|/|_|g')
            BACKUP_FILE="${SNAPSHOT_DIR}/${SANITIZED_SNAPSHOT}.gz"

            # Ensure the directory exists
            mkdir -p "$(dirname ${BACKUP_FILE})"

            # Export and compress the snapshot
            echo "[INFO] Exporting and compressing snapshot: ${SNAPSHOT}..."
            execute_command "zfs send ${SNAPSHOT} | gzip > ${BACKUP_FILE}"

            # Upload the backup to Google Drive
            echo "[INFO] Uploading ${SANITIZED_SNAPSHOT}.gz to Google Drive..."
            echo "TEST"
            echo ${BACKUP_FILE} ${REMOTE}
            execute_command "rclone copy ${BACKUP_FILE} ${REMOTE}"

            # Clean up the local backup file
            echo "[INFO] Cleaning up local backup file: ${BACKUP_FILE}..."
            execute_command "rm ${BACKUP_FILE}"
        done
        
        # Clean up older backups on Google Drive, keeping only the latest two
        REMOTE_FILES=$(rclone lsjson "${REMOTE}" --files-only | jq -r '.[].Name' | grep "^${DATASET}@" | sort | head -n -2)
        
        if [ -n "$REMOTE_FILES" ]; then
            echo "[INFO] Deleting older backups on Google Drive for dataset '$DATASET':"
            echo "$REMOTE_FILES"
        
            while IFS= read -r OLD_REMOTE_FILE; do
                echo "[INFO] Deleting: $OLD_REMOTE_FILE"
                rclone delete "${REMOTE}/${OLD_REMOTE_FILE}" || echo "[ERROR] Failed to delete ${OLD_REMOTE_FILE}"
            done <<< "$REMOTE_FILES"
        else
            echo "[INFO] No older backups to delete for dataset '$DATASET'."
        fi

    else
        echo "[ERROR] Failed to find the latest snapshots for dataset '$DATASET'"
    fi
done

echo "[INFO] Latest two snapshots for datasets in ${POOL}/${DATASET} have been backed up to Google Drive and older backups have been cleaned up!"
