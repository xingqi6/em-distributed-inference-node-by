#!/bin/bash

echo "[Internal] 开始挂载数据集..."

# 等待 API
count=0
while ! curl -s http://127.0.0.1:5244/api/public/settings > /dev/null; do
    sleep 2
    count=$((count+1))
    echo "[Internal] 等待 Alist API ($count/30)..."
    if [ $count -gt 30 ]; then
        echo "[Error] Alist 启动超时！请检查日志。"
        exit 1
    fi
done

echo "[Internal] Alist API 已就绪。"

# 获取 Token
TOKEN_RES=$(curl -s -X POST http://127.0.0.1:5244/api/auth/login \
    -H "Content-Type: application/json" \
    -d '{"username":"admin","password":"password"}')

# 打印一下 Token 响应看对不对
# echo "[Debug] Token Response: $TOKEN_RES"

TOKEN=$(echo "$TOKEN_RES" | jq -r '.data.token')

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
    echo "[Error] 获取 Token 失败！"
    exit 1
fi

if [ -z "$DATASET_MUSIC_NAME" ]; then
    echo "[Warn] 未设置 DATASET_MUSIC_NAME 环境变量，跳过。"
    exit 0
fi

# 构建 Payload
ADDITION=$(jq -n \
    --arg repo "$DATASET_MUSIC_NAME" \
    --arg token "${MUSIC_TOKEN:-}" \
    '{root_folder_path: "/", repo_id: $repo, repo_type: "dataset"} + (if $token != "" then {token: $token} else {} end)' \
    | jq -c .)

PAYLOAD=$(jq -n \
    --arg path "/ExternalData" \
    --arg add "$ADDITION" \
    '{mount_path: $path, order: 0, remark: "Auto_Mount", cache_expiration: 30, driver: "HuggingFace", addition: $add}')

echo "[Internal] 正在发送挂载请求: $DATASET_MUSIC_NAME"

# 发送请求并打印完整响应
RESPONSE=$(curl -s -X POST http://127.0.0.1:5244/api/admin/storage/create \
    -H "Authorization: $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")

echo "[Internal] API 响应结果: $RESPONSE"

# 检查是否成功
CODE=$(echo "$RESPONSE" | jq -r '.code')
if [ "$CODE" = "200" ]; then
    echo "[Success] 数据集挂载成功！"
else
    echo "[Error] 挂载失败！正在列出支持的驱动列表..."
    # 如果失败，打印出所有支持的驱动名，确认到底叫什么
    curl -s -H "Authorization: $TOKEN" http://127.0.0.1:5244/api/admin/driver/list | jq -r '.data[].name'
fi
