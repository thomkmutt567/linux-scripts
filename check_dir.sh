#!/bin/bash

# Define the log file path
LOG_FILE="./multiple_directory_stats.log"

# Clear the log file at the start of the run (optional, use '>>' to append)
echo "--- Directory Check Run Started: $(date +"%Y-%m-%d %H:%M:%S") ---" > "$LOG_FILE"

# --- Validation for Input ---
if [ "$#" -eq 0 ]; then
    echo "Error: Please provide one or more directory paths as arguments (field1, field2, ...)." | tee -a "$LOG_FILE"
    echo "Usage: $0 /path/to/dir1 /path/to/dir2 ..."
    exit 1
fi

# --- Process Directories in a Loop ---
# The special variable '$@' holds all command-line arguments (all directory paths)
for DIR_PATH in "$@"; do
    
    # Check if the path is a valid directory
    if [ ! -d "$DIR_PATH" ]; then
        echo "⚠️ Skipping path: '$DIR_PATH'. Not found or is not a directory." >> "$LOG_FILE"
        continue # Skip to the next path in the loop
    fi

    # --- Calculations ---
    # Count files and subdirectories recursively (excluding the top-level directory itself)
    TOTAL_COUNT=$(find "$DIR_PATH" -mindepth 1 | wc -l)

    # Get total disk usage of the directory in human-readable format (e.g., 2.5G)
    TOTAL_SIZE=$(du -sh "$DIR_PATH" | awk '{print $1}')

    # --- Log Output for Current Directory ---
    {
        echo "--- Directory Stats ---"
        echo "Directory Path: $DIR_PATH"
        echo "Total Items (Files & Directories): $TOTAL_COUNT"
        echo "Total Disk Size: $TOTAL_SIZE"
        echo "-----------------------"
    } >> "$LOG_FILE"
    
    echo "✅ Checked: $DIR_PATH"

done

echo "--- Directory Check Run Finished: $(date +"%Y-%m-%d %H:%M:%S") ---" >> "$LOG_FILE"
echo "All directory checks complete. Output saved to: $LOG_FILE"