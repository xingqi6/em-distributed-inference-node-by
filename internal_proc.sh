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

# === 调试：打印所有支持的驱动名 ===
log_proc "Available drivers in Alist:"
curl -s -H "Authorization: $TOKEN" http://127.0.0.1:5244/api/admin/driver/list | jq -r '.data[].name'

# === 尝试挂载 ===
# Alist 最新版通常使用 "WebDav" (注意大小写)
DRIVER_NAME="WebDav"

log_proc "Using driver: '$DRIVER_NAME'"

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

log_proc "Mount response: $RESPONSE"
