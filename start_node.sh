#!/bin/bash

echo "========== Inference Node (Native Mount) =========="

# 0. 权限检查
if [ -e /dev/fuse ]; then
    chmod 777 /dev/fuse
else
    echo "Fatal: /dev/fuse missing. Hugging Face mount will fail."
fi

# 1. WebDAV 备份恢复 (Rclone)
setup_sync_agent() {
    mkdir -p /app/config/sync_conf
    CONF_PATH="/tmp/secure_transport.conf"
    cat <<EOF > $CONF_PATH
[secure_remote]
type = webdav
url = $WEBDAV_URL
vendor = other
user = $WEBDAV_USER
pass = $(sys_data_sync obscure "$WEBDAV_PASSWORD")
EOF
}

if [ -n "$WEBDAV_URL" ]; then
    echo "Syncing configuration..."
    setup_sync_agent
    sys_data_sync copy secure_remote:$WEBDAV_REMOTE_PATH /app/config --config $CONF_PATH --transfers 4
fi

# 2. 挂载 Hugging Face 数据集 (取代 Alist)
if [ -n "$DATASET_MUSIC_NAME" ]; then
    echo "Mounting Dataset: $DATASET_MUSIC_NAME"
    mkdir -p /app/data/ExternalData
    
    # 如果有 Token，登录 (用于私有数据集)
    if [ -n "$MUSIC_TOKEN" ]; then
        huggingface-cli login --token "$MUSIC_TOKEN"
    fi

    # === 核心黑科技 ===
    # 使用 huggingface-cli 直接挂载
    # --quiet: 减少日志
    # & : 后台运行
    nohup huggingface-cli mount \
        "$DATASET_MUSIC_NAME" \
        /app/data/ExternalData \
        --repo-type dataset \
        --quiet > /app/mount.log 2>&1 &
        
    echo "Dataset mounted at /app/data/ExternalData"
else
    echo "No dataset configured."
fi

# 3. 自动备份守护 (Rclone)
if [ -n "$WEBDAV_URL" ]; then
    (
        while true; do
            sleep "${SYNC_INTERVAL:-3600}"
            sys_data_sync sync /app/config secure_remote:$WEBDAV_REMOTE_PATH \
                --config /tmp/secure_transport.conf \
                --exclude "cache/**" --exclude "logs/**" --exclude "metadata/**" --exclude "transcoding-temp/**"
        done
    ) &
fi

# 4. 启动 Emby
echo "Starting Engine..."
exec /opt/emby-server/system/model_inference_core \
    -programdata /app/config \
    -ffdetect /opt/emby-server/bin/ffdetect \
    -ffmpeg /opt/emby-server/bin/ffmpeg \
    -ffprobe /opt/emby-server/bin/ffprobe \
    -restartexitcode 3
