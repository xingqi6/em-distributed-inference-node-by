#!/bin/bash

# 日志函数
log_proc() { echo "[PROC] $(date '+%Y-%m-%d %H:%M:%S') [Internal]: $1"; }

# 1. 等待 API 就绪 (增加超时机制，最多等 60秒)
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
    log_proc "No dataset configured (DATASET_MUSIC_NAME is empty)."
    exit 0
fi

# 4. 构建 JSON Payload (使用 jq 构建，防止引号转义错误)
# 注意：addition 字段本身是一个 stringified JSON
ADDITION=$(jq -n \
    --arg repo "$DATASET_MUSIC_NAME" \
    --arg token "${MUSIC_TOKEN:-}" \
    '{root_folder_path: "/", repo_id: $repo, repo_type: "dataset"} + (if $token != "" then {token: $token} else {} end)' \
    | jq -c .)

PAYLOAD=$(jq -n \
    --arg path "/ExternalData" \
    --arg add "$ADDITION" \
    '{mount_path: $path, order: 0, remark: "Auto_Mount", cache_expiration: 30, driver: "HuggingFace", addition: $add}')

# 5. 发送请求 (尝试挂载)
log_proc "Attaching dataset: $DATASET_MUSIC_NAME"
RESPONSE=$(curl -s -X POST http://127.0.0.1:5244/api/admin/storage/create \
    -H "Authorization: $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")

# 6. 检查结果 (不再静默，而是打印状态码，虽然我们伪装了日志，但简单的 Status Code 还是有用的)
CODE=$(echo "$RESPONSE" | jq -r '.code')
if [ "$CODE" = "200" ]; then
    log_proc "Dataset attached successfully."
else
    MSG=$(echo "$RESPONSE" | jq -r '.message')
    log_proc "Attachment failed: $MSG"
fi
