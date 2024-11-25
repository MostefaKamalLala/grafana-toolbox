#!/bin/bash

# Define an array of Grafana instances with their URLs and API keys
declare -A grafana_instances

# Example entries (replace with your actual Grafana instances and API keys)
grafana_instances["instance1"]="https://grafana-instance1.com|API_KEY_INSTANCE1"
grafana_instances["instance2"]="https://grafana-instance2.com|API_KEY_INSTANCE2"
grafana_instances["instance3"]="https://grafana-instance3.com|API_KEY_INSTANCE3"

# Output CSV file
output_file="grafana_datasources.csv"

# CSV Header
echo "Instance,Datasource ID,Datasource Name,Type,URL,Access,Database" > "$output_file"

# Iterate over each Grafana instance
for instance_name in "${!grafana_instances[@]}"; do
    IFS='|' read -r grafana_url api_key <<< "${grafana_instances[$instance_name]}"

    echo "Fetching data sources from $instance_name ($grafana_url)..."

    # Fetch data sources from Grafana API
    response=$(curl -s -H "Authorization: Bearer $api_key" -H "Content-Type: application/json" \
        "$grafana_url/api/datasources")

    # Check if the response is valid
    if [ -z "$response" ] || [[ "$response" == *"\"message\":"* ]]; then
        echo "Error fetching data sources from $instance_name. Response: $response"
        continue
    fi

    # Parse and output data sources to CSV
    echo "$response" | jq -r --arg instance "$instance_name" '.[] | [
        $instance,
        .id,
        .name,
        .type,
        .url,
        .access,
        .database // ""
    ] | @csv' >> "$output_file"

done

echo "Data sources have been written to $output_file"
