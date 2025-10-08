#!/bin/bash

###########################################################
#                    CONFIGURATION                        #
###########################################################

# 1. กำหนดชื่อไฟล์รายชื่อ Path ที่ต้องการแก้ไข (ห้ามลืมเปลี่ยน!)
PATH_LIST_FILE="./paths_to_remap.txt" 

# 2. กำหนดสิทธิ์ Permission ที่ต้องการให้ ACLs ได้รับ
ACL_PERMISSIONS="rwx" 

###########################################################
#                    CORE SCRIPT                          #
###########################################################

LOG_FILE="./remap_summary_dynamic.log"
DETAIL_LOG_FILE="./remap_details.log" 

TOTAL_FILES=0
CHANGE_COUNT=0
ACL_CORRECTED=0
OWNER_SKIP_COUNT=0
TOTAL_DIRS_PROCESSED=0

# ฟังก์ชันสำหรับบันทึกข้อความสรุป
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# ฟังก์ชันสำหรับบันทึกรายละเอียดการแก้ไขที่สำเร็จ
log_detail_success() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - SUCCESS: $1" >> "$DETAIL_LOG_FILE"
}

# ฟังก์ชันสำหรับบันทึกรายละเอียดข้อผิดพลาด
log_detail_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $1" >> "$DETAIL_LOG_FILE"
}

# --- 0. ตรวจสอบและเตรียมไฟล์ Log ---
echo "--- Starting Log ---" > "$DETAIL_LOG_FILE"

# --- 1. ตรวจสอบสิทธิ์ Root, ไฟล์ Path List, และเครื่องมือ ACL ---
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run with root privileges (sudo)." | tee -a "$LOG_FILE"
    exit 1
fi
if [ ! -f "$PATH_LIST_FILE" ]; then
    log_message "FATAL ERROR: Path List File '$PATH_LIST_FILE' not found. Exiting."
    exit 1
fi

ACL_TOOL_CHECK=$(which setfacl 2>/dev/null)
if [ -z "$ACL_TOOL_CHECK" ]; then
    log_message "WARNING: 'setfacl' tool not found. ACLs will NOT be corrected. Only basic ownership will be fixed."
fi

log_message "Starting DYNAMIC Recursive Ownership and ACL Re-mapping. Reading Paths from $PATH_LIST_FILE"
log_message "--------------------------------------------------------"

# --- 2. อ่าน Path จากไฟล์ Path List ---
# ใช้ IFS= อ่านทีละบรรทัด โดยถือว่าบรรทัดทั้งหมดคือ TARGET_PATH
while IFS= read -r TARGET_PATH || [[ -n "$TARGET_PATH" ]]; do
    
    # ข้ามบรรทัดที่เป็น comment หรือว่างเปล่า
    if [[ "$TARGET_PATH" =~ ^#.* ]] || [[ -z "$TARGET_PATH" ]]; then
        continue
    fi
    
    # ตัดช่องว่างหน้าหลังออก
    TARGET_PATH=$(echo "$TARGET_PATH" | xargs)
    
    if [ ! -d "$TARGET_PATH" ]; then
        log_message "WARNING: Path '$TARGET_PATH' is not a valid directory. Skipping."
        log_detail_error "SKIPPED: Path '$TARGET_PATH' is not a valid directory or does not exist."
        continue
    fi

    TOTAL_DIRS_PROCESSED=$((TOTAL_DIRS_PROCESSED + 1))
    log_message "Processing Directory: $TARGET_PATH"

    # --- 3. ดำเนินการ Re-map Ownership (Dynamic Per File) ---
    # ใช้ find -print0 เพื่อความปลอดภัยในการจัดการชื่อไฟล์ที่มีช่องว่างใน Directory ที่กำหนด
    sudo find "$TARGET_PATH" -type f -o -type d -o -type l -print0 2>/dev/null | \
    while IFS= read -r -d $'\0' file; do
        TOTAL_FILES=$((TOTAL_FILES + 1))
        
        # 3.1 ดึงชื่อ User/Group Name ปัจจุบัน (ที่ย้ายมา)
        CURRENT_USER=$(stat -c "%U" "$file" 2>/dev/null)
        CURRENT_GROUP=$(stat -c "%G" "$file" 2>/dev/null)
        
        # Fallback to UID/GID if name is unknown
        if [[ "$CURRENT_USER" =~ ^[0-9]+$ || "$CURRENT_USER" == "UNKNOWN" || "$CURRENT_USER" == "?" ]]; then
            CURRENT_USER=$(stat -c "%u" "$file" 2>/dev/null)
        fi
        if [[ "$CURRENT_GROUP" =~ ^[0-9]+$ || "$CURRENT_GROUP" == "UNKNOWN" || "$CURRENT_GROUP" == "?" ]]; then
            CURRENT_GROUP=$(stat -c "%g" "$file" 2>/dev/null)
        fi

        # 3.2 ตรวจสอบว่าชื่อ User และ Group นั้นมีอยู่บนเครื่องใหม่หรือไม่
        IS_USER_EXISTS=0
        if getent passwd "$CURRENT_USER" &>/dev/null; then IS_USER_EXISTS=1; fi
        IS_GROUP_EXISTS=0
        if getent group "$CURRENT_GROUP" &>/dev/null; then IS_GROUP_EXISTS=1; fi
        
        # 3.3 ดำเนินการ chown และ Re-map Ownership หลัก
        CHOWN_STATUS="SKIP"
        if [ "$IS_USER_EXISTS" -eq 1 ] || [ "$IS_GROUP_EXISTS" -eq 1 ]; then
            if sudo chown -h "$CURRENT_USER":"$CURRENT_GROUP" "$file"; then
                CHANGE_COUNT=$((CHANGE_COUNT + 1))
                CHOWN_STATUS="CHOWNED"
            else
                log_detail_error "CHOWN FAILED: Could not change ownership to $CURRENT_USER:$CURRENT_GROUP for file: $file"
                CHOWN_STATUS="FAILED_CHOWN"
            fi
        else
            OWNER_SKIP_COUNT=$((OWNER_SKIP_COUNT + 1))
            log_detail_error "OWNER NOT FOUND: Skipped chown for file: $file. Owner/Group '$CURRENT_USER:$CURRENT_GROUP' not found on system."
        fi

        # --- 4. แก้ไข ACLs (ถ้าเครื่องมือมีอยู่และไฟล์มี ACLs) ---
        ACL_STATUS="N/A"
        if [ ! -z "$ACL_TOOL_CHECK" ] && getfacl "$file" 2>/dev/null | grep -q "group:"; then
            ACL_STATUS="CHECKED"
            if [ "$IS_USER_EXISTS" -eq 1 ] || [ "$IS_GROUP_EXISTS" -eq 1 ]; then
                if sudo setfacl -m u:"$CURRENT_USER":"$ACL_PERMISSIONS",g:"$CURRENT_GROUP":"$ACL_PERMISSIONS" "$file" 2>/dev/null; then
                    ACL_CORRECTED=$((ACL_CORRECTED + 1))
                    ACL_STATUS="CORRECTED"
                else
                    log_detail_error "SETFACL FAILED: Could not modify ACL for file: $file (Target: $CURRENT_USER:$CURRENT_GROUP)"
                    ACL_STATUS="FAILED_ACL"
                fi
            fi
        fi
        
        # 5. บันทึกผลลัพธ์โดยละเอียด
        if [[ "$CHOWN_STATUS" == "CHOWNED" || "$ACL_STATUS" == "CORRECTED" ]]; then
            log_detail_success "File: $file | New Owner: $CURRENT_USER:$CURRENT_GROUP | Chown Status: $CHOWN_STATUS | ACL Status: $ACL_STATUS"
        fi

        # สถานะความคืบหน้า (บันทึกในไฟล์ Log สรุป)
        if (( TOTAL_FILES % 50000 == 0 )); then
            log_message "STATUS: Processed $TOTAL_FILES files. Changed $CHANGE_COUNT owners so far."
        fi

    done
done < "$PATH_LIST_FILE" # อ่าน Path จากไฟล์

# --- 6. สรุปผลลัพธ์ ---
log_message "--------------------------------------------------------"
log_message "Script finished. Total directories processed: $TOTAL_DIRS_PROCESSED"
log_message "SUMMARY: Total items processed: $TOTAL_FILES"
log_message "SUMMARY: Ownership successfully re-mapped: $CHANGE_COUNT"
log_message "SUMMARY: ACLs corrected: $ACL_CORRECTED"
log_message "SUMMARY: Skipped (Owner/Group not found on system): $OWNER_SKIP_COUNT"