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

    # 3. Start rclone mount
    rclone mount google-drive: ~/GoogleDrive \
      --vfs-cache-mode writes \
      --daemon

    # Wait a moment for mount to be ready
    sleep 2
    
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
    
    # After emacs exits, run the move script to move local file back to Google Drive
    echo "Running gods-writings-move_if_older.sh..." >&2
    # Expand the tilde in the destination path
    destination_dir="$HOME/GoogleDrive/gods-writing/"
    ./gods-writings-move_if_older.sh "$local_file" "$destination_dir"
    
    # Unmount rclone
    unmount_rclone
    
    echo "Done!" >&2
}

# Run main function
main "$@"
