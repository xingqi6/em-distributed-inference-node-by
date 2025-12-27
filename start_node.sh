#!/bin/bash

echo "========== Inference Node (Proxy Mode) =========="

# 1. WebDAV 备份恢复
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

# 2. 启动 HF WebDAV 代理 (本地 8080)
echo "Starting HF WebDAV Proxy..."
nohup python3 /usr/local/bin/hf_dav.py > /app/adapter_data/dav.log 2>&1 &

# 3. 启动 Alist
echo "Starting Alist..."
cd /opt/alist
nohup api_resource_adapter server > /app/adapter_data/alist.log 2>&1 &
sleep 5
api_resource_adapter admin set password

# 4. 挂载 (调用 internal_proc)
/usr/local/bin/internal_proc

# 5. 生成 .strm
echo "Generating .strm files..."
sleep 5
python3 /usr/local/bin/gen_strm.py

# 6. 自动备份
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

# 7. 启动 Emby
echo "Starting Engine..."
export LD_LIBRARY_PATH=/opt/emby-server/lib
exec /opt/emby-server/system/model_inference_core \
    -programdata /app/config \
    -ffdetect /opt/emby-server/bin/ffdetect \
    -ffmpeg /opt/emby-server/bin/ffmpeg \
    -ffprobe /opt/emby-server/bin/ffprobe \
    -restartexitcode 3
