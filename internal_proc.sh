#!/bin/bash
log_proc() { echo "[Internal] $1"; }

# 1. 等待 Alist API
log_proc "Waiting for Alist API..."
while ! curl -s http://127.0.0.1:5244/api/public/settings > /dev/null; do
    sleep 2
done

# 2. 等待本地 WebDAV 代理启动
log_proc "Waiting for HF WebDAV Proxy..."
while ! curl -s http://127.0.0.1:8080/ > /dev/null; do
    sleep 2
done

TOKEN=$(curl -s -X POST http://127.0.0.1:5244/api/auth/login \
    -H "Content-Type: application/json" \
    -d '{"username":"admin","password":"password"}' | jq -r '.data.token')

# 3. 挂载本地 WebDAV
# 驱动: WebDAV
# 地址: http://127.0.0.1:8080
# 用户名/密码: 随意 (代理脚本设置了允许匿名)
PAYLOAD=$(jq -n \
    --arg path "/ExternalData" \
    --arg url "http://127.0.0.1:8080" \
    '{mount_path: $path, order: 0, remark: "HF_Proxy", cache_expiration: 30, driver: "WebDAV", addition: "{\"root_folder_path\":\"/\",\"url\":$url,\"username\":\"admin\",\"password\":\"admin\"}"}')

log_proc "Mounting Local WebDAV Proxy..."
RESPONSE=$(curl -s -X POST http://127.0.0.1:5244/api/admin/storage/create \
    -H "Authorization: $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")

log_proc "Mount response: $RESPONSE"
