#!/bin/bash

# Verify internet connection for 15 seconds pinging archlinux.org
timeout 15s bash -c "until ping -c 1 archlinux.org >/dev/null 2>&1; do sleep 1; done" || { echo "No internet connection after 15s"; exit 1; }

timedatectl set-ntp true
