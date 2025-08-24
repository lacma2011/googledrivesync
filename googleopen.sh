#!/bin/bash

set -euo pipefail

# Function to check if rclone is already mounted
is_mounted() {
    mountpoint -q ~/GoogleDrive 2>/dev/null
}

# Function to start rclone mount if not already running
start_rclone() {
    if is_mounted; then
        echo "Google Drive is already mounted."
        return 0
    fi
    
    echo "Starting rclone mount..."
    
    # 1. Unmount safely (in case of stale mount)
    fusermount -u ~/GoogleDrive 2>/dev/null || sudo umount -l ~/GoogleDrive 2>/dev/null || true

    # 2. Check if the mount point is clean
    if [ ! -d ~/GoogleDrive ]; then
        mkdir -p ~/GoogleDrive
    fi

    # 3. Start rclone mount with better caching for this use case
    rclone mount google-drive: ~/GoogleDrive \
      --vfs-cache-mode full \
      --vfs-cache-max-age 10m \
      --vfs-cache-max-size 100M \
      --daemon

    # Wait longer for mount to be ready
    sleep 5
    
    # Verify mount worked
    if ! is_mounted; then
        echo "Error: Failed to mount Google Drive"
        exit 1
    fi
    
    echo "Google Drive mounted successfully."
}

# Function to list and select files
select_file() {
    local writings_dir="~/GoogleDrive/gods-writing"
    
    # Expand the tilde
    writings_dir="${writings_dir/#\~/$HOME}"
    
    if [ ! -d "$writings_dir" ]; then
        echo "Error: Directory $writings_dir does not exist." >&2
        exit 1
    fi
    
    # Get list of files (not directories) - simpler approach
    local files=()
    for file in "$writings_dir"/*; do
        if [ -f "$file" ]; then
            files+=("$file")
        fi
    done
    
    if [ ${#files[@]} -eq 0 ]; then
        echo "No files found in $writings_dir" >&2
        exit 1
    fi
    
    # Display files with numbers (to stderr so it shows up)
    echo "Files in gods-writing folder:" >&2
    echo >&2
    for i in "${!files[@]}"; do
        local filename=$(basename "${files[$i]}")
        printf "%2d) %s\n" $((i+1)) "$filename" >&2
    done
    echo >&2
    
    # Prompt for selection
    while true; do
        read -p "Enter the number of the file to open (1-${#files[@]}): " choice >&2
        
        # Validate input
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#files[@]} ]; then
            selected_file="${files[$((choice-1))]}"
            break
        else
            echo "Invalid choice. Please enter a number between 1 and ${#files[@]}." >&2
        fi
    done
    
    echo "Selected: $(basename "$selected_file")" >&2
    echo "$selected_file"  # This goes to stdout for capture
}

# Function to sync and verify file upload
sync_and_verify() {
    local file_path="$1"
    local max_attempts=5
    local attempt=1
    
    echo "Syncing file to Google Drive..." >&2
    
    while [ $attempt -le $max_attempts ]; do
        echo "Sync attempt $attempt..." >&2
        
        # Force sync the specific directory
        rclone sync "$(dirname "$file_path")" google-drive:gods-writing --progress
        
        # Wait a moment for sync to complete
        sleep 3
        
        # Verify the file exists and has content on Google Drive
        local remote_size=$(rclone size google-drive:gods-writing/$(basename "$file_path") --json 2>/dev/null | jq -r '.bytes // 0' 2>/dev/null || echo "0")
        local local_size=$(stat -f%z "$file_path" 2>/dev/null || stat -c%s "$file_path" 2>/dev/null || echo "0")
        
        echo "Local file size: $local_size bytes" >&2
        echo "Remote file size: $remote_size bytes" >&2
        
        if [ "$remote_size" -gt 0 ] && [ "$remote_size" -eq "$local_size" ]; then
            echo "File successfully synced!" >&2
            return 0
        fi
        
        echo "Sync verification failed, retrying..." >&2
        attempt=$((attempt + 1))
        sleep 2
    done
    
    echo "Warning: Could not verify successful sync after $max_attempts attempts" >&2
    return 1
}

# Function to unmount rclone
unmount_rclone() {
    if is_mounted; then
        echo "Unmounting Google Drive..."
        fusermount -u ~/GoogleDrive || sudo umount -l ~/GoogleDrive
        echo "Google Drive unmounted."
    fi
}

# Main script execution
main() {
    # Start rclone if not already mounted
    start_rclone
    
    # Select file to edit
    selected_file=$(select_file)
    
    if [ -z "$selected_file" ]; then
        echo "No file selected."
        unmount_rclone
        exit 1
    fi
    
    # Copy file to local folder
    local_file="./$(basename "$selected_file")"
    echo "Copying $(basename "$selected_file") to local folder..." >&2
    cp "$selected_file" "$local_file"
    
    if [ ! -f "$local_file" ]; then
        echo "Error: Failed to copy file to local folder." >&2
        unmount_rclone
        exit 1
    fi
    
    # Open local file in emacs
    echo "Opening $(basename "$local_file") in emacs..." >&2
    emacs "$local_file"
    
    # Verify file was actually modified and has content
    if [ ! -s "$local_file" ]; then
        echo "Warning: Local file appears to be empty!" >&2
        read -p "Do you want to continue anyway? (y/N): " continue_empty
        if [[ ! "$continue_empty" =~ ^[Yy]$ ]]; then
            echo "Aborting..." >&2
            unmount_rclone
            exit 1
        fi
    fi
    
    echo "Local file size: $(wc -c < "$local_file") bytes" >&2
    
    # Wait for user before moving
    echo >&2
    read -p "Press Enter to move file back to Google Drive..." >&2
    
    # Move to Google Drive mount point first
    destination_dir="$HOME/GoogleDrive/gods-writing/"
    echo "Moving $local_file to $destination_dir" >&2
    
    # Use cp instead of mv to keep a backup, then sync
    cp "$local_file" "$destination_dir"
    
    # Sync and verify
    if sync_and_verify "$destination_dir$(basename "$local_file")"; then
        echo "File successfully uploaded to Google Drive!" >&2
        # Only remove local file after successful sync
        rm "$local_file"
    else
        echo "Keeping local file as backup due to sync issues" >&2
    fi
    
    # Wait for user before unmounting and finishing
    echo >&2
    read -p "Press Enter to unmount and finish..." >&2
    
    # Unmount rclone
    unmount_rclone
    
    echo "Done!" >&2
}

# Run main function
main "$@"
