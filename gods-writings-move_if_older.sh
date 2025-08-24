#!/bin/bash

set -euo pipefail

# Check usage
if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <filename or pattern> <destination folder>"
  exit 1
fi

PATTERN="$1"
DEST_DIR="$2"

# Function to sync file directly to Google Drive (bypassing mount issues)
sync_direct_to_gdrive() {
    local src_file="$1"
    local dest_dir="$2"
    
    echo "Syncing $src_file directly to Google Drive..."
    
    # Copy directly to Google Drive using rclone (bypassing mount)
    rclone copy "$src_file" google-drive:gods-writing/ --progress -v
    
    # Verify the upload
    local filename=$(basename "$src_file")
    local local_size=$(stat -f%z "$src_file" 2>/dev/null || stat -c%s "$src_file" 2>/dev/null || echo "0")
    local remote_size=$(rclone size "google-drive:gods-writing/$filename" --json 2>/dev/null | jq -r '.bytes // 0' 2>/dev/null || echo "0")
    
    echo "Local file size: $local_size bytes"
    echo "Remote file size: $remote_size bytes"
    
    if [ "$remote_size" -gt 0 ] && [ "$remote_size" -eq "$local_size" ]; then
        echo "File successfully uploaded!"
        return 0
    else
        echo "Upload verification failed!"
        return 1
    fi
}

# Ensure destination folder exists (only check if it's a local path)
if [[ "$DEST_DIR" != *"GoogleDrive"* ]] && [ ! -d "$DEST_DIR" ]; then
  echo "Error: Destination directory '$DEST_DIR' does not exist."
  exit 2
fi

# Loop over matching files
for SRC_FILE in $PATTERN; do
  # Ensure it's a regular file
  if [ ! -f "$SRC_FILE" ]; then
    echo "Skipping '$SRC_FILE': Not a regular file."
    continue
  fi

  # Check if this is going to Google Drive
  if [[ "$DEST_DIR" == *"GoogleDrive"* ]]; then
    echo "Detected Google Drive destination, using direct sync method..."
    
    if sync_direct_to_gdrive "$SRC_FILE" "$DEST_DIR"; then
      echo "Removing local file after successful upload..."
      rm "$SRC_FILE"
    else
      echo "Keeping local file due to upload issues."
    fi
    
  else
    # Original logic for non-Google Drive destinations
    DEST_FILE="$DEST_DIR/$(basename "$SRC_FILE")"

    if [ -f "$DEST_FILE" ]; then
      if [ "$SRC_FILE" -nt "$DEST_FILE" ]; then
        echo "Moving newer '$SRC_FILE' to '$DEST_DIR/'..."
        mv "$SRC_FILE" "$DEST_DIR/"
      else
        echo "WARNING: '$SRC_FILE' is not newer than '$DEST_FILE'. Skipping."
      fi
    else
      echo "Destination file '$DEST_FILE' does not exist. Moving '$SRC_FILE'."
      mv "$SRC_FILE" "$DEST_DIR/"
    fi
  fi
done
