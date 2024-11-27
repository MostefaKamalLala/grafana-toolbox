#!/bin/bash

# Variables (Update these with your Grafana admin credentials and URL)
GRAFANA_URL="http://your-grafana-instance.com"
ADMIN_USER="admin"
ADMIN_PASSWORD="admin_password"

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: 'jq' is not installed. Please install 'jq' to run this script."
    exit 1
fi

# Fetch the list of organizations
orgs_response=$(curl -s -u "$ADMIN_USER:$ADMIN_PASSWORD" \
    "$GRAFANA_URL/api/orgs")

# Check for errors in the orgs_response
if echo "$orgs_response" | jq empty 2>/dev/null; then
    orgs=$(echo "$orgs_response" | jq -c '.[]')
else
    echo "Error fetching organizations. Response:"
    echo "$orgs_response"
    exit 1
fi

# Iterate over each organization
echo "$orgs" | while IFS= read -r org; do
    org_id=$(echo "$org" | jq '.id')
    org_name=$(echo "$org" | jq -r '.name')
    echo "Organization ID: $org_id, Name: $org_name"

    # Fetch data sources for this organization
    datasources_response=$(curl -s -u "$ADMIN_USER:$ADMIN_PASSWORD" \
        -H "X-Grafana-Org-Id: $org_id" \
        "$GRAFANA_URL/api/datasources")

    # Check for errors in the datasources_response
    if echo "$datasources_response" | jq empty 2>/dev/null; then
        datasources=$(echo "$datasources_response" | jq -c '.[]')
    else
        echo "Error fetching data sources for organization $org_name. Response:"
        echo "$datasources_response"
        echo "-------------------------------------------"
        continue
    fi

    # List data sources for this organization
    if [ -z "$datasources" ]; then
        echo "No data sources found for organization $org_name."
    else
        echo "Data sources for organization $org_name:"
        echo "$datasources" | jq '. | {id: .id, uid: .uid, name: .name, type: .type}'
    fi

    echo "-------------------------------------------"

done
