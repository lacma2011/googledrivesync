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

    # 3. Start rclone mount with better caching for read-only access
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
        read -p "Enter the number of the file to open for read-only (1-${#files[@]}): " choice >&2
        
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
    
    # Select file to read
    selected_file=$(select_file)
    
    if [ -z "$selected_file" ]; then
        echo "No file selected."
        unmount_rclone
        exit 1
    fi
    
    # Verify file exists and is readable
    if [ ! -f "$selected_file" ]; then
        echo "Error: Selected file does not exist or is not readable." >&2
        unmount_rclone
        exit 1
    fi
    
    # Open file directly in emacs in read-only mode
    echo "Opening $(basename "$selected_file") in read-only mode..." >&2
    emacs --eval "(progn (find-file \"$selected_file\") (read-only-mode 1) (message \"File opened in read-only mode\"))"
    
    # Wait for user before unmounting and finishing
    echo >&2
    read -p "Press Enter to unmount and finish..." >&2
    
    # Unmount rclone
    unmount_rclone
    
    echo "Done!" >&2
}

# Run main function
main "$@"
