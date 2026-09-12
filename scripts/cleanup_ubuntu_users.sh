#!/bin/bash

# Check if the script is being run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root or with sudo."
  exit 1
fi

# Prompt for the total number of users to remove
read -p "Enter the maximum user number to delete (e.g., 5 to clean up user01 through user05): " USER_COUNT

# Validate that the input is a positive integer
if ! [[ "$USER_COUNT" =~ ^[0-9]+$ ]] || [ "$USER_COUNT" -le 0 ]; then
  echo "Error: Please enter a valid positive number."
  exit 1
fi

echo "----------------------------------------------------"
echo "WARNING: This will permanently delete user01 to user$(printf "%02d" $USER_COUNT)"
echo "and completely erase all files in their home directories."
echo "----------------------------------------------------"
read -p "Are you absolutely sure you want to proceed? (y/N): " CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Cleanup cancelled."
    exit 0
fi

# Loop to remove users
for i in $(seq -f "%02g" 1 "$USER_COUNT"); do
    USERNAME="user$i"
    
    # Check if user actually exists
    if ! id "$USERNAME" &>/dev/null; then
        echo "User $USERNAME does not exist. Skipping..."
    else
        echo "Processing cleanup for $USERNAME..."
        
        # 1. Forcefully kill any active sessions or background processes for the user
        # (Crucial if students are still connected via SSH or terminal sessions)
        pkill -u "$USERNAME" -9 &>/dev/null
        killall -u "$USERNAME" -9 &>/dev/null
        
        # 2. Delete the user and recursively wipe out their home directory (-r)
        if userdel -r "$USERNAME" 2>/dev/null; then
            echo "Successfully removed $USERNAME and their home directory."
        else
            # Fallback handling if a process was locking the userdel command
            sleep 1
            userdel -f -r "$USERNAME" 2>/dev/null
            echo "Forcefully removed $USERNAME."
        fi
    fi
done

echo "Done! Cleanup completed up to user$(printf "%02d" $USER_COUNT)."

