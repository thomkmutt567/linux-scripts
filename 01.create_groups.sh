#!/bin/bash

INPUT_FILE="$1"
LOG_FILE="./group_creation.log"

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
    echo "Usage: sudo ./create_groups.sh <group_input_file>" | tee -a "$LOG_FILE"
    echo "Input file not found or not specified. Exiting." | tee -a "$LOG_FILE"
    exit 1
fi

log_message "Starting bulk group creation from file: $INPUT_FILE"
echo "--------------------------------------------------------" | tee -a "$LOG_FILE"

# --- 2. ฟังก์ชันสร้างกลุ่ม ---
create_group() {
    local GROUP_NAME="$1"
    local GID="$2"
    local GROUP_TYPE="$3" # Primary หรือ Secondary

    # ตรวจสอบว่า GID เป็นตัวเลขหรือไม่
    if ! [[ "$GID" =~ ^[0-9]+$ ]]; then
        log_message "ERROR: Invalid GID '$GID' for $GROUP_TYPE Group '$GROUP_NAME'. Skipping."
        return 1
    fi
    
    # 2.1 ตรวจสอบว่า GID ถูกใช้แล้วโดยกลุ่มอื่นที่มีชื่อต่างกันหรือไม่
    if getent group "$GID" | grep -v "^$GROUP_NAME:" &>/dev/null; then
        local EXISTING_GROUP=$(getent group "$GID" | cut -d: -f1)
        log_message "FATAL ERROR: GID $GID is already used by group '$EXISTING_GROUP'. Cannot create $GROUP_NAME."
        return 1
    fi

    # 2.2 ตรวจสอบว่ากลุ่มมีอยู่แล้วหรือไม่
    if getent group "$GROUP_NAME" &>/dev/null; then
        log_message "$GROUP_TYPE Group '$GROUP_NAME' already exists. Skipping creation."
        return 0
    fi
    
    # 2.3 สร้างกลุ่ม
    log_message "Creating $GROUP_TYPE Group '$GROUP_NAME' with GID $GID..."
    groupadd -g "$GID" "$GROUP_NAME"

    if [ $? -eq 0 ]; then
        log_message "Success: $GROUP_TYPE Group '$GROUP_NAME' created."
        return 0
    else
        log_message "FATAL ERROR: Failed to create $GROUP_TYPE Group '$GROUP_NAME'. Check GID validity or system limits."
        return 1
    fi
}

# --- 3. ประมวลผลไฟล์ข้อมูลเข้าทีละบรรทัด (รับค่า 4 ฟิลด์) ---
# F1:PrimaryGroupName, F2:PrimaryGID, F3:SecondaryGroupName, F4:SecondaryGroupID
while IFS=, read -r PRIMARY_NAME PRIMARY_GID SECONDARY_NAME SECONDARY_GID || [ -n "$PRIMARY_NAME" ]; do
    
    # ข้ามบรรทัดว่างหรือบรรทัดที่เป็น comment (#)
    if [[ -z "$PRIMARY_NAME" || "$PRIMARY_NAME" =~ ^# ]]; then
        continue
    fi

    # ลบช่องว่างนำหน้า/ตามหลัง (Cleanup)
    PRIMARY_NAME=$(echo "$PRIMARY_NAME" | tr -d '[:space:]')
    PRIMARY_GID=$(echo "$PRIMARY_GID" | tr -d '[:space:]')
    SECONDARY_NAME=$(echo "$SECONDARY_NAME" | tr -d '[:space:]')
    SECONDARY_GID=$(echo "$SECONDARY_GID" | tr -d '[:space:]')

    log_message "Processing entry: Primary=$PRIMARY_NAME, Secondary=$SECONDARY_NAME"

    # 3.1 สร้าง Primary Group
    if [ ! -z "$PRIMARY_NAME" ]; then
        create_group "$PRIMARY_NAME" "$PRIMARY_GID" "Primary"
    fi

    # 3.2 สร้าง Secondary Group
    if [ ! -z "$SECONDARY_NAME" ]; then
        create_group "$SECONDARY_NAME" "$SECONDARY_GID" "Secondary"
    fi

    echo "--------------------------------------------------------" | tee -a "$LOG_FILE"

done < "$INPUT_FILE"

log_message "Bulk group creation script finished."