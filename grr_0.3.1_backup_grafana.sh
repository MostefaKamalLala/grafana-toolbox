#!/bin/bash

# Variables
GRAFANA_URL="https://your-grafana-instance.com"
ADMIN_USER="admin"
ADMIN_PASSWORD="your_admin_password"

# Create backup directory
BACKUP_DIR="backup"
mkdir -p "${BACKUP_DIR}"

# Get list of all organizations
ORG_LIST=$(curl -s -u "${ADMIN_USER}:${ADMIN_PASSWORD}" "${GRAFANA_URL}/api/orgs")

# Extract organization IDs
ORG_IDS=$(echo "${ORG_LIST}" | jq -r '.[].id')

# Loop through each organization
for ORG_ID in ${ORG_IDS}; do
    echo "Processing Organization ID: ${ORG_ID}"

    # Switch to the organization
    SWITCH_ORG=$(curl -s -X POST -u "${ADMIN_USER}:${ADMIN_PASSWORD}" "${GRAFANA_URL}/api/user/using/${ORG_ID}")
    if [[ $(echo "${SWITCH_ORG}" | jq -r '.message') != "Active organization changed" ]]; then
        echo "Failed to switch to organization ${ORG_ID}"
        continue
    fi

    # Create organization backup directory
    ORG_BACKUP_DIR="${BACKUP_DIR}/org_${ORG_ID}"
    mkdir -p "${ORG_BACKUP_DIR}"

    # Export datasources
    grr export resources/datasources > "${ORG_BACKUP_DIR}/datasources.yaml"

    # Export folders
    grr export resources/folders > "${ORG_BACKUP_DIR}/folders.yaml"

    # Export dashboards
    grr export resources/dashboards > "${ORG_BACKUP_DIR}/dashboards.yaml"

    echo "Backup completed for Organization ID: ${ORG_ID}"
done

echo "Backup process completed."