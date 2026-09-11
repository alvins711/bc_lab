#!/bin/bash

# ==========================================
# CONFIGURATION - MUST MATCH THE CREATION SCRIPT
# ==========================================
GUAC_URL="http://192.168.68.102:8081/guacamole"
ADMIN_USER="guacadmin"
ADMIN_PASS="guacadmin"

# Base User Configuration to match
USER_PREFIX="user"     

# Connection Name to target for deletion
CONN_NAME="Shared Server Auto-Login"

# ==========================================
# PROMPT USER FOR COUNT
# ==========================================
echo "============================================="
echo "  Apache Guacamole Automated Cleanup Tool    "
echo "============================================="
echo ""

while true; do
    read -p "How many sequential users do you need to remove? (e.g., 10): " USER_COUNT
    if [[ "$USER_COUNT" =~ ^[0-9]+$ ]] && [ "$USER_COUNT" -gt 0 ]; then
        break
    else
        echo "❌ Invalid input. Please enter a valid positive integer."
    fi
done

echo ""
echo "🧹 Preparing to delete $USER_COUNT users and the connection '${CONN_NAME}'..."
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
echo "------------------------------------------------"

# ==========================================
# 2. BULK USER DELETION LOOP
# ==========================================
echo "Starting removal of ${USER_COUNT} users..."

for ((i=1; i<=USER_COUNT; i++)); do
    # Match the dynamic zero padding scale from the creation script
    if [ "$USER_COUNT" -lt 100 ]; then
        printf -v USER_NUM "%02d" $i
    else
        printf -v USER_NUM "%03d" $i
    fi
    
    CURRENT_USER="${USER_PREFIX}${USER_NUM}"
    
    echo "Processing [${CURRENT_USER}]..."

    # Issue HTTP DELETE to remove the user resource profile
    USER_RESPONSE=$(curl -s -X DELETE "${GUAC_URL}/api/session/data/${DATA_SOURCE}/users/${CURRENT_USER}?token=${AUTH_TOKEN}")

    if [[ "$USER_RESPONSE" == *"NOT_FOUND"* ]]; then
        echo "   ⚠️ User not found. Skipping."
    elif [[ -n "$USER_RESPONSE" ]]; then
        echo "   ❌ Failed to remove user. Response: $USER_RESPONSE"
    else
        echo "   ✅ User successfully removed."
    fi
done

echo "------------------------------------------------"

# ==========================================
# 3. LOCATE & REMOVE THE TARGET CONNECTION
# ==========================================
echo "Searching for connection identifier for '${CONN_NAME}'..."

# Retrieve all connections to find the match
ALL_CONN_RESPONSE=$(curl -s -X GET "${GUAC_URL}/api/session/data/${DATA_SOURCE}/connections?token=${AUTH_TOKEN}")

# Extract the identifier based on the precise connection name layout
CONN_ID=$(echo "$ALL_CONN_RESPONSE" | grep -o "\"name\":\"${CONN_NAME}\",\"identifier\":\"[^\"]*" | grep -o '[^"]*$')

if [ -z "$CONN_ID" ]; then
    echo "⚠️ Connection '${CONN_NAME}' not found or already deleted."
else
    echo "Found connection identifier: ${CONN_ID}"
    echo "Deleting connection..."
    
    # Issue HTTP DELETE to drop the connection tree
    CONN_DELETE_RESPONSE=$(curl -s -X DELETE "${GUAC_URL}/api/session/data/${DATA_SOURCE}/connections/${CONN_ID}?token=${AUTH_TOKEN}")
    
    if [[ -n "$CONN_DELETE_RESPONSE" ]]; then
        echo "❌ Failed to delete connection. Response: $CONN_DELETE_RESPONSE"
    else
        echo "✅ Connection '${CONN_NAME}' successfully removed."
    fi
fi

echo "------------------------------------------------"
echo "🎉 Cleanup process completed!"

