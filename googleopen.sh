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
        echo "Error: Directory $writings_dir does not exist."
        exit 1
    fi
    
    # Get list of files (not directories)
    local files=()
    while IFS= read -r -d '' file; do
        files+=("$file")
    done < <(find "$writings_dir" -maxdepth 1 -type f -print0 | sort -z)
    
    if [ ${#files[@]} -eq 0 ]; then
        echo "No files found in $writings_dir"
        exit 1
    fi
    
    # Display files with numbers
    echo "Files in gods-writing folder:"
    echo
    for i in "${!files[@]}"; do
        local filename=$(basename "${files[$i]}")
        printf "%2d) %s\n" $((i+1)) "$filename"
    done
    echo
    
    # Prompt for selection
    while true; do
        read -p "Enter the number of the file to open (1-${#files[@]}): " choice
        
        # Validate input
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#files[@]} ]; then
            selected_file="${files[$((choice-1))]}"
            break
        else
            echo "Invalid choice. Please enter a number between 1 and ${#files[@]}."
        fi
    done
    
    echo "Selected: $(basename "$selected_file")"
    echo "$selected_file"
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
    
    # Open file in emacs
    echo "Opening $(basename "$selected_file") in emacs..."
    emacs "$selected_file"
    
    # After emacs exits, run the move script
    echo "Running gods-writings-move_if_older.sh..."
    ./gods-writings-move_if_older.sh "$selected_file" "~/GoogleDrive/gods-writing/"
    
    # Unmount rclone
    unmount_rclone
    
    echo "Done!"
}

# Run main function
main "$@"
