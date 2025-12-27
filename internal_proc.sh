#!/bin/bash

log_proc() { echo "[Internal] $1"; }

# 1. 等待 Alist
log_proc "Waiting for Alist API..."
while ! curl -s http://127.0.0.1:5244/api/public/settings > /dev/null; do
    sleep 2
done

# 2. 等待 WebDAV 代理
log_proc "Waiting for HF WebDAV Proxy (port 8080)..."
count=0
while ! curl -s http://127.0.0.1:8080/ > /dev/null; do
    sleep 2
    count=$((count+1))
    if [ $count -gt 30 ]; then
        log_proc "❌ Proxy timeout! Check python logs."
        exit 1
    fi
done
log_proc "✅ Proxy is ready."

TOKEN=$(curl -s -X POST http://127.0.0.1:5244/api/auth/login \
    -H "Content-Type: application/json" \
    -d '{"username":"admin","password":"password"}' | jq -r '.data.token')

# === 智能获取驱动名称 ===
log_proc "Detecting WebDAV driver name..."
DRIVER_LIST=$(curl -s -H "Authorization: $TOKEN" http://127.0.0.1:5244/api/admin/driver/list)
# 查找名字包含 "WebDAV" 的驱动 (忽略大小写)
DRIVER_NAME=$(echo "$DRIVER_LIST" | jq -r '.data[] | select(.name | test("WebDAV"; "i")) | .name' | head -n 1)

if [ -z "$DRIVER_NAME" ]; then
    log_proc "❌ Error: WebDAV driver not found in Alist! Available drivers:"
    echo "$DRIVER_LIST" | jq -r '.data[].name'
    # 尝试硬编码备选
    DRIVER_NAME="WebDAV"
fi

log_proc "✅ Found driver: '$DRIVER_NAME'"

# 3. 挂载本地 WebDAV
# 驱动: 自动检测的 DRIVER_NAME
# 地址: http://127.0.0.1:8080
# 用户名/密码: admin (hf_dav.py设置了允许匿名，但Alist可能要求非空)
PAYLOAD=$(jq -n \
    --arg path "/ExternalData" \
    --arg driver "$DRIVER_NAME" \
    --arg url "http://127.0.0.1:8080" \
    '{mount_path: $path, order: 0, remark: "HF_Proxy", cache_expiration: 30, driver: $driver, addition: "{\"root_folder_path\":\"/\",\"url\":$url,\"username\":\"admin\",\"password\":\"admin\"}"}')

log_proc "Mounting Local WebDAV Proxy..."
RESPONSE=$(curl -s -X POST http://127.0.0.1:5244/api/admin/storage/create \
    -H "Authorization: $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")

CODE=$(echo "$RESPONSE" | jq -r '.code')
if [ "$CODE" = "200" ]; then
    log_proc "✅ Dataset mounted successfully!"
else
    MSG=$(echo "$RESPONSE" | jq -r '.message')
    log_proc "❌ Mount failed: $MSG"
fi
