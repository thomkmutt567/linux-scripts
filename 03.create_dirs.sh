#!/bin/bash

# กำหนดชื่อไฟล์ Log
LOG_FILE="creation_dir_log.txt"
INPUT_FILE="$1"

# --- การตั้งค่าเริ่มต้นและการตรวจสอบ ---
if [ -z "$INPUT_FILE" ]; then
    echo "Usage: $0 <input_file.txt>"
    echo "The input file should have the format: user group directory_path (separated by space/tab)"
    exit 1
fi

if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file '$INPUT_FILE' not found."
    exit 1
fi

# ล้างไฟล์ Log เก่าและสร้าง header ใหม่
echo "Timestamp,Directory Path,Status,Details" > "$LOG_FILE"
echo "--- Starting Directory Creation and Ownership Setting ---"
echo "Log file is being saved to: $LOG_FILE"

# --- ฟังก์ชันสำหรับบันทึก Log ---
# พารามิเตอร์: $1=Directory Path, $2=Status (SUCCESS/FAILED), $3=Details
log_status() {
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    local log_entry="$timestamp,$1,$2,$3"
    echo "$log_entry" >> "$LOG_FILE"
}

# --- การอ่านและประมวลผลไฟล์ Input ---
while IFS= read -r line; do
    # ลบอักขระ Carriage Return (CR หรือ ^M) ออกจากตัวแปร $line
    # line=$(echo "$line" | tr -d '\r') 
    # ส่วนแก้ไขทีหลังเอา ^M ออก
    # ข้ามบรรทัดที่ว่างเปล่าหรือ comment
    if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
        continue
    fi

    # แยก field ต่างๆ โดยใช้ช่องว่าง/แท็บเป็นตัวคั่น (Bash default)
    set -- $line 
    user="$1"
    group="$2"
    dir_path="$3"

    # ตรวจสอบว่ามี 3 field ครบหรือไม่
    if [ -z "$user" ] || [ -z "$group" ] || [ -z "$dir_path" ]; then
        echo "Skipping line (Incomplete fields): $line"
        log_status "N/A" "FAILED" "Incomplete fields in input line: $line"
        continue
    fi

    echo "Processing: User='$user', Group='$group', Directory='$dir_path'"
    STATUS_DETAIL="" # ตัวแปรสำหรับเก็บรายละเอียดของผลลัพธ์โดยรวม

    # 1. สร้าง Directory
    if [ ! -d "$dir_path" ]; then
        if sudo mkdir -p "$dir_path"; then
            echo "  SUCCESS: Directory '$dir_path' created."
            STATUS_DETAIL="Directory created."
        else
            echo "  ERROR: Failed to create directory '$dir_path'."
            log_status "$dir_path" "FAILED" "Directory creation failed. (Check sudo permissions or path)"
            continue # ข้ามไปบรรทัดถัดไปหากสร้าง directory ไม่สำเร็จ
        fi
    else
        echo "  NOTE: Directory '$dir_path' already exists."
        STATUS_DETAIL="Directory existed."
    fi

    # 2. ตั้งค่า Owner และ Group (Chown)
    if sudo chown "$user":"$group" "$dir_path"; then
        echo "  SUCCESS: Ownership set to '$user:$group' for '$dir_path'."
        STATUS_DETAIL+=' Ownership set successfully.'
        log_status "$dir_path" "SUCCESS" "$STATUS_DETAIL"
    else
        echo "  ERROR: Failed to set ownership for '$dir_path'."
        STATUS_DETAIL+=' Ownership failed.'
        log_status "$dir_path" "FAILED" "Ownership failed. (Check if user '$user' or group '$group' exists)"
    fi
    
    echo "--------------------------------------------------------"

done < "$INPUT_FILE" # <-- ปิด while loop อย่างสมบูรณ์แล้ว

echo "--- Script Finished. Check $LOG_FILE for results. ---"
