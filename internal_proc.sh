#!/bin/bash

log_proc() { echo "[Internal] $1"; }

# 等待服务启动
log_proc "Waiting for Alist..."
for i in {1..30}; do
    if curl -s http://127.0.0.1:5244/api/public/settings > /dev/null; then
        break
    fi
    sleep 2
done

log_proc "Waiting for WebDAV Proxy..."
for i in {1..30}; do
    if curl -s http://127.0.0.1:8080/ > /dev/null; then
        log_proc "✅ Proxy ready"
        break
    fi
    sleep 2
    if [ $i -eq 30 ]; then
        log_proc "❌ Proxy timeout!"
        python3 -c "from huggingface_hub import HfApi; print(list(HfApi().list_repo_tree('$DATASET_MUSIC_NAME', repo_type='dataset'))[:5])"
        exit 1
    fi
done

# 登录 Alist
TOKEN=$(curl -s -X POST http://127.0.0.1:5244/api/auth/login \
    -H "Content-Type: application/json" \
    -d '{"username":"admin","password":"password"}' | jq -r '.data.token')

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
    log_proc "❌ Failed to get Alist token"
    exit 1
fi

# 检测可用驱动
log_proc "Detecting WebDAV driver..."
DRIVERS=$(curl -s -H "Authorization: $TOKEN" http://127.0.0.1:5244/api/admin/driver/list)
log_proc "Available drivers: $(echo $DRIVERS | jq -r '.data[].name' | tr '\n' ', ')"

# 尝试常见的驱动名称
for DRIVER_NAME in "WebDAV" "WebDav" "Webdav" "webdav"; do
    MATCH=$(echo "$DRIVERS" | jq -r ".data[] | select(.name == \"$DRIVER_NAME\") | .name")
    if [ -n "$MATCH" ]; then
        log_proc "✅ Using driver: $DRIVER_NAME"
        break
    fi
done

if [ -z "$DRIVER_NAME" ]; then
    log_proc "❌ No WebDAV driver found!"
    exit 1
fi

# 挂载
PAYLOAD=$(cat <<EOF
{
  "mount_path": "/ExternalData",
  "order": 0,
  "remark": "HF_Proxy",
  "cache_expiration": 30,
  "driver": "$DRIVER_NAME",
  "addition": "{\"root_folder_path\":\"/\",\"url\":\"http://127.0.0.1:8080\",\"username\":\"admin\",\"password\":\"admin\"}"
}
EOF
)

log_proc "Mounting..."
RESPONSE=$(curl -s -X POST http://127.0.0.1:5244/api/admin/storage/create \
    -H "Authorization: $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")

CODE=$(echo "$RESPONSE" | jq -r '.code')
MSG=$(echo "$RESPONSE" | jq -r '.message')

if [ "$CODE" = "200" ]; then
    log_proc "✅ Mount successful"
else
    log_proc "❌ Mount failed: $MSG"
    log_proc "Response: $RESPONSE"
fi
