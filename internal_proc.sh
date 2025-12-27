#!/bin/bash
sleep 5
while ! curl -s http://127.0.0.1:5244/api/public/settings > /dev/null; do sleep 2; done

AUTH_TOKEN=$(curl -s -X POST http://127.0.0.1:5244/api/auth/login \
    -H "Content-Type: application/json" \
    -d '{"username":"admin","password":"password"}' | jq -r '.data.token')

if [ -z "$DATASET_MUSIC_NAME" ]; then exit 0; fi

ADDITION_CONFIG="{\"root_folder_path\":\"/\",\"repo_id\":\"$DATASET_MUSIC_NAME\",\"repo_type\":\"dataset\""
if [ -n "$MUSIC_TOKEN" ]; then ADDITION_CONFIG="$ADDITION_CONFIG,\"token\":\"$MUSIC_TOKEN\""; fi
ADDITION_CONFIG="$ADDITION_CONFIG}"

# 静默挂载
curl -s -X POST http://127.0.0.1:5244/api/admin/storage/create \
    -H "Authorization: $AUTH_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{ "mount_path": "/ExternalData", "order": 0, "remark": "Remote_Source", "cache_expiration": 30, "driver": "HuggingFace", "addition": '"$ADDITION_CONFIG"' }' > /dev/null
