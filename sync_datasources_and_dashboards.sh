#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Variables
INSTANCE_A_URL="https://grafana-instance-a.com"
INSTANCE_B_URL="https://grafana-instance-b.com"
INSTANCE_A_API_KEY="INSTANCE_A_API_KEY"
INSTANCE_B_API_KEY="INSTANCE_B_API_KEY"

BACKUP_BRANCH_NAME="grafana_backup_$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="grafana_backup"

LOG_FILE="sync_log_$(date +%Y%m%d_%H%M%S).log"

# Ensure required tools are installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed. Please install jq." | tee -a "$LOG_FILE"
    exit 1
fi

if ! command -v git &> /dev/null; then
    echo "Error: git is not installed. Please install git." | tee -a "$LOG_FILE"
    exit 1
fi

# Function to log messages
log() {
    echo "$1" | tee -a "$LOG_FILE"
}

# Step 1: Fetch data sources from both instances
log "Fetching data sources from both instances..."

# Fetch data sources from Instance A
datasources_a=$(curl -s -H "Authorization: Bearer $INSTANCE_A_API_KEY" \
     -H "Content-Type: application/json" \
     "$INSTANCE_A_URL/api/datasources")

if [ -z "$datasources_a" ]; then
    log "Failed to fetch data sources from Instance A."
    exit 1
fi

# Fetch data sources from Instance B
datasources_b=$(curl -s -H "Authorization: Bearer $INSTANCE_B_API_KEY" \
     -H "Content-Type: application/json" \
     "$INSTANCE_B_URL/api/datasources")

if [ -z "$datasources_b" ]; then
    log "Failed to fetch data sources from Instance B."
    exit 1
fi

# Build mapping of data sources in Instance B based on type and URL
declare -A datasource_b_map

echo "$datasources_b" | jq -c '.[]' | while read -r ds_b; do
    ds_b_type=$(echo "$ds_b" | jq -r '.type')
    ds_b_url=$(echo "$ds_b" | jq -r '.url')
    ds_b_key="${ds_b_type}_${ds_b_url}"
    datasource_b_map["$ds_b_key"]="$ds_b"
done

# Step 2: Match and sync data sources from Instance A to Instance B
log "Matching and syncing data sources from Instance A to Instance B..."

echo "$datasources_a" | jq -c '.[]' | while read -r ds_a; do
    ds_a_type=$(echo "$ds_a" | jq -r '.type')
    ds_a_url=$(echo "$ds_a" | jq -r '.url')
    ds_a_name=$(echo "$ds_a" | jq -r '.name')
    ds_a_uid=$(echo "$ds_a" | jq -r '.uid')
    ds_a_id=$(echo "$ds_a" | jq -r '.id')
    ds_a_key="${ds_a_type}_${ds_a_url}"

    # Find matching data source in Instance B
    ds_b="${datasource_b_map[$ds_a_key]}"

    if [ -n "$ds_b" ]; then
        # Data source exists in Instance B, update UID, ID, and Name
        ds_b_id=$(echo "$ds_b" | jq -r '.id')
        ds_b_name=$(echo "$ds_b" | jq -r '.name')

        # Prepare updated data source object
        ds_b_updated=$(echo "$ds_b" | jq --arg uid "$ds_a_uid" --arg name "$ds_a_name" --arg id "$ds_a_id" \
            '.uid = $uid | .name = $name | .id = ($id | tonumber)')

        # Update data source in Instance B
        update_response=$(curl -s -X PUT -H "Authorization: Bearer $INSTANCE_B_API_KEY" \
            -H "Content-Type: application/json" \
            -d "$ds_b_updated" \
            "$INSTANCE_B_URL/api/datasources/$ds_b_id")

        if echo "$update_response" | jq -e '.id' > /dev/null; then
            log "Updated data source '$ds_a_name' in Instance B."
        else
            log "Failed to update data source '$ds_a_name' in Instance B. Response: $update_response"
        fi
    else
        # Data source does not exist in Instance B
        log "Data source '$ds_a_name' does not exist in Instance B. Creating it."

        # Remove id field before creating
        ds_a_create=$(echo "$ds_a" | jq 'del(.id)')

        # Create data source in Instance B
        create_response=$(curl -s -X POST -H "Authorization: Bearer $INSTANCE_B_API_KEY" \
            -H "Content-Type: application/json" \
            -d "$ds_a_create" \
            "$INSTANCE_B_URL/api/datasources")

        if echo "$create_response" | jq -e '.id' > /dev/null; then
            log "Created data source '$ds_a_name' in Instance B."
        else
            log "Failed to create data source '$ds_a_name' in Instance B. Response: $create_response"
        fi
    fi
done

# Step 3: Update dashboards in Instance B to reference updated data sources

# Fetch updated data sources from Instance B to get the new IDs and UIDs
datasources_b_updated=$(curl -s -H "Authorization: Bearer $INSTANCE_B_API_KEY" \
     -H "Content-Type: application/json" \
     "$INSTANCE_B_URL/api/datasources")

if [ -z "$datasources_b_updated" ]; then
    log "Failed to fetch updated data sources from Instance B."
    exit 1
fi

# Build a mapping of data source names to UIDs in Instance B
declare -A datasource_name_to_uid_map

echo "$datasources_b_updated" | jq -c '.[]' | while read -r ds; do
    ds_name=$(echo "$ds" | jq -r '.name')
    ds_uid=$(echo "$ds" | jq -r '.uid')
    datasource_name_to_uid_map["$ds_name"]="$ds_uid"
done

log "Fetching dashboards from Instance B..."

# Fetch all dashboards from Instance B
dashboards_b=$(curl -s -H "Authorization: Bearer $INSTANCE_B_API_KEY" \
     -H "Content-Type: application/json" \
     "$INSTANCE_B_URL/api/search?type=dash-db&limit=5000")

if [ -z "$dashboards_b" ]; then
    log "Failed to fetch dashboards from Instance B."
    exit 1
fi

# Step 4: Update dashboards in Instance B
log "Updating dashboards in Instance B to reference updated data sources..."

echo "$dashboards_b" | jq -c '.[]' | while read -r dashboard; do
    dashboard_uid=$(echo "$dashboard" | jq -r '.uid')
    dashboard_title=$(echo "$dashboard" | jq -r '.title')

    log "Processing dashboard '$dashboard_title' (UID: $dashboard_uid)..."

    # Fetch the dashboard JSON
    dashboard_json=$(curl -s -H "Authorization: Bearer $INSTANCE_B_API_KEY" \
        -H "Content-Type: application/json" \
        "$INSTANCE_B_URL/api/dashboards/uid/$dashboard_uid")

    if [ -z "$dashboard_json" ]; then
        log "Failed to fetch dashboard '$dashboard_title' (UID: $dashboard_uid). Continuing..."
        continue
    fi

    # Extract the dashboard object
    dashboard_obj=$(echo "$dashboard_json" | jq '.dashboard')

    # Find all data source references in the dashboard
    ds_names_in_dashboard=$(echo "$dashboard_obj" | jq -r '.. | objects | select(has("datasource")) | .datasource' | sort -u)

    # Update data source UIDs in the dashboard
    for ds_name in $ds_names_in_dashboard; do
        ds_uid="${datasource_name_to_uid_map[$ds_name]}"

        if [ -n "$ds_uid" ]; then
            # Replace data source UID in the dashboard JSON
            dashboard_obj=$(echo "$dashboard_obj" | jq --arg ds_name "$ds_name" --arg ds_uid "$ds_uid" \
                'walk(if type == "object" and has("datasource") and .datasource == $ds_name then .uid = $ds_uid else . end)')
        else
            log "Data source '$ds_name' not found in Instance B. Skipping replacement in dashboard '$dashboard_title'."
        fi
    done

    # Prepare the updated dashboard payload
    updated_dashboard_payload=$(jq -n --argjson dashboard "$dashboard_obj" '.dashboard = $dashboard | .overwrite = true')

    # Update the dashboard in Instance B
    update_response=$(curl -s -X POST -H "Authorization: Bearer $INSTANCE_B_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$updated_dashboard_payload" \
        "$INSTANCE_B_URL/api/dashboards/db")

    if echo "$update_response" | jq -e '.status' > /dev/null; then
        log "Updated dashboard '$dashboard_title' (UID: $dashboard_uid)."
    else
        log "Failed to update dashboard '$dashboard_title' (UID: $dashboard_uid). Response: $update_response"
    fi
done

# Step 5: Backup current state and create Git branch

log "Backing up current state and creating Git branch..."

mkdir -p "$BACKUP_DIR"

# Save data sources from Instance B
echo "$datasources_b_updated" > "$BACKUP_DIR/datasources_b.json"

# Save dashboards from Instance B
echo "$dashboards_b" | jq -r '.[].uid' | while read -r dashboard_uid; do
    dashboard_json=$(curl -s -H "Authorization: Bearer $INSTANCE_B_API_KEY" \
        -H "Content-Type: application/json" \
        "$INSTANCE_B_URL/api/dashboards/uid/$dashboard_uid")

    if [ -n "$dashboard_json" ]; then
        echo "$dashboard_json" > "$BACKUP_DIR/dashboard_$dashboard_uid.json"
    else
        log "Failed to backup dashboard UID: $dashboard_uid"
    fi
done

# Create Git branch and commit backups
git checkout -b "$BACKUP_BRANCH_NAME"
git add "$BACKUP_DIR"
git commit -m "Backup of Grafana Instance B after synchronization on $(date)"

log "Synchronization complete. Backup branch '$BACKUP_BRANCH_NAME' has been created."

