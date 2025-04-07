#!/bin/bash

# Prompt user for root password
echo "Please enter a new password for the root user:"
passwd root

# Prompt user for main user password
echo "Please enter a new password for the 'main' user:"
passwd main

# Modify sudoers file
sudoers_file="/etc/sudoers"

# Comment out %wheel NOPASSWD line
sed -i 's/^%wheel ALL=(ALL:ALL) NOPASSWD: ALL/# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/' "$sudoers_file"

# Add 'main' sudo line if not present
if ! grep -q '^main ALL=(ALL:ALL) ALL' "$sudoers_file"; then
    sed -i '/^root ALL=(ALL:ALL) ALL/a main ALL=(ALL:ALL) ALL' "$sudoers_file"
fi

# Cleanup
echo "Passwords updated!"
echo "Deleting script..."
echo "It's recommended to reboot."

rm -- "$0"

