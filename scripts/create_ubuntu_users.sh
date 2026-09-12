#!/bin/bash

# Check if the script is being run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root or with sudo."
  exit 1
fi

# Define the source template file
TEMPLATE_FILE="./custom_bashrc.tmpl"

# Verify that your custom template file actually exists before starting
if [ ! -f "$TEMPLATE_FILE" ]; then
  echo "Error: Custom template file '$TEMPLATE_FILE' not found!"
  echo "Please create this file in the same directory before running the script."
  exit 1
fi

# Prompt for the total number of users
read -p "Enter the number of users to create (e.g., 5 for user01 to user05): " USER_COUNT

# Validate that the input is a positive integer
if ! [[ "$USER_COUNT" =~ ^[0-9]+$ ]] || [ "$USER_COUNT" -le 0 ]; then
  echo "Error: Please enter a valid positive number."
  exit 1
fi

# Prompt for the shared password
#read -s -p "Enter the shared password for all users: " PASSWORD
#echo "" # Move to a new line after hidden password input

PASSWORD="user123"

# Loop to create users
for i in $(seq -f "%02g" 1 "$USER_COUNT"); do
    USERNAME="user$i"
    USER_HOME="/home/$USERNAME"
    
    # Check if user already exists
    if id "$USERNAME" &>/dev/null; then
        echo "User $USERNAME already exists. Skipping..."
    else
        # Create user with a home directory and default bash shell
        useradd -m -s /bin/bash "$USERNAME"
        
	# ADD USER TO SUDO GROUP (For Ubuntu/Debian use 'sudo', for Alpine/CentOS use 'wheel')
        usermod -aG sudo "$USERNAME"

        # Set the shared password
        echo "$USERNAME:$PASSWORD" | chpasswd
        
        # -------------------------------------------------------------
        # COPY CUSTOM BASHRC FILE
        # -------------------------------------------------------------
        # Copy the external custom template to the user's home folder
        cp "$TEMPLATE_FILE" "$USER_HOME/.bashrc"
        
        # Optional: Dynamically append something unique if needed
        # echo "export USER_ID='$USERNAME'" >> "$USER_HOME/.bashrc"
        
        # Fix file ownership and permissions so the user owns it
        chown "$USERNAME:$USERNAME" "$USER_HOME/.bashrc"
        chmod 644 "$USER_HOME/.bashrc"
        # -------------------------------------------------------------
        
        echo "User $USERNAME created successfully with custom .bashrc file."
    fi
done

echo "Done! Created users up to user$USER_COUNT."

