#!/bin/bash

# Variables
GRAFANA_URL="http://localhost:3000"  # Replace with your Grafana URL
ADMIN_USER="admin"
ADMIN_PASSWORD="your_admin_password"
ORG_ID="1"  # Replace with the target organization ID
TEMP_USER="temp-wtf-user"
TEMP_USER_EMAIL="temp-wtf@example.com"
TEMP_USER_PASSWORD=$(openssl rand -base64 12)  # Generate a random password
WTF_TEMP_TOKEN_NAME="grafana-wtf-temp-token"

# Dependencies check
if ! command -v curl &> /dev/null || ! command -v jq &> /dev/null; then
  echo "Error: curl and jq must be installed."
  exit 1
fi

# Function to clean up the temporary user
function cleanup() {
  echo "Cleaning up..."
  USER_ID=$(curl -s -u "$ADMIN_USER:$ADMIN_PASSWORD" "$GRAFANA_URL/api/org/users" | jq ".[] | select(.login==\"$TEMP_USER\") | .userId")
  if [ -n "$USER_ID" ]; then
    curl -s -u "$ADMIN_USER:$ADMIN_PASSWORD" -X DELETE "$GRAFANA_URL/api/admin/users/$USER_ID"
    echo "Temporary user $TEMP_USER deleted."
  fi
}

# Trap cleanup on exit
trap cleanup EXIT

# Step 1: Switch to the target organization
echo "Switching to organization ID: $ORG_ID"
SWITCH_ORG_RESPONSE=$(curl -s -u "$ADMIN_USER:$ADMIN_PASSWORD" -X POST "$GRAFANA_URL/api/user/using/$ORG_ID")
if ! echo "$SWITCH_ORG_RESPONSE" | grep -q '"message":"Active organization changed"'; then
  echo "Failed to switch to organization ID $ORG_ID. Response: $SWITCH_ORG_RESPONSE"
  exit 1
fi

# Step 2: Create a temporary user
echo "Creating temporary user: $TEMP_USER"
CREATE_USER_PAYLOAD=$(cat <<EOF
{
  "name": "$TEMP_USER",
  "email": "$TEMP_USER_EMAIL",
  "login": "$TEMP_USER",
  "password": "$TEMP_USER_PASSWORD"
}
EOF
)
CREATE_USER_RESPONSE=$(curl -s -u "$ADMIN_USER:$ADMIN_PASSWORD" -H "Content-Type: application/json" -X POST -d "$CREATE_USER_PAYLOAD" "$GRAFANA_URL/api/admin/users")
TEMP_USER_ID=$(echo "$CREATE_USER_RESPONSE" | jq -r '.id')

if [ "$TEMP_USER_ID" == "null" ] || [ -z "$TEMP_USER_ID" ]; then
  echo "Failed to create temporary user. Response: $CREATE_USER_RESPONSE"
  exit 1
fi

# Step 3: Add the temporary user to the organization
echo "Adding user $TEMP_USER to organization ID $ORG_ID with Viewer role"
ADD_USER_PAYLOAD=$(cat <<EOF
{
  "loginOrEmail": "$TEMP_USER",
  "role": "Viewer"
}
EOF
)
ADD_USER_RESPONSE=$(curl -s -u "$ADMIN_USER:$ADMIN_PASSWORD" -H "Content-Type: application/json" -X POST -d "$ADD_USER_PAYLOAD" "$GRAFANA_URL/api/orgs/$ORG_ID/users")
if ! echo "$ADD_USER_RESPONSE" | grep -q '"message":"User added to organization"'; then
  echo "Failed to add user to organization. Response: $ADD_USER_RESPONSE"
  exit 1
fi

# Step 4: Generate a token for the temporary user
echo "Generating API token for temporary user"
TOKEN_RESPONSE=$(curl -s -u "$TEMP_USER:$TEMP_USER_PASSWORD" -H "Content-Type: application/json" -X POST -d "{\"name\":\"$WTF_TEMP_TOKEN_NAME\",\"role\":\"Viewer\"}" "$GRAFANA_URL/api/auth/keys")
WTF_API_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.key')

if [ "$WTF_API_TOKEN" == "null" ] || [ -z "$WTF_API_TOKEN" ]; then
  echo "Failed to generate API token for user $TEMP_USER. Response: $TOKEN_RESPONSE"
  exit 1
fi

# Step 5: Run grafana-wtf using the temporary token
export GRAFANA_URL=$GRAFANA_URL
export GRAFANA_TOKEN="Bearer $WTF_API_TOKEN"

echo "Running grafana-wtf..."
grafana-wtf

# Step 6: Clean up (optional)
cleanup
