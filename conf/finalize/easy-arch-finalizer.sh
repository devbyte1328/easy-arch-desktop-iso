#!/bin/bash

# ANSI color codes
LIGHT_BLUE='\033[1;34m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
RESET='\033[0m'

echo -e "${LIGHT_BLUE}Easy Arch Finalizer${RESET}"
echo "This script lets you create or load your personal configuration for the distro."
echo "Your configuration can include system settings, packages (with optional caching),"
echo "and custom commands to modify or personalize the distro to fit your needs."
echo ""
echo -e "${YELLOW}Easy Arch does not provide any hosting services.${RESET}"
echo -e "${YELLOW}You are responsible for saving your files, including the configuration file created with this script.${RESET}"
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
    "system_settings_screen_locking=false"
    "system_settings_power_management=false"
    "system_settings_clear_clipboard_history=false"
    "custom_commands=[]"
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
                    bash /home/main/.config/easy-arch-finalizer/easy-arch-packages-cache.sh "$package_list"
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
                read -p "System settings - Disable screen locking? (y/n): " ans
                [[ "$ans" == [yY] ]] && value_system_settings_screen_locking="true" || value_system_settings_screen_locking="false"
                read -p "System settings - Disable power management? (y/n): " ans
                [[ "$ans" == [yY] ]] && value_system_settings_power_management="true" || value_system_settings_power_management="false"
                read -p "System settings - Disable clipboard history 'Ask again' prompt? (y/n): " ans
                [[ "$ans" == [yY] ]] && value_system_settings_clear_clipboard_history="true" || value_system_settings_clear_clipboard_history="false"
            else
                value_system_settings_screen_locking="false"
                value_system_settings_power_management="false"
                value_system_settings_clear_clipboard_history="false"
            fi

            read -p "Add your own custom commands? (y/n): " custom_commands
            custom_commands_array=()
            if [[ "$custom_commands" == "y" || "$custom_commands" == "Y" ]]; then
                count=1
                while true; do
                    read -p "Provide custom command #$count: " user_command
                    custom_commands_array+=("$user_command")
                    read -p "Add another custom command? (y/n): " another
                    [[ "$another" != "y" && "$another" != "Y" ]] && break
                    ((count++))
                done
            fi
            value_custom_commands=$(printf '%s\n' "${custom_commands_array[@]}" | jq -R . | jq -s .)

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
                system_settings_screen_locking=$(jq -r '.system_settings_screen_locking' "$SELECTED_FILE")
                system_settings_power_management=$(jq -r '.system_settings_power_management' "$SELECTED_FILE")
                system_settings_clear_clipboard_history=$(jq -r '.system_settings_clear_clipboard_history' "$SELECTED_FILE")
                custom_commands=$(jq -r '.custom_commands | join(" && ")' "$SELECTED_FILE")

                echo -e "${LIGHT_BLUE}Configuration Loaded:${RESET}"
                echo "Root Password: $root_password"
                echo "Username Password: $username_password"
                echo "Install Packages: $install_packages"
                echo "Cache Packages: $cache_packages"
                echo "Packages: $packages"
                echo "System Settings Screen Locking: $system_settings_screen_locking"
                echo "System Settings Power Management: $system_settings_power_management"
                echo "System Settings Clear Clipboard History: $system_settings_clear_clipboard_history"
                echo "Custom Commands: $custom_commands"

                touch /home/main/.config/easy-arch-finalizer/tmp/easy-arch-screen-holder-loading-1
                bash -c "source /home/main/.config/easy-arch-finalizer/venv/bin/activate && python /home/main/.config/easy-arch-finalizer/easy-arch-screen-holder-background.py" 2>/dev/null &
                bash -c "source /home/main/.config/easy-arch-finalizer/venv/bin/activate && python /home/main/.config/easy-arch-finalizer/easy-arch-screen-holder-text.py" 2>/dev/null &
                bash -c "source /home/main/.config/easy-arch-finalizer/venv/bin/activate && python /home/main/.config/easy-arch-finalizer/easy-arch-screen-holder-loading.py" 2>/dev/null &

                if [[ "$root_password" != "none" || "$username_password" != "none" ]]; then
                    konsole -e bash -c "
                        sleep 2;
                        [[ \"$root_password\" != \"none\" ]] && echo 'root:$root_password' | chpasswd 2>/dev/null
                        [[ \"$username_password\" != \"none\" ]] && echo 'main:$username_password' | chpasswd 2>/dev/null
                        echo -e '${LIGHT_BLUE}Passwords applied. Closing window...${RESET}';
                        sleep 2;
                        exit 0;
                    " 2>/dev/null
                fi

                mv /home/main/.config/easy-arch-finalizer/tmp/easy-arch-screen-holder-loading-1 /home/main/.config/easy-arch-finalizer/tmp/easy-arch-screen-holder-loading-2
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
                        echo -e '${LIGHT_BLUE}Installing packages...${RESET}';
                        sleep 2;
                        CONFIG_PATH=\"$SELECTED_FILE\"
                        PACKAGES=\$(jq -r '.packages[]' \"\$CONFIG_PATH\")
                        for pkg in \$PACKAGES; do
                            if pacman -Si \$pkg &>/dev/null; then
                                echo -e '${YELLOW}Installing \$pkg with pacman...${RESET}';
                                pacman -S --noconfirm \$pkg
                            else
                                echo -e '${YELLOW}Installing \$pkg with yay...${RESET}';
                                sudo -u main yay -S --noconfirm \$pkg
                            fi
                        done
                        echo -e '${LIGHT_BLUE}Packages installed. Closing window...${RESET}';
                        sleep 2;
                        exit 0;
                    " 2>/dev/null
                fi
                
                mv /home/main/.config/easy-arch-finalizer/tmp/easy-arch-screen-holder-loading-2 /home/main/.config/easy-arch-finalizer/tmp/easy-arch-screen-holder-loading-3
                [[ "$system_settings_screen_locking" == "true" ]] && source /home/main/.config/easy-arch-finalizer/venv/bin/activate && python /home/main/.config/easy-arch-finalizer/ui-auto/system_settings_screen_locking/ui-auto.py && deactivate
                [[ "$system_settings_power_management" == "true" ]] && source /home/main/.config/easy-arch-finalizer/venv/bin/activate && python /home/main/.config/easy-arch-finalizer/ui-auto/system_settings_power_management/ui-auto.py && deactivate
                [[ "$system_settings_clear_clipboard_history" == "true" ]] && source /home/main/.config/easy-arch-finalizer/venv/bin/activate && python /home/main/.config/easy-arch-finalizer/ui-auto/system_settings_clear_clipboard_history/ui-auto.py && deactivate

                mv /home/main/.config/easy-arch-finalizer/tmp/easy-arch-screen-holder-loading-3 /home/main/.config/easy-arch-finalizer/tmp/easy-arch-screen-holder-loading-4
                custom_commands_present=$(jq '.custom_commands | length' "$SELECTED_FILE")
                if [[ "$custom_commands_present" -gt 0 ]]; then
                    echo -e "${LIGHT_BLUE}Executing custom commands...${RESET}"
                    mapfile -t commands < <(jq -r '.custom_commands[]' "$SELECTED_FILE")
                    for cmd in "${commands[@]}"; do
                        echo -e "${YELLOW}Executing: $cmd${RESET}"
                        bash -c "$cmd"
                    done
                fi

                rm -f /home/main/.config/easy-arch-finalizer/tmp/easy-arch-screen-holder-loading-4
                rm -f /home/main/.config/easy-arch-finalizer/tmp/easy-arch-screen-holder-text
                rm -f /home/main/.config/easy-arch-finalizer/tmp/easy-arch-screen-holder-background
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

# Build JSON
json_output="{"
for item in "${ordered_config_defaults[@]}"; do
    key="${item%%=*}"
    var_name="value_$key"
    value="${!var_name}"
    if [[ "$value" == "true" || "$value" == "false" || "$value" == \[* || "$value" == \{* || "$value" =~ ^[0-9]+$ ]]; then
        json_output+="\n    \"$key\": $value,"
    else
        json_output+="\n    \"$key\": \"${value}\","
    fi
done
json_output="${json_output%,}"
json_output+="\n}"

echo -e "$json_output" > "$CONFIG_FILE"
umask 000
chmod 666 "$CONFIG_FILE"

