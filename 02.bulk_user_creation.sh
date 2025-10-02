#!/bin/bash

# กำหนดตัวแปรและไฟล์บันทึก (Log)
INPUT_FILE="$1"
LOG_FILE="./user_creation.log"

# ฟังก์ชันสำหรับบันทึกข้อความ (Log messages)
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# --- 1. ตรวจสอบสิทธิ์ Root และไฟล์ ---
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run with root privileges (sudo)." | tee -a "$LOG_FILE"
   exit 1
fi
if [ -z "$INPUT_FILE" ] || [ ! -f "$INPUT_FILE" ]; then
    echo "Usage: sudo ./bulk_user_creation.sh <user_input_file>" | tee -a "$LOG_FILE"
    echo "Input file not found or not specified. Exiting." | tee -a "$LOG_FILE"
    exit 1
fi

log_message "Starting bulk user creation from file: $INPUT_FILE"
echo "--------------------------------------------------------" | tee -a "$LOG_FILE"

# --- 2. ประมวลผลไฟล์ข้อมูลเข้าทีละบรรทัด (รับค่า 9 ฟิลด์) ---
# F1:Username, F2:UID, F3:Password, F4:PrimaryGroup, F5:PrimaryGID, F6:SecondaryGroups, F7:SecondaryGIDs (Ignored), F8:HomeDir, F9:Shell
while IFS=, read -r USERNAME USER_ID PASSWORD PRIMARY_GROUP PRIMARY_GID SECONDARY_GROUPS SECONDARY_GIDS HOME_DIR SHELL_BIN || [ -n "$USERNAME" ]; do
    
    # ข้ามบรรทัดว่างหรือบรรทัดที่เป็น comment (#)
    if [[ -z "$USERNAME" || "$USERNAME" =~ ^# ]]; then
        continue
    fi

    # ลบช่องว่างนำหน้า/ตามหลัง (Cleanup)
    USERNAME=$(echo "$USERNAME" | tr -d '[:space:]')
    USER_ID=$(echo "$USER_ID" | tr -d '[:space:]')
    PASSWORD=$(echo "$PASSWORD" | tr -d '[:space:]')
    PRIMARY_GROUP=$(echo "$PRIMARY_GROUP" | tr -d '[:space:]')
    PRIMARY_GID=$(echo "$PRIMARY_GID" | tr -d '[:space:]')
    SECONDARY_GROUPS=$(echo "$SECONDARY_GROUPS" | tr -d '[:space:]')
    HOME_DIR=$(echo "$HOME_DIR" | tr -d '[:space:]')
    SHELL_BIN=$(echo "$SHELL_BIN" | tr -d '[:space:]')
    # SECONDARY_GIDS ถูกอ่านค่าแต่จะถูกละเลยในการสร้างผู้ใช้

    log_message "Processing user: $USERNAME (UID: $USER_ID, Shell: $SHELL_BIN)"

    # --- 3. ตรวจสอบความถูกต้องของ ID และ Group ---
    if [ -z "$USER_ID" ] || ! [[ "$USER_ID" =~ ^[0-9]+$ ]]; then
        log_message "FATAL ERROR: Invalid or missing User ID for '$USERNAME'. Skipping user."
        continue
    fi
    if [ -z "$PRIMARY_GROUP" ] || [ -z "$PRIMARY_GID" ]; then
        log_message "FATAL ERROR: Primary Group or GID for '$USERNAME' is missing. Skipping user."
        continue
    fi
    
    # --- 4. ตรวจสอบและสร้าง Primary Group (ใช้ GID ที่กำหนด) ---
    if ! getent group "$PRIMARY_GROUP" &>/dev/null; then
        log_message "Primary Group '$PRIMARY_GROUP' (GID $PRIMARY_GID) does not exist. Creating it."
        groupadd -g "$PRIMARY_GID" "$PRIMARY_GROUP"
        if [ $? -ne 0 ]; then
            log_message "FATAL ERROR: Failed to create Primary Group '$PRIMARY_GROUP' with GID $PRIMARY_GID. Skipping user '$USERNAME'."
            continue
        fi
    fi
    
    # --- 5. ตรวจสอบการมีอยู่ของผู้ใช้และ UID ซ้ำ ---
    if id "$USERNAME" &>/dev/null; then
        log_message "User '$USERNAME' already exists. Skipping creation."
        continue
    fi
    if id -u "$USER_ID" &>/dev/null; then
        log_message "FATAL ERROR: UID '$USER_ID' is already in use by another user. Skipping user '$USERNAME'."
        continue
    fi

    # --- 6. จัดการกลุ่มเสริม (Secondary Groups) ---
    GROUP_ARGS=""
    if [ ! -z "$SECONDARY_GROUPS" ]; then
        IFS=',' read -r -a GROUP_ARRAY <<< "$SECONDARY_GROUPS"
        for GROUP_NAME in "${GROUP_ARRAY[@]}"; do
            if ! getent group "$GROUP_NAME" &>/dev/null; then
                log_message "Secondary Group '$GROUP_NAME' does not exist. Creating it (system-assigned GID)."
                groupadd "$GROUP_NAME"
                if [ $? -ne 0 ]; then
                    log_message "Error: Failed to create Secondary Group '$GROUP_NAME'. Skipping group assignment for $USERNAME."
                    continue 
                fi
            fi
            GROUP_ARGS+="$GROUP_NAME,"
        done
        GROUP_ARGS="-G ${GROUP_ARGS%,}"
    fi

    # --- 7. สร้างพาธหลักของ Home Directory ล่วงหน้า ---
    PARENT_DIR=$(dirname "$HOME_DIR")
    if [ ! -d "$PARENT_DIR" ]; then
        log_message "Creating parent directory: $PARENT_DIR"
        mkdir -p "$PARENT_DIR"
        if [ $? -ne 0 ]; then
            log_message "FATAL ERROR: Failed to create parent directory '$PARENT_DIR'. Skipping user '$USERNAME'."
            continue
        fi
    fi

    # --- 8. สร้างผู้ใช้, กำหนด ID, Home Directory และ Group ---
    log_message "Attempting to create user '$USERNAME' with UID $USER_ID..."
    # ใช้ -s "$SHELL_BIN" ที่อ่านมาจากไฟล์
    useradd -u "$USER_ID" -m -d "$HOME_DIR" -s "$SHELL_BIN" -g "$PRIMARY_GROUP" $GROUP_ARGS "$USERNAME"

    if [ $? -eq 0 ]; then
        log_message "User '$USERNAME' created successfully. Shell: $SHELL_BIN."
        
        # --- 9. กำหนดรหัสผ่าน ---
        log_message "Setting password for user '$USERNAME'..."
        echo "$USERNAME:$PASSWORD" | chpasswd

        if [ $? -eq 0 ]; then
            log_message "Password set successfully for $USERNAME."
        else
            log_message "CRITICAL ERROR: Failed to set password for user '$USERNAME'. Deleting user and home."
            userdel -r "$USERNAME"
            log_message "User '$USERNAME' deleted due to password failure."
        fi
    else
        log_message "FATAL ERROR: Failed to create user '$USERNAME'. Skipping password setting."
    fi
    
    echo "--------------------------------------------------------" | tee -a "$LOG_FILE"
done < "$INPUT_FILE"

log_message "Bulk user creation script finished."