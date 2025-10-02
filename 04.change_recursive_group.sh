#!/bin/bash

INPUT_FILE="$1"
LOG_FILE="./recursive_group_change.log"

# ฟังก์ชันสำหรับบันทึกข้อความ
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# --- 1. ตรวจสอบสิทธิ์ Root และไฟล์ ---
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run with root privileges (sudo)." | tee -a "$LOG_FILE"
   exit 1
fi
if [ -z "$INPUT_FILE" ] || [ ! -f "$INPUT_FILE" ]; then
    echo "Usage: sudo ./change_recursive_group.sh <group_change_file>" | tee -a "$LOG_FILE"
    echo "Input file not found or not specified. Exiting." | tee -a "$LOG_FILE"
    exit 1
fi

log_message "Starting Recursive Group Ownership correction from file: $INPUT_FILE"
echo "--------------------------------------------------------" | tee -a "$LOG_FILE"

# --- 2. ประมวลผลไฟล์ข้อมูลเข้าทีละบรรทัด (รับค่า 3 ฟิลด์) ---
# F1: OldGroupName/GID, F2: NewGroupName, F3: TargetPath
while IFS=, read -r OLD_GROUP NEW_GROUPNAME TARGET_PATH || [ -n "$OLD_GROUP" ]; do
    
    # ข้ามบรรทัดว่างหรือบรรทัดที่เป็น comment (#)
    if [[ -z "$OLD_GROUP" || "$OLD_GROUP" =~ ^# ]]; then
        continue
    fi
    
    # ลบช่องว่างนำหน้า/ตามหลัง (Cleanup)
    OLD_GROUP=$(echo "$OLD_GROUP" | tr -d '[:space:]')
    NEW_GROUPNAME=$(echo "$NEW_GROUPNAME" | tr -d '[:space:]')
    TARGET_PATH=$(echo "$TARGET_PATH" | tr -d '[:space:]')

    log_message "Processing: Path=$TARGET_PATH, Old Group=$OLD_GROUP, New Group=$NEW_GROUPNAME"

    # --- 3. ตรวจสอบความถูกต้อง ---
    if [ ! -d "$TARGET_PATH" ]; then
        log_message "ERROR: Target Path '$TARGET_PATH' is not a valid directory or does not exist. Skipping."
        continue
    fi
    if ! getent group "$NEW_GROUPNAME" &>/dev/null; then
        log_message "FATAL ERROR: New Group '$NEW_GROUPNAME' does not exist on this server. Skipping."
        continue
    fi
    
    # --- 4. กำหนด Flag และ Value สำหรับ find ---
    # ตรวจสอบว่า Field 1 เป็นตัวเลข GID หรือไม่
    if [[ "$OLD_GROUP" =~ ^[0-9]+$ ]]; then
        # ใช้ GID ในการค้นหา (find -gid)
        OLD_GROUP_FOR_SEARCH="$OLD_GROUP"
        FIND_FLAG="-gid"
        log_message "Detected OLD_GROUP as GID ($OLD_GROUP). Using find -gid."
    else
        # พยายามค้นหา GID จาก
