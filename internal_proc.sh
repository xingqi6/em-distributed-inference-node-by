#!/bin/bash

log_proc() { echo "[PROC] $(date '+%Y-%m-%d %H:%M:%S') [Internal]: $1"; }

# 1. 等待 API 就绪
log_proc "Waiting for Resource Adapter API..."
count=0
while ! curl -s http://127.0.0.1:5244/api/public/settings > /dev/null; do
    sleep 2
    count=$((count+1))
    if [ $count -gt 30 ]; then
        log_proc "API timeout, aborting."
        exit 1
    fi
done

# 2. 获取 Token
TOKEN=$(curl -s -X POST http://127.0.0.1:5244/api/auth/login \
    -H "Content-Type: application/json" \
    -d '{"username":"admin","password":"password"}' | jq -r '.data.token')

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
    log_proc "Auth failed."
    exit 1
fi

# 3. 检查环境变量
if [ -z "$DATASET_MUSIC_NAME" ]; then
    log_proc "No dataset configured."
    exit 0
fi

# 4. 构建 Payload
# 注意：v3.35.0 版本中 HuggingFace 驱动名称确定为 "HuggingFace"
ADDITION=$(jq -n \
    --arg repo "$DATASET_MUSIC_NAME" \
    --arg token "${MUSIC_TOKEN:-}" \
    '{root_folder_path: "/", repo_id: $repo, repo_type: "dataset"} + (if $token != "" then {token: $token} else {} end)' \
    | jq -c .)

PAYLOAD=$(jq -n \
    --arg path "/ExternalData" \
    --arg add "$ADDITION" \
    '{mount_path: $path, order: 0, remark: "Auto_Mount", cache_expiration: 30, driver: "HuggingFace", addition: $add}')

# 5. 发送挂载请求
log_proc "Attaching dataset: $DATASET_MUSIC_NAME"
RESPONSE=$(curl -s -X POST http://127.0.0.1:5244/api/admin/storage/create \
    -H "Authorization: $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")

CODE=$(echo "$RESPONSE" | jq -r '.code')
if [ "$CODE" = "200" ]; then
    log_proc "Dataset attached successfully."
else
    MSG=$(echo "$RESPONSE" | jq -r '.message')
    log_proc "Attachment failed: $MSG"
    
    # 调试：如果失败，打印一下当前支持的驱动列表，看看到底叫什么名字
    log_proc "Debug: Listing available drivers..."
    curl -s -H "Authorization: $TOKEN" http://127.0.0.1:5244/api/admin/driver/list | jq -r '.data[].name' | grep -i "Hugging" | while read line; do log_proc "Found driver: $line"; done
fi
