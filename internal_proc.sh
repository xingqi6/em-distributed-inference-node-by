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

# 构建挂载 Payload
ADDITION=$(jq -n \
    --arg repo "$DATASET_MUSIC_NAME" \
    --arg token "${MUSIC_TOKEN:-}" \
    '{root_folder_path: "/", repo_id: $repo, repo_type: "dataset"} + (if $token != "" then {token: $token} else {} end)' \
    | jq -c .)

PAYLOAD=$(jq -n \
    --arg path "/ExternalData" \
    --arg add "$ADDITION" \
    '{mount_path: $path, order: 0, remark: "HF_Dataset", cache_expiration: 30, driver: "HuggingFace", addition: $add}')

log_proc "Mounting dataset: $DATASET_MUSIC_NAME"
curl -s -X POST http://127.0.0.1:5244/api/admin/storage/create \
    -H "Authorization: $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" > /dev/null

log_proc "Mount request sent."
