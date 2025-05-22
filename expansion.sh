#!/bin/bash

# A script written to expand a volume as data is being written to it while monitoring the root volume capacity and including logging

# --- Configuration ---
LV_PATH="/dev/vg0/data0"        # Path to the Logical Volume
MOUNT_POINT="/data"             # Mount point of the LV
THRESHOLD_MB=1000               # Free space threshold for /data in MB
EXPAND_SIZE="500M"              # Size to expand by (e.g., 500M, 1G)
ROOT_USAGE_WARNING=90           # Root partition usage % to warn
ROOT_USAGE_CRITICAL=95          # Root partition usage % to HALT expansion
CHECK_INTERVAL_SECONDS=70        # How often to check (70 seconds)
LOG_FILE="/var/log/expansion_script.log"
# ---------------------

# --- Logging Function ---
log_message() {
    local TYPE="$1" # INFO, WARNING, ERROR, CRITICAL
    local MSG="$2"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$TYPE] $MSG" | tee -a "$LOG_FILE"
}
# ------------------------

# --- Initial Check for running instance ---
if pgrep -f "/usr/local/bin/expansion.sh" | grep -v "$$" > /dev/null; then
    exit 0 # Exit quietly if another instance is running
fi
# ------------------------------------------

log_message INFO "Starting LVM expansion monitoring for ${MOUNT_POINT}."

while true; do
    sleep "$CHECK_INTERVAL_SECONDS"
    log_message INFO "Checking disk space."

    # Get /data free space
    # Using 'df -m' for MB, awk to get 4th column (Available), NR==2 for data row
    AVAILABLE_MB=$(df -m "$MOUNT_POINT" | awk 'NR==2 {print $4}')
    if [[ -z "$AVAILABLE_MB" ]]; then
        log_message ERROR "Could not determine available space for $MOUNT_POINT. Check mount point or permissions. Skipping this cycle."
        continue
    fi
    sleep "$CHECK_INTERVAL_SECONDS"

    # Get root partition usage
    # Using 'df /' for root, awk to get 5th column (Use%), sed to remove %
    ROOT_PARTITION_USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [[ -z "$ROOT_PARTITION_USAGE" ]]; then
        log_message ERROR "Could not determine root partition usage. Skipping this cycle."
        continue
    fi
    sleep "$CHECK_INTERVAL_SECONDS"

    # Proceed with /data expansion check ONLY IF root is below critical
    if [ "$ROOT_PARTITION_USAGE" -lt "$ROOT_USAGE_CRITICAL" ]; then
        if [ "$AVAILABLE_MB" -lt "$THRESHOLD_MB" ]; then
            log_message INFO "Free space on ${MOUNT_POINT} is ${AVAILABLE_MB}MB, below threshold of ${THRESHOLD_MB}MB. Attempting to expand by $EXPAND_SIZE."

            # Extend Logical Volume
            /usr/sbin/lvextend -L+${EXPAND_SIZE} ${LV_PATH}
            /usr/sbin/resize2fs ${LV_PATH}
            log_message INFO "Successfully extended logical volume ${LV_PATH} by $EXPAND_SIZE."
        else
            log_message INFO "Free space on ${MOUNT_POINT} is ${AVAILABLE_MB}MB. No expansion needed."
        fi
    fi
    sleep "$CHECK_INTERVAL_SECONDS"
done