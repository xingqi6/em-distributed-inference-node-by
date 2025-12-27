#!/bin/bash

echo "========== Inference Node (Sync Mode) =========="

# 0. 环境检查
# 既然 FUSE 不可用，我们就不检查它了，直接用下载模式

# 1. WebDAV 备份恢复 (用于恢复 Emby 配置)
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

# 2. 同步 Hugging Face 数据集 (取代 Mount)
if [ -n "$DATASET_MUSIC_NAME" ]; then
    echo "Syncing Dataset: $DATASET_MUSIC_NAME"
    
    # 如果有 Token，登录
    if [ -n "$MUSIC_TOKEN" ]; then
        huggingface-cli login --token "$MUSIC_TOKEN"
    fi

    # === 核心修改 ===
    # 使用 download 代替 mount
    # --local-dir: 指定下载目录
    # --repo-type dataset: 指定是数据集
    # & : 后台运行，Emby 启动后，文件会陆续出现
    
    nohup huggingface-cli download \
        "$DATASET_MUSIC_NAME" \
        --local-dir /app/data/ExternalData \
        --repo-type dataset \
        --quiet > /app/sync.log 2>&1 &
        
    echo "Dataset syncing started at /app/data/ExternalData"
else
    echo "No dataset configured."
fi

# 3. 自动备份守护 (Rclone)
if [ -n "$WEBDAV_URL" ]; then
    (
        while true; do
            sleep "${SYNC_INTERVAL:-3600}"
            # 排除 ExternalData 文件夹，防止把下载的电影备份回 WebDAV
            sys_data_sync sync /app/config secure_remote:$WEBDAV_REMOTE_PATH \
                --config /tmp/secure_transport.conf \
                --exclude "cache/**" --exclude "logs/**" --exclude "metadata/**" --exclude "transcoding-temp/**" --exclude "ExternalData/**"
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
