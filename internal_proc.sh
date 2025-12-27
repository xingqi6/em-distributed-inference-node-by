#!/bin/bash

log_proc() { echo "[Internal] $1"; }

log_proc "Waiting for Alist API..."
count=0
while ! curl -s http://127.0.0.1:5244/api/public/settings > /dev/null; do
    sleep 2
    count=$((count+1))
    if [ $count -gt 30 ]; then exit 1; fi
done

# 获取 Token
TOKEN=$(curl -s -X POST http://127.0.0.1:5244/api/auth/login \
    -H "Content-Type: application/json" \
    -d '{"username":"admin","password":"password"}' | jq -r '.data.token')

if [ -z "$DATASET_MUSIC_NAME" ]; then
    log_proc "No dataset configured."
    exit 0
fi

# === 修复：构建 JSON Payload (更稳健的方式) ===
# 1. 先构建 addition 里的 JSON 字符串
if [ -n "$MUSIC_TOKEN" ]; then
    ADDITION_JSON="{\"root_folder_path\":\"/\",\"repo_id\":\"$DATASET_MUSIC_NAME\",\"repo_type\":\"dataset\",\"token\":\"$MUSIC_TOKEN\"}"
else
    ADDITION_JSON="{\"root_folder_path\":\"/\",\"repo_id\":\"$DATASET_MUSIC_NAME\",\"repo_type\":\"dataset\"}"
fi

# 2. 构建主 Payload
# 注意：addition 字段必须是转义后的 JSON 字符串
# 这里我们用 jq 来安全地生成最终 JSON
PAYLOAD=$(jq -n \
    --arg path "/ExternalData" \
    --arg driver "HuggingFace" \
    --arg add "$ADDITION_JSON" \
    '{mount_path: $path, order: 0, remark: "HF_Dataset", cache_expiration: 30, driver: $driver, addition: $add}')

log_proc "Sending mount request for: $DATASET_MUSIC_NAME"

# 3. 发送请求并捕获响应 (不再静默)
RESPONSE=$(curl -s -X POST http://127.0.0.1:5244/api/admin/storage/create \
    -H "Authorization: $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")

log_proc "API Response: $RESPONSE"

# 4. 立即验证是否挂载成功
CHECK=$(curl -s -H "Authorization: $TOKEN" http://127.0.0.1:5244/api/admin/storage/list | grep "ExternalData")
if [ -n "$CHECK" ]; then
    log_proc "✅ Storage mounted successfully!"
else
    log_proc "❌ Storage mount failed! Listing available drivers to debug..."
    curl -s -H "Authorization: $TOKEN" http://127.0.0.1:5244/api/admin/driver/list | jq -r '.data[].name' | grep -i "Hugging"
fi
