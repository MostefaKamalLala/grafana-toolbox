#!/bin/bash

# Variables
GRAFANA_URL="https://your-grafana-instance.com"
ADMIN_USER="admin"
ADMIN_PASSWORD="your_admin_password"

# Base64 encode the admin credentials for basic auth
AUTH_HEADER="Authorization: Basic $(echo -n "${ADMIN_USER}:${ADMIN_PASSWORD}" | base64)"

# Backup directory
BACKUP_DIR="backup"

# Check if backup directory exists
if [ ! -d "${BACKUP_DIR}" ]; then
    echo "Backup directory '${BACKUP_DIR}' not found!"
    exit 1
fi

# Loop through each organization backup directory
for ORG_BACKUP_DIR in ${BACKUP_DIR}/org_*; do
    ORG_ID=$(basename "${ORG_BACKUP_DIR}" | cut -d'_' -f2)
    echo "Restoring Organization ID: ${ORG_ID}"

    # Switch to the organization
    SWITCH_ORG=$(curl -s -X POST -H "${AUTH_HEADER}" "${GRAFANA_URL}/api/user/using/${ORG_ID}")
    if [[ $(echo "${SWITCH_ORG}" | jq -r '.message') != "Active organization changed" ]]; then
        echo "Failed to switch to organization ${ORG_ID}"
        continue
    fi

    # Restore datasources
    if [ -f "${ORG_BACKUP_DIR}/datasources.yaml" ]; then
        grr apply \
            --url "${GRAFANA_URL}" \
            --headers "${AUTH_HEADER}" \
            "${ORG_BACKUP_DIR}/datasources.yaml"
    fi

    # Restore folders
    if [ -f "${ORG_BACKUP_DIR}/folders.yaml" ]; then
        grr apply \
            --url "${GRAFANA_URL}" \
            --headers "${AUTH_HEADER}" \
            "${ORG_BACKUP_DIR}/folders.yaml"
    fi

    # Restore dashboards
    if [ -f "${ORG_BACKUP_DIR}/dashboards.yaml" ]; then
        grr apply \
            --url "${GRAFANA_URL}" \
            --headers "${AUTH_HEADER}" \
            "${ORG_BACKUP_DIR}/dashboards.yaml"
    fi

    echo "Restore completed for Organization ID: ${ORG_ID}"
done

echo "Restore process completed."
