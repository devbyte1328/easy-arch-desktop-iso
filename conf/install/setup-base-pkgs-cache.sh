#!/bin/bash

# Set temp location for pacman to safely write
TMPROOT="/tmp/easyarch-tmp"
TMPDB="$TMPROOT/db"
TMPCACHE="$TMPROOT/cache"

# Set final destination (relative to current dir)
FINALDB="airootfs/root/pacstrap-easyarch-db"
FINALCACHE="airootfs/root/pacstrap-easyarch-repo"

# Create safe temp dirs
mkdir -p "$TMPDB/sync"
mkdir -p "$TMPCACHE"

echo "Downloading and caching base packages using pacman..."
# Sync packages into temp
sudo pacman -Syyw \
  --noconfirm \
  --cachedir "$TMPCACHE" \
  --dbpath "$TMPDB" \
  base linux linux-firmware bc curl

# Check if pacman succeeded
if [ $? -ne 0 ]; then
  echo "Pacman failed. Aborting."
  exit 1
fi

# Create final destination dirs
mkdir -p "$FINALDB"
mkdir -p "$FINALCACHE"

# Move downloaded data back to working directory
cp -r "$TMPDB/"* "$FINALDB/"
cp -r "$TMPCACHE/"* "$FINALCACHE/"

# Cleanup
echo "🧹 Cleaning up temporary files..."
rm -rf "$TMPROOT"

echo "Packages downloaded and moved to working directory successfully."

