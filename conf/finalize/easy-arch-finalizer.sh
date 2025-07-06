#!/bin/bash

# ANSI color codes
LIGHT_BLUE='\033[1;34m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
RESET='\033[0m'

echo -e "${LIGHT_BLUE}Easy Arch Finalizer${RESET}"
echo "This script will allow you to create/load your personal configuration of the distro,"
echo "the configuration may include your own system settings, packages (can be version controlled),"
echo "package settings, folders and files (location for each folder and file can be specified)."
echo ""
echo -e "${YELLOW}Easy Arch does not provide any hosting solutions, It is your responsibility to${RESET}"
echo -e "${YELLOW}save your files including the configuration you create using this script.${RESET}"
echo ""
echo "Select one of the two options:"
echo "1. Create Configuration"
echo "2. Load Configuration"

CONFIG_FILE="easy-arch-configuration.json"
JSON_TEMPLATE='{
    "root_password": "__root_password__",
    "username": "__username__",
    "username_password": "__username_password__"
}'

while true; do
    read -p "Enter option (1 or 2): " choice
    case $choice in
        1)
            echo "Creating configuration..."
            read -s -p "Enter Root Password: " value_root_password
            echo ""
            read -p "Enter Username: " value_username
            read -s -p "Enter Password for $value_username: " value_username_password
            echo ""
            echo -e "${LIGHT_BLUE}Configuration saved to '$CONFIG_FILE'.${RESET}"
            break
            ;;
        2)
            echo "Loading configuration..."

            SELECTED_FILE=$(kdialog --getopenfilename "$PWD" "*.json" 2>/dev/null)

            if [[ -z "$SELECTED_FILE" ]]; then
                echo -e "${RED}No file selected. Exiting.${RESET}"
                exit 1
            fi

            if [[ -f "$SELECTED_FILE" ]]; then
                root_password=$(grep '"root_password"' "$SELECTED_FILE" | sed 's/.*: "\(.*\)".*/\1/')
                username=$(grep '"username"' "$SELECTED_FILE" | sed 's/.*: "\(.*\)".*/\1/')
                username_password=$(grep '"username_password"' "$SELECTED_FILE" | sed 's/.*: "\(.*\)".*/\1/')

                echo -e "${LIGHT_BLUE}Configuration Loaded:${RESET}"
                echo "Root Password: $root_password"
                echo "Username: $username"
                echo "Username Password: $username_password"
            else
                echo -e "${RED}Configuration file not found!${RESET}"
            fi
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option, retry${RESET}"
            ;;
    esac
done

[[ -z "$value_root_password" ]] && value_root_password="None"
[[ -z "$value_username" ]] && value_username="None"
[[ -z "$value_username_password" ]] && value_username_password="None"

config_json="${JSON_TEMPLATE//__root_password__/$value_root_password}"
config_json="${config_json//__username__/$value_username}"
config_json="${config_json//__username_password__/$value_username_password}"

echo "$config_json" > "$CONFIG_FILE"
umask 000
chmod 666 "$CONFIG_FILE"

