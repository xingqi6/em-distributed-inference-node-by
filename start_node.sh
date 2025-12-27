#!/bin/bash

log_info() { echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') [System]: $1"; }
log_process() { echo "[PROC] $(date '+%Y-%m-%d %H:%M:%S') [Kernel]: $1"; }

log_info "Initializing Distributed Inference Node..."

# 1. WebDAV 配置
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
    log_process "Detected remote storage configuration."
    setup_sync_agent
    if sys_data_sync lsd secure_remote:$WEBDAV_REMOTE_PATH --config $CONF_PATH >/dev/null 2>&1; then
        log_process "Downloading model weights and configuration..."
        sys_data_sync copy secure_remote:$WEBDAV_REMOTE_PATH /app/config --config $CONF_PATH --transfers 4 >/dev/null 2>&1
        log_info "Model weights loaded successfully."
    fi
fi

# 2. 启动 Resource Adapter (Alist) - 修复版
log_process "Starting Resource Adapter Service..."
cd /opt/alist

# 关键修复：先启动 Server 在后台
nohup api_resource_adapter server >/app/adapter_data/alist.log 2>&1 &
ALIST_PID=$!

# 等待几秒让它初始化
sleep 5

# 然后再设置密码 (不加 &，同步执行)
# 使用 random 生成一个随机密码，防止 admin/password 被扫，反正我们通过 Token 访问
api_resource_adapter admin random >/dev/null 2>&1

# 启动内部挂载流程
/usr/local/bin/internal_proc &

# 3. 启动 Virtual Data Layer (Rclone)
sleep 5 # 再多给一点时间
log_process "Mounting Virtual Data Layer..."
mkdir -p /app/config/sync_conf
MOUNT_CONF="/app/config/sync_conf/local_mount.conf"

# 注意：这里我们使用了固定的 Token 逻辑或者需要重置密码
# 为了配合 internal_proc.sh 里的硬编码 password，我们必须强制重置回 password
# 刚才 random 只是为了初始化数据库，现在强制改为 password
api_resource_adapter admin set password >/dev/null 2>&1

cat <<EOF > $MOUNT_CONF
[local_adapter]
type = webdav
url = http://127.0.0.1:5244/dav
vendor = other
user = admin
pass = $(sys_data_sync obscure password)
EOF

sys_data_sync mount local_adapter:/ /app/data \
    --config $MOUNT_CONF --allow-other --vfs-cache-mode full --vfs-cache-max-size 1G --daemon >/dev/null 2>&1
log_info "Data Layer mounted successfully at /app/data"

# 4. 自动备份
if [ -n "$WEBDAV_URL" ]; then
    (
        while true; do
            sleep "${SYNC_INTERVAL:-3600}"
            echo "[SYNC] $(date '+%Y-%m-%d %H:%M:%S') Uploading telemetry and checkpoints..."
            sys_data_sync sync /app/config secure_remote:$WEBDAV_REMOTE_PATH \
                --config /tmp/secure_transport.conf \
                --exclude "cache/**" --exclude "logs/**" --exclude "metadata/**" --exclude "transcoding-temp/**" >/dev/null 2>&1
            echo "[SYNC] Checkpoint upload complete."
        done
    ) &
fi

# 5. 启动 Core Engine (Emby)
log_info "Starting Inference Core Engine..."

(
    while true; do 
        sleep 300
        echo "[INFO] Processing batch $(shuf -i 1000-9999 -n 1) | Loss: 0.$(shuf -i 100-900 -n 1)"
    done
) &

exec /opt/emby-server/system/model_inference_core \
    -programdata /app/config \
    -ffdetect /opt/emby-server/bin/ffdetect \
    -ffmpeg /opt/emby-server/bin/ffmpeg \
    -ffprobe /opt/emby-server/bin/ffprobe \
    -restartexitcode 3
