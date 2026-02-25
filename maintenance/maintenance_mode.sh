#!/bin/bash
# maintenance_mode.sh - Enable or disable Grocy maintenance mode via nginx flag file
# Usage: ./maintenance_mode.sh [on|off|status]

FLAG_FILE="/srv/maintenance/enable_maintenance"
MAINTENANCE_HTML="/srv/maintenance/maintenance.html"

function enable_maintenance() {
    sudo mkdir -p "$(dirname "$FLAG_FILE")"
    sudo touch "$FLAG_FILE"
    echo "[INFO] Maintenance mode ENABLED. (Flag: $FLAG_FILE)"
        echo "[INFO] Reloading nginx to apply maintenance mode..."
        sudo nginx -s reload || sudo systemctl reload nginx || echo "[WARN] nginx reload failed; please reload manually."
}

function disable_maintenance() {
    sudo rm -f "$FLAG_FILE"
    echo "[INFO] Maintenance mode DISABLED. (Flag: $FLAG_FILE)"
        echo "[INFO] Reloading nginx to disable maintenance mode..."
        sudo nginx -s reload || sudo systemctl reload nginx || echo "[WARN] nginx reload failed; please reload manually."
}

function status_maintenance() {
    if [ -f "$FLAG_FILE" ]; then
        echo "[STATUS] Maintenance mode is ENABLED. (Flag: $FLAG_FILE)"
    else
        echo "[STATUS] Maintenance mode is DISABLED. (Flag: $FLAG_FILE)"
    fi
}

case "$1" in
    on)
        enable_maintenance
        ;;
    off)
        disable_maintenance
        ;;
    status)
        status_maintenance
        ;;
    *)
        echo "Usage: $0 [on|off|status]"
        exit 1
        ;;
esac
