#!/bin/bash

# Variables
GRAFANA_URL="http://localhost:3000"    # Replace with your Grafana URL
ADMIN_USER="admin"                     # Grafana admin username
ADMIN_PASSWORD="your_admin_password"   # Grafana admin password
ORG_ID="1"                             # Target organization ID
SA_NAME="temp-wtf-serviceaccount"      # Name of the temporary service account
SA_ROLE="Viewer"                       # Role for the service account: Viewer|Editor|Admin
WTF_TEMP_TOKEN_NAME="wtf-temp-token"   # Name of the token for grafana-wtf
WTF_TEMP_TOKEN_ROLE="Viewer"           # Role for the token: Viewer|Editor|Admin

# Ensure dependencies
if ! command -v curl &> /dev/null || ! command -v jq &> /dev/null; then
  echo "Error: curl and jq must be installed."
  exit 1
fi

# Function to clean up the temporary service account
cleanup() {
  if [ -n "$SA_ID" ]; then
    echo "Deleting service account with ID: $SA_ID"
    DELETE_RESPONSE=$(curl -s -u "$ADMIN_USER:$ADMIN_PASSWORD" -X DELETE "$GRAFANA_URL/api/serviceaccounts/$SA_ID")
    if echo "$DELETE_RESPONSE" | grep -q '"message":"Service account deleted"'; then
      echo "Temporary service account deleted."
    else
      echo "Failed to delete service account. Response: $DELETE_RESPONSE"
    fi
  fi
}
trap cleanup EXIT

# 1. Switch to the target organization
echo "Switching to organization ID: $ORG_ID"
SWITCH_ORG_RESPONSE=$(curl -s -u "$ADMIN_USER:$ADMIN_PASSWORD" -X POST "$GRAFANA_URL/api/user/using/$ORG_ID")
if ! echo "$SWITCH_ORG_RESPONSE" | grep -q '"message":"Active organization changed"'; then
  echo "Failed to switch to organization ID $ORG_ID. Response: $SWITCH_ORG_RESPONSE"
  exit 1
fi

# 2. Create the temporary service account
CREATE_SA_PAYLOAD=$(cat <<EOF
{
  "name": "$SA_NAME",
  "role": "$SA_ROLE"
}
EOF
)

echo "Creating temporary service account: $SA_NAME"
CREATE_SA_RESPONSE=$(curl -s -u "$ADMIN_USER:$ADMIN_PASSWORD" -H "Content-Type: application/json" -X POST -d "$CREATE_SA_PAYLOAD" "$GRAFANA_URL/api/serviceaccounts")
SA_ID=$(echo "$CREATE_SA_RESPONSE" | jq -r '.id')

if [ "$SA_ID" == "null" ] || [ -z "$SA_ID" ]; then
  echo "Failed to create service account. Response: $CREATE_SA_RESPONSE"
  exit 1
fi

echo "Service account $SA_NAME created with ID: $SA_ID"

# 3. Generate a token (API key) for the service account
CREATE_TOKEN_PAYLOAD=$(cat <<EOF
{
  "name": "$WTF_TEMP_TOKEN_NAME",
  "role": "$WTF_TEMP_TOKEN_ROLE"
}
EOF
)

echo "Generating API token for service account ID: $SA_ID"
TOKEN_RESPONSE=$(curl -s -u "$ADMIN_USER:$ADMIN_PASSWORD" -H "Content-Type: application/json" -X POST -d "$CREATE_TOKEN_PAYLOAD" "$GRAFANA_URL/api/serviceaccounts/$SA_ID/keys")
WTF_API_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.key')

if [ "$WTF_API_TOKEN" == "null" ] || [ -z "$WTF_API_TOKEN" ]; then
  echo "Failed to generate API token for service account. Response: $TOKEN_RESPONSE"
  exit 1
fi

echo "Temporary service account API token generated."

# 4. Run grafana-wtf using the temporary token
export GRAFANA_URL=$GRAFANA_URL
export GRAFANA_TOKEN="Bearer $WTF_API_TOKEN"

echo "Running grafana-wtf..."
grafana-wtf

# Cleanup will run on exit, deleting the service account.
