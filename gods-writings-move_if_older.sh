#!/bin/bash

set -euo pipefail

# Check usage
if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <filename or pattern> <destination folder>"
  exit 1
fi

PATTERN="$1"
DEST_DIR="$2"

# Ensure destination folder exists
if [ ! -d "$DEST_DIR" ]; then
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
done

