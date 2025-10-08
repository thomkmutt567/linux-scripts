#!/bin/bash

echo "----------------------------------------------------------------------------------------------------------------"
printf "%-15s %-8s %-18s %-8s %-40s\n" "USERNAME" "UID" "PRIMARY_GROUP_NAME" "PRIMARY_GID" "SECONDARY_GROUP_NAMES"
echo "----------------------------------------------------------------------------------------------------------------"

# Change: UID is renamed to USER_ID in the read command
getent passwd | while IFS=: read -r USERNAME X USER_ID GID GECOS HOME SHELL; do
    
    # ... (rest of the script logic)
    
    # 1. ค้นหาชื่อ Primary Group จาก GID (ฟิลด์ที่ 4)
    PRIMARY_GROUP_NAME=$(getent group "$GID" | cut -d: -f1)
    
    # 2. ค้นหาชื่อ Secondary Groups (ใช้คำสั่ง groups หรือ id)
    SECONDARY_GROUPS_ALL=$(groups "$USERNAME" 2>/dev/null | cut -d: -f2 | tr -d '\n')

    # ลบชื่อ Primary Group และชื่อผู้ใช้ออกจากรายการกลุ่มทั้งหมด
    SECONDARY_GROUPS=$(echo "$SECONDARY_GROUPS_ALL" | sed "s/\b$USERNAME\b//g; s/\b$PRIMARY_GROUP_NAME\b//g; s/  */ /g; s/^ *//; s/ *$//; s/ /,/g")
    
    # จัดรูปแบบผลลัพธ์
    # Change: Use the new variable USER_ID here
    printf "%-15s %-8s %-18s %-8s %-40s\n" "$USERNAME" "$USER_ID" "$PRIMARY_GROUP_NAME" "$GID" "$SECONDARY_GROUPS"
done

echo "----------------------------------------------------------------------------------------------------------------"





