#!/bin/bash
# Detects the local primary IPv4 address (Linux/macOS)
export LOCAL_IP=$(hostname -I | awk '{print $1}')

# Write it to the .env file for Docker Compose
echo "LOCAL_IP=$LOCAL_IP" > .env

# Start your containers
docker compose up -d --build
