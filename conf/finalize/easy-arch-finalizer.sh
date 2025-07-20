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
ordered_config_defaults=(
    "root_password=none"
    "username_password=none"
    "install_packages=false"
    "cache_packages=false"
    "packages=[]"
    "system_settings=false"
    "system_settings_screen_locking=false"
    "system_settings_recent_files=false"
    "system_settings_power_management=false"
    "system_settings_clear_clipboard_history=false"
    "system_settings_brave_plasma_integration=false"
    "system_settings_display_configuration_scale=false"
)

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
                echo ""

                if [[ "$value_cache_packages" == "true" ]]; then
                    echo -e "${YELLOW}[*]Caching packages...${RESET}"
                    bash easy-arch-packages-cache.sh "$package_list"
                    packages_array="[]"
                else
                    packages_array=$(echo "$package_list" | tr ',' '\n' | jq -R . | jq -s .)
                fi
                value_packages="$packages_array"
            else
                value_install_packages="false"
                value_cache_packages="false"
                packages_array="[]"
                value_packages="$packages_array"
            fi
            read -p "Modify system settings? (y/n): " system_settings
            if [[ "$system_settings" == "y" || "$system_settings" == "Y" ]]; then
            	value_system_settings="true"
            
            	read -p "System settings - Screen Locking? (y/n): " system_settings_screen_locking
            	if [[ "$system_settings_screen_locking" == "y" || "$system_settings_screen_locking" == "Y" ]]; then
            		value_system_settings_screen_locking="true"
            	else
            		value_system_settings_screen_locking="false"
            	fi
            
            	read -p "System settings - Recent Files? (y/n): " system_settings_recent_files
            	if [[ "$system_settings_recent_files" == "y" || "$system_settings_recent_files" == "Y" ]]; then
            		value_system_settings_recent_files="true"
            	else
            		value_system_settings_recent_files="false"
            	fi
            
            	read -p "System settings - Power Management? (y/n): " system_settings_power_management
            	if [[ "$system_settings_power_management" == "y" || "$system_settings_power_management" == "Y" ]]; then
            		value_system_settings_power_management="true"
            	else
            		value_system_settings_power_management="false"
            	fi
            
            	read -p "System settings - Clear Clipboard History? (y/n): " system_settings_clear_clipboard_history
            	if [[ "$system_settings_clear_clipboard_history" == "y" || "$system_settings_clear_clipboard_history" == "Y" ]]; then
            		value_system_settings_clear_clipboard_history="true"
            	else
            		value_system_settings_clear_clipboard_history="false"
            	fi
            
            	read -p "System settings - Brave Plasma Integration? (y/n): " system_settings_brave_plasma_integration
            	if [[ "$system_settings_brave_plasma_integration" == "y" || "$system_settings_brave_plasma_integration" == "Y" ]]; then
            		value_system_settings_brave_plasma_integration="true"
            	else
            		value_system_settings_brave_plasma_integration="false" 
            	fi
           
            	read -p "System settings - Display Configuration Scale? (y/n): " system_settings_display_configuration_scale
            	if [[ "$system_settings_display_configuration_scale" == "y" || "$system_settings_display_configuration_scale" == "Y" ]]; then
            		value_system_settings_display_configuration_scale="true"
            	else
            		value_system_settings_display_configuration_scale="false" 
            	fi
            else
            	value_system_settings="false"
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
                system_settings=$(jq -r '.system_settings' "$SELECTED_FILE")
                system_settings_screen_locking=$(jq -r '.system_settings_screen_locking' "$SELECTED_FILE")
                echo -e "${LIGHT_BLUE}Configuration Loaded:${RESET}"
                echo "Root Password: $root_password"
                echo "Username Password: $username_password"
                echo "Install Packages: $install_packages"
                echo "Cache Packages: $cache_packages"
                echo "Packages: $packages"
                echo "System Settings: $system_settings"
                echo "System Settings Screen Locking: $system_settings_screen_locking"
                
                bash -c "source venv/bin/activate && python easy-arch-screen-holder-background.py" 2>/dev/null &
                bash -c "source venv/bin/activate && python easy-arch-screen-holder-text.py" 2>/dev/null &
		
		        if [[ "$root_password" != "none" || "$username_password" != "none" ]]; then
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
			        exit 0;
		            " 2>/dev/null
		        fi

		        if [[ "$install_packages" == "true" && "$cache_packages" == "true" ]]; then
		            konsole -e bash -c "
			        sleep 2;
			        sudo pacman -U --noconfirm easy-arch-packages-cache/*.pkg.tar.zst
			        echo -e '${LIGHT_BLUE}Cached packages installed. Closing window...${RESET}';
			        sleep 2;
			        exit 0;
		            " 2>/dev/null
		        fi

		        if [[ "$install_packages" == "true" && "$cache_packages" == "false" ]]; then
		            konsole -e bash -c "
		                echo -e '${LIGHT_BLUE}Installing packages using pacman and yay...${RESET}';
		                sleep 2;
		                CONFIG_PATH=\"$PWD/$CONFIG_FILE\"
		                PACKAGES=\$(jq -r '.packages[]' \"\$CONFIG_PATH\")
		                for pkg in \$PACKAGES; do
		                    if pacman -Si \$pkg &>/dev/null; then
		                        echo -e '${YELLOW}Installing \$pkg with pacman...${RESET}';
		                        pacman -S --noconfirm \$pkg
		                    else
		                        echo -e '${YELLOW}Package \$pkg not found in pacman, trying yay...${RESET}';
		                        sudo -u main yay -S --noconfirm \$pkg
		                    fi
		                done
		                echo -e '${LIGHT_BLUE}Packages downloaded and installed. Closing window...${RESET}';
		                sleep 2;
		                exit 0;
		            " 2>/dev/null
		        fi
		        
		        if [[ "$system_settings_screen_locking" == "true" ]]; then
		            konsole -e bash -c "
		                echo -e '${LIGHT_BLUE}Running 'ui-auto.py' script to apply screen locking settings...${RESET}';
		                sleep 2;
		                source venv/bin/activate
		                python ui-auto.py
		                deactivate
		            " 2>/dev/null
		        
		        fi
		        
		        rm /tmp/easy-arch-screen-holder-text
		        rm /tmp/easy-arch-screen-holder-background
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


# Apply defaults if not set
for item in "${ordered_config_defaults[@]}"; do
    key="${item%%=*}"
    default="${item#*=}"
    var_name="value_$key"
    [[ -z "${!var_name}" ]] && declare "$var_name=$default"
done

# Build JSON with correct formatting
json_output="{"
for item in "${ordered_config_defaults[@]}"; do
    key="${item%%=*}"
    var_name="value_$key"
    value="${!var_name}"

    # Quote only if not native JSON or boolean
    if [[ "$value" == "true" || "$value" == "false" || "$value" == \[* || "$value" == \{* || "$value" =~ ^[0-9]+$ ]]; then
        json_output+="\n    \"$key\": $value,"
    else
        json_output+="\n    \"$key\": \"${value}\","
    fi
done
# Clean up trailing comma and close JSON
json_output="${json_output%,}"
json_output+="\n}"

# Save with permissions
echo -e "$json_output" > "$CONFIG_FILE"
umask 000
chmod 666 "$CONFIG_FILE"
