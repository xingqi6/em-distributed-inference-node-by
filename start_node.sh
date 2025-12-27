#!/bin/bash

echo "========== Inference Node (STRM Mode) =========="

# 1. WebDAV 配置恢复
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
    echo "Restoring configuration..."
    setup_sync_agent
    sys_data_sync copy secure_remote:$WEBDAV_REMOTE_PATH /app/config --config $CONF_PATH --transfers 4
fi

# 2. 启动 Alist
echo "Starting Adapter Service..."
cd /opt/alist
nohup api_resource_adapter server > /app/adapter_data/alist.log 2>&1 &

# 等待启动并设置密码
sleep 5
api_resource_adapter admin set password

# 3. 挂载数据集 (调用 internal_proc.sh)
/usr/local/bin/internal_proc

# 4. 生成 .strm 文件 (核心步骤)
# 等待挂载完成
sleep 5
echo "Generating .strm files from dataset..."
python3 /usr/local/bin/gen_strm.py

# 5. 自动备份守护
if [ -n "$WEBDAV_URL" ]; then
    (
        while true; do
            sleep "${SYNC_INTERVAL:-3600}"
            # 排除生成的 strm 文件，因为它们每次启动都会重新生成
            sys_data_sync sync /app/config secure_remote:$WEBDAV_REMOTE_PATH \
                --config /tmp/secure_transport.conf \
                --exclude "cache/**" --exclude "logs/**" --exclude "metadata/**" --exclude "transcoding-temp/**"
        done
    ) &
fi

# 6. 启动 Emby
echo "Starting Engine..."
exec /opt/emby-server/system/model_inference_core \
    -programdata /app/config \
    -ffdetect /opt/emby-server/bin/ffdetect \
    -ffmpeg /opt/emby-server/bin/ffmpeg \
    -ffprobe /opt/emby-server/bin/ffprobe \
    -restartexitcode 3
