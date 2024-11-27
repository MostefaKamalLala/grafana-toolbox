#!/bin/bash

# Variables (Update these with your Grafana admin credentials and URL)
GRAFANA_URL="http://your-grafana-instance.com"
ADMIN_USER="admin"
ADMIN_PASSWORD="admin_password"

# Array of organization names to include or exclude
# Example: ORG_NAMES=("Main Org." "Development Team")
# Leave empty to include all organizations
ORG_NAMES=("Main Org." "Development Team")

# Set to "include" or "exclude"
FILTER_TYPE="include"

# Output format: "csv" or "json"
OUTPUT_FORMAT="csv"

# Output file name
OUTPUT_FILE="grafana_datasources.$OUTPUT_FORMAT"

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: 'jq' is not installed. Please install 'jq' to run this script."
    exit 1
fi

# Check if output format is valid
if [[ "$OUTPUT_FORMAT" != "csv" && "$OUTPUT_FORMAT" != "json" ]]; then
    echo "Error: OUTPUT_FORMAT must be 'csv' or 'json'."
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

# Convert ORG_NAMES array to a string for comparison
ORG_NAMES_STRING=$(printf "|%s" "${ORG_NAMES[@]}")
ORG_NAMES_STRING="${ORG_NAMES_STRING:1}" # Remove leading '|'

# Initialize data array for JSON output
data_array=()

# Initialize CSV output with header
if [ "$OUTPUT_FORMAT" == "csv" ]; then
    echo "Organization ID,Organization Name,Datasource ID,Datasource UID,Datasource Name,Datasource Type" > "$OUTPUT_FILE"
fi

# Iterate over each organization
echo "$orgs" | while IFS= read -r org; do
    org_id=$(echo "$org" | jq '.id')
    org_name=$(echo "$org" | jq -r '.name')

    # Determine whether to process this organization based on FILTER_TYPE
    if [ "${#ORG_NAMES[@]}" -eq 0 ]; then
        # No filtering, process all organizations
        process_org=true
    else
        # Check if org_name is in ORG_NAMES array
        if [[ "$ORG_NAMES_STRING" =~ (^|[|])"$org_name"($|[|]) ]]; then
            if [ "$FILTER_TYPE" == "include" ]; then
                process_org=true
            else
                process_org=false
            fi
        else
            if [ "$FILTER_TYPE" == "exclude" ]; then
                process_org=true
            else
                process_org=false
            fi
        fi
    fi

    if [ "$process_org" = true ]; then
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
            continue
        fi

        # Process data sources for this organization
        if [ -z "$datasources" ]; then
            echo "No data sources found for organization $org_name."
        else
            echo "Processing data sources for organization $org_name..."
            echo "$datasources" | while IFS= read -r ds; do
                ds_id=$(echo "$ds" | jq '.id')
                ds_uid=$(echo "$ds" | jq -r '.uid')
                ds_name=$(echo "$ds" | jq -r '.name')
                ds_type=$(echo "$ds" | jq -r '.type')

                if [ "$OUTPUT_FORMAT" == "csv" ]; then
                    # Append to CSV file
                    echo "\"$org_id\",\"$org_name\",\"$ds_id\",\"$ds_uid\",\"$ds_name\",\"$ds_type\"" >> "$OUTPUT_FILE"
                else
                    # Add to data array for JSON output
                    data_entry=$(jq -n \
                        --arg org_id "$org_id" \
                        --arg org_name "$org_name" \
                        --arg ds_id "$ds_id" \
                        --arg ds_uid "$ds_uid" \
                        --arg ds_name "$ds_name" \
                        --arg ds_type "$ds_type" \
                        '{organization_id: $org_id|tonumber, organization_name: $org_name, datasource_id: $ds_id|tonumber, datasource_uid: $ds_uid, datasource_name: $ds_name, datasource_type: $ds_type}')
                    data_array+=("$data_entry")
                fi
            done
        fi
    else
        echo "Skipping organization: $org_name"
    fi
done

# Write JSON output if selected
if [ "$OUTPUT_FORMAT" == "json" ]; then
    # Combine data entries into a JSON array
    printf '%s\n' "${data_array[@]}" | jq -s '.' > "$OUTPUT_FILE"
fi

echo "Data sources have been written to $OUTPUT_FILE."
