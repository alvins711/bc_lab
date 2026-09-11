#!/bin/bash

# ==========================================
# CONFIGURATION - UPDATE THESE FOR YOUR ENV
# ==========================================
GUAC_URL="http://localhost:8081/guacamole"
ADMIN_USER="guacadmin"
ADMIN_PASS="guacadmin"

# Bulk User Configuration
USER_PREFIX="user"     
#USER_COUNT=2          
SHARED_PASSWORD="user123"

# Connection Details to create
CONN_NAME="Shared Server Auto-Login"
CONN_PROTOCOL="ssh"
CONN_HOST="claude_workspace"
CONN_PORT="22"

# ==========================================
# PROMPT USER FOR COUNT
# ==========================================
echo "============================================="
echo "  Apache Guacamole Bulk User Provisioning    "
echo "============================================="
echo ""

while true; do
    read -p "How many users would you like to create? (e.g., 10): " USER_COUNT
    # Validate that the input is a positive number
    if [[ "$USER_COUNT" =~ ^[0-9]+$ ]] && [ "$USER_COUNT" -gt 0 ]; then
        break
    else
        echo "❌ Invalid input. Please enter a valid positive integer."
    fi
done

echo ""
echo "🚀 Preparing to create $USER_COUNT users (${USER_PREFIX}01 to ${USER_PREFIX}$(printf "%02d" $USER_COUNT))..."
echo "------------------------------------------------"

# ==========================================
# 1. AUTHENTICATE & GET TOKEN
# ==========================================
echo "Authenticating admin user..."

AUTH_RESPONSE=$(curl -s -X POST "${GUAC_URL}/api/tokens" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "username=${ADMIN_USER}" \
  --data-urlencode "password=${ADMIN_PASS}")

AUTH_TOKEN=$(echo "$AUTH_RESPONSE" | grep -o '"authToken":"[^"]*' | grep -o '[^"]*$')
DATA_SOURCE=$(echo "$AUTH_RESPONSE" | grep -o '"dataSource":"[^"]*' | grep -o '[^"]*$')

if [ -z "$AUTH_TOKEN" ]; then
    echo "❌ Authentication failed! Response was:"
    echo "$AUTH_RESPONSE"
    exit 1
fi

echo "✅ Authenticated successfully. Detected Data Source: ${DATA_SOURCE}"

# ==========================================
# 2. CREATE THE AUTO-INJECT CONNECTION
# ==========================================
echo "Creating target connection '${CONN_NAME}'..."

# NOTE: The username and password fields use escaped backslashes (\$GUAC...) 
# to prevent Bash from interpreting them locally. Guacamole handles the injection.
CONN_PAYLOAD=$(cat <<EOF
{
    "parentIdentifier": "ROOT",
    "name": "${CONN_NAME}",
    "protocol": "${CONN_PROTOCOL}",
    "attributes": {
        "max-connections": "",
        "max-connections-per-user": "",
        "weight": "",
        "failover-only": "",
        "guacd-port": "",
        "guacd-encryption": "",
        "guacd-hostname": ""
    },
    "parameters": {
        "hostname": "${CONN_HOST}",
        "port": "${CONN_PORT}",
        "username": "\${GUAC_USERNAME}",
        "password": "\${GUAC_PASSWORD}"
    }
}
EOF
)

CONN_RESPONSE=$(curl -s -X POST "${GUAC_URL}/api/session/data/${DATA_SOURCE}/connections?token=${AUTH_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$CONN_PAYLOAD")

CONN_ID=$(echo "$CONN_RESPONSE" | grep -o '"identifier":"[^"]*' | grep -o '[^"]*$')

if [ -z "$CONN_ID" ]; then
    echo "❌ Failed to create connection! Response:"
    echo "$CONN_RESPONSE"
    exit 1
fi

echo "✅ Connection created with ID: ${CONN_ID}"
echo "------------------------------------------------"

# ==========================================
# 3. BULK USER CREATION LOOP
# ==========================================
echo "Starting creation of ${USER_COUNT} users..."

for ((i=1; i<=USER_COUNT; i++)); do
    printf -v USER_NUM "%02d" $i
    CURRENT_USER="${USER_PREFIX}${USER_NUM}"
    
    echo "Processing [${CURRENT_USER}]..."

    USER_PAYLOAD=$(cat <<EOF
{
    "username": "${CURRENT_USER}",
    "password": "${SHARED_PASSWORD}",
    "attributes": {
        "disabled": "",
        "expired": "",
        "access-window-start": "",
        "access-window-end": "",
        "valid-from": "",
        "valid-until": "",
        "timezone": ""
    }
}
EOF
)

    USER_RESPONSE=$(curl -s -X POST "${GUAC_URL}/api/session/data/${DATA_SOURCE}/users?token=${AUTH_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "$USER_PAYLOAD")

    if [[ "$USER_RESPONSE" == *"ALREADY_EXISTS"* ]]; then
        echo "   ⚠️ User already exists. Skipping profile creation, moving to permissions..."
    elif [[ "$USER_RESPONSE" == *"INVALID_CREDENTIALS"* || "$USER_RESPONSE" == *"NOT_FOUND"* || "$USER_RESPONSE" == *"INTERNAL_ERROR"* ]]; then
        echo "   ❌ Failed to create user profile. Response: $USER_RESPONSE"
        continue
    else
        echo "   ✅ Profile created."
    fi

    # Assign connection read access to this specific user
    PERM_PAYLOAD=$(cat <<EOF
[
    {
        "op": "add",
        "path": "/connectionPermissions/${CONN_ID}",
        "value": "READ"
    }
]
EOF
)

    PERM_RESPONSE=$(curl -s -X PATCH "${GUAC_URL}/api/session/data/${DATA_SOURCE}/users/${CURRENT_USER}/permissions?token=${AUTH_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "$PERM_PAYLOAD")

    echo "   ✅ Connection permission linked."
done

echo "------------------------------------------------"
echo "🎉 Bulk user provisioning successfully complete!"

