#!/bin/bash

INPUT_FILE="$1"
LOG_FILE="./recursive_user_change.log"

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
    echo "Usage: sudo ./change_recursive_user.sh <user_change_file>" | tee -a "$LOG_FILE"
    echo "Input file not found or not specified. Exiting." | tee -a "$LOG_FILE"
    exit 1
fi

log_message "Starting Recursive User Ownership correction from file: $INPUT_FILE"
echo "--------------------------------------------------------" | tee -a "$LOG_FILE"

# --- 2. ประมวลผลไฟล์ข้อมูลเข้าทีละบรรทัด (รับค่า 3 ฟิลด์) ---
# F1: OldUID, F2: NewUID/NewUsername, F3: TargetPath
while IFS=, read -r OLD_UID NEW_OWNER_ID_OR_NAME TARGET_PATH || [ -n "$OLD_UID" ]; do
    
    # ข้ามบรรทัดว่างหรือบรรทัดที่เป็น comment (#)
    if [[ -z "$OLD_UID" || "$OLD_UID" =~ ^# ]]; then
        continue
    fi
    
    # ลบช่องว่างนำหน้า/ตามหลัง (Cleanup)
    OLD_UID=$(echo "$OLD_UID" | tr -d '[:space:]')
    NEW_OWNER_ID_OR_NAME=$(echo "$NEW_OWNER_ID_OR_NAME" | tr -d '[:space:]')
    TARGET_PATH=$(echo "$TARGET_PATH" | tr -d '[:space:]')

    log_message "Processing: Path=$TARGET_PATH, Old UID=$OLD_UID, New Owner=$NEW_OWNER_ID_OR_NAME"

    # --- 3. ตรวจสอบและค้นหา Username ที่ถูกต้องสำหรับคำสั่ง chown ---
    
    # ตรวจสอบว่า F2 (New Owner) เป็นตัวเลข (UID) หรือไม่
    if [[ "$NEW_OWNER_ID_OR_NAME" =~ ^[0-9]+$ ]]; then
        # ถ้าเป็นตัวเลข (UID) ให้ค้นหา Username ที่สอดคล้องบน Server ใหม่
        NEW_USERNAME=$(getent passwd "$NEW_OWNER_ID_OR_NAME" | cut -d: -f1)
        if [ -z "$NEW_USERNAME" ]; then
            log_message "FATAL ERROR: Cannot find Username for UID $NEW_OWNER_ID_OR_NAME. The user may not exist. Skipping."
            continue
        fi
    else
        # ถ้าไม่ใช่ตัวเลข (เป็น Username) ให้ใช้ชื่อนั้นโดยตรง
        NEW_USERNAME="$NEW_OWNER_ID_OR_NAME"
        # และตรวจสอบว่า Username นี้มีอยู่จริงหรือไม่
        if ! id -u "$NEW_USERNAME" &>/dev/null; then
            log_message "FATAL ERROR: New Username '$NEW_USERNAME' does not exist. Skipping."
            continue
        fi
    fi

    # --- 4. ตรวจสอบ Path ---
    if [ ! -d "$TARGET_PATH" ]; then
        log_message "ERROR: Target Path '$TARGET_PATH' is not a valid directory or does not exist. Skipping."
        continue
    fi
    
    # --- 5. ดำเนินการแก้ไข User Ownership แบบ Recursive ---
    log_message "Changing User Ownership for files under '$TARGET_PATH' from Old UID $OLD_UID to User $NEW_USERNAME..."
    
    # ใช้ find เพื่อค้นหาไฟล์ด้วย OLD_UID (ตัวเลข) และเปลี่ยน Owner เป็น NEW_USERNAME (ชื่อ)
    FIND_COMMAND="find \"$TARGET_PATH\" -uid \"$OLD_UID\" -exec chown \"$NEW_USERNAME\" {} \;"
    log_message "Executing command: $FIND_COMMAND"
    
    eval $FIND_COMMAND

    if [ $? -eq 0 ]; then
        log_message "SUCCESS: Recursive User ownership changed to $NEW_USERNAME under $TARGET_PATH."
    else
        log_message "WARNING: Error during User Ownership change. Check logs for find/chown errors."
    fi

    echo "--------------------------------------------------------" | tee -a "$LOG_FILE"

done < "$INPUT_FILE"

log_message "Recursive User Ownership correction script finished."