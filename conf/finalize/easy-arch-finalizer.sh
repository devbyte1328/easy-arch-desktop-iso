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
    "username_password": "__username_password__",
    "install_packages": __install_packages__,
    "cache_packages": __cache_packages__,
    "packages": __packages__
}'

while true; do
    read -p "Enter option (1 or 2): " choice
    case $choice in
        1)
            echo "Creating configuration..."
            echo ""
            read -p "Enter Root Password (default is no password): " value_root_password
            echo ""
            read -p "Enter Password for username 'main' (default is no password): " value_username_password
            echo ""
            read -p "Install packages? (y/n): " install_packages
            echo ""
            if [[ "$install_packages" == "y" || "$install_packages" == "Y" ]]; then
                value_install_packages="true"
                echo "The next part requires internet connection if set to true"
                read -p "Cache packages? (y/n): " cache_packages
                echo ""
                if [[ "$cache_packages" == "y" || "$cache_packages" == "Y" ]]; then
                    value_cache_packages="true"
                else
                    value_cache_packages="false"
                fi
                read -p "Enter packages (e.g., neofetch,rar,obs-studio): " package_list
                packages_array=$(echo "$package_list" | tr ',' '\n' | jq -R . | jq -s .)
                echo ""
            else
                value_install_packages="false"
                value_cache_packages="false"
                packages_array="[]"
            fi
            # Echo user prompt based on install_packages and cache_packages
            if [[ "$value_install_packages" == "true" && "$value_cache_packages" == "true" ]]; then
                echo -e "${YELLOW}[*]Caching packages...${RESET}"
                bash easy-arch-packages-cache.sh
            fi
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
                root_password=$(jq -r '.root_password' "$SELECTED_FILE")
                username_password=$(jq -r '.username_password' "$SELECTED_FILE")
                install_packages=$(jq -r '.install_packages' "$SELECTED_FILE")
                cache_packages=$(jq -r '.cache_packages' "$SELECTED_FILE")
                packages=$(jq -r '.packages | join(", ")' "$SELECTED_FILE")
                echo -e "${LIGHT_BLUE}Configuration Loaded:${RESET}"
                echo "Root Password: $root_password"
                echo "Username Password: $username_password"
                echo "Install Packages: $install_packages"
                echo "Cache Packages: $cache_packages"
                echo "Packages: $packages"
                # Start Python script in background and capture PID
                python3 easy-arch-screen-holder.py 2>/dev/null &
                PYTHON_PID=$!
                # Trap to send close signal via pipe and kill process
                trap 'if [[ -f /tmp/overlay_pipe_fd ]]; then PIPE_FD=$(cat /tmp/overlay_pipe_fd 2>/dev/null); echo "close" >&$PIPE_FD; sleep 1; kill $PYTHON_PID 2>/dev/null; rm -f /tmp/overlay_pipe_fd; fi' EXIT
                konsole -e bash -c "
                    sleep 2;
                    if [[ \"$root_password\" != \"none\" ]]; then
                        echo -e 'Setting root password...';
                        echo 'root:$root_password' | chpasswd 2>/dev/null;
                    else
                        echo -e 'Skipping root password (none).';
                    fi
                    sleep 2;
                    if [[ \"$username_password\" != \"none\" ]]; then
                        echo -e 'Setting password for username \"main\"...';
                        echo 'main:$username_password' | chpasswd 2>/dev/null;
                    else
                        echo -e 'Skipping user password (none).';
                    fi
                    echo -e '${LIGHT_BLUE}Configuration applied. Closing window...${RESET}';
                    sleep 2;
                    if [[ -f /tmp/overlay_pipe_fd ]]; then
                        PIPE_FD=$(cat /tmp/overlay_pipe_fd 2>/dev/null);
                        echo 'close' >&\$PIPE_FD;
                        sleep 1;
                        kill $PYTHON_PID 2>/dev/null;
                        rm -f /tmp/overlay_pipe_fd;
                    fi
                " 2>/dev/null
                echo -e "${LIGHT_BLUE}Configuration applied.${RESET}"
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

# Apply defaults if values are empty
[[ -z "$value_root_password" ]] && value_root_password="none"
[[ -z "$value_username_password" ]] && value_username_password="none"
[[ -z "$value_cache_packages" ]] && value_cache_packages="false"

# Build final config JSON
config_json="${JSON_TEMPLATE//__root_password__/$value_root_password}"
config_json="${config_json//__username_password__/$value_username_password}"
config_json="${config_json//__install_packages__/$value_install_packages}"
config_json="${config_json//__cache_packages__/$value_cache_packages}"
config_json="${config_json//__packages__/$packages_array}"

# Save to file with safe permissions
echo "$config_json" > "$CONFIG_FILE"
umask 000
chmod 666 "$CONFIG_FILE"
