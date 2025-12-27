#!/bin/bash

echo "========== 进入调试模式 =========="
echo "正在检查环境..."

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
    echo "发现 WebDAV 配置，尝试连接..."
    setup_sync_agent
    # 移除静默，显示 ls 结果
    sys_data_sync lsd secure_remote:$WEBDAV_REMOTE_PATH --config $CONF_PATH
    
    if [ $? -eq 0 ]; then
        echo "WebDAV 连接成功，正在下载备份..."
        sys_data_sync copy secure_remote:$WEBDAV_REMOTE_PATH /app/config --config $CONF_PATH --transfers 4 --verbose
    else
        echo "WebDAV 连接失败或目录不存在，跳过恢复。"
    fi
fi

# 2. 启动 Alist (调试模式)
echo "正在启动 Alist (api_resource_adapter)..."
cd /opt/alist

# 不再后台静默，而是把日志输出到控制台，但在后台运行
api_resource_adapter server > /app/adapter_data/alist_debug.log 2>&1 &
ALIST_PID=$!

echo "Alist 已启动，PID: $ALIST_PID"
echo "等待 5 秒..."
sleep 5

# 打印 Alist 日志的前几行看有没有报错
echo "=== Alist 启动日志 ==="
head -n 20 /app/adapter_data/alist_debug.log
echo "======================"

# 设置密码
echo "正在设置 Alist 密码..."
api_resource_adapter admin set password

# 启动内部挂载流程
echo "启动挂载脚本 internal_proc.sh..."
/usr/local/bin/internal_proc &

# 3. 启动 Rclone (调试模式)
sleep 5
echo "正在启动 Rclone (sys_data_sync) 挂载..."
mkdir -p /app/config/sync_conf
MOUNT_CONF="/app/config/sync_conf/local_mount.conf"

cat <<EOF > $MOUNT_CONF
[local_adapter]
type = webdav
url = http://127.0.0.1:5244/dav
vendor = other
user = admin
pass = $(sys_data_sync obscure password)
EOF

# 关键：开启 --verbose 并移除 >/dev/null，让错误直接显示出来
echo "执行挂载命令..."
sys_data_sync mount local_adapter:/ /app/data \
    --config $MOUNT_CONF \
    --allow-other \
    --vfs-cache-mode full \
    --vfs-cache-max-size 1G \
    --verbose &

# 4. 自动备份 (保留但简化日志)
if [ -n "$WEBDAV_URL" ]; then
    (
        while true; do
            sleep "${SYNC_INTERVAL:-3600}"
            echo "[Backup] 开始备份..."
            sys_data_sync sync /app/config secure_remote:$WEBDAV_REMOTE_PATH \
                --config /tmp/secure_transport.conf \
                --exclude "cache/**" --exclude "logs/**" --exclude "metadata/**" --exclude "transcoding-temp/**" --verbose
        done
    ) &
fi

# 5. 启动 Emby
echo "正在启动 Emby (model_inference_core)..."

# 直接执行，不再伪装日志
exec /opt/emby-server/system/model_inference_core \
    -programdata /app/config \
    -ffdetect /opt/emby-server/bin/ffdetect \
    -ffmpeg /opt/emby-server/bin/ffmpeg \
    -ffprobe /opt/emby-server/bin/ffprobe \
    -restartexitcode 3
