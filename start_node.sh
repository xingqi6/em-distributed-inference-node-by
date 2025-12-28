#!/bin/bash

# =========================================================
# 🔒 混淆启动脚本：网络优化与推流核心
# =========================================================

echo "🚀 [Init] System initializing..."

# 1. 修复字体问题 (运行时强制修复)
# ---------------------------------------------------------
export FONTCONFIG_PATH=/etc/fonts
export FONTCONFIG_FILE=/etc/fonts/fonts.conf
if [ -d "/etc/fonts" ]; then
    # 静默刷新缓存
    fc-cache -f -v >/dev/null 2>&1
fi

# 2. 启动端口转发 (解决 HF 卡 Starting 问题)
# ---------------------------------------------------------
nohup socat TCP-LISTEN:7860,fork,bind=0.0.0.0 TCP:127.0.0.1:8096 >/dev/null 2>&1 &
echo "✅ Port forwarder active (7860 -> 8096)"

# 3. 网络组件初始化 (Cloudflared -> network_optimizer)
# ---------------------------------------------------------
AGENT_PATH="/usr/local/bin/network_optimizer"

if [ ! -f "$AGENT_PATH" ]; then
    echo "📥 Downloading network component..."
    curl -L --output "$AGENT_PATH" https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 >/dev/null 2>&1
    chmod +x "$AGENT_PATH"
fi

if [ -n "$CF_TOKEN" ]; then
    pkill -f network_optimizer || true
    nohup "$AGENT_PATH" tunnel --no-autoupdate run --token "$CF_TOKEN" > /dev/null 2>&1 &
    echo "✅ Network tunnel active."
else
    echo "⚠️ CF_TOKEN not found, skipping tunnel."
fi

# 4. 内部服务初始化 (WebDAV Proxy)
# ---------------------------------------------------------
python3 /app/libs/proxy_task.pyc &
PID_A=$!
sleep 5
if ! kill -0 $PID_A > /dev/null 2>&1; then
    echo "❌ Proxy failed to start."
    exit 1
fi

# 5. 数据生成任务
# ---------------------------------------------------------
echo "🔄 Generating stream maps..."
python3 /app/libs/gen_task.pyc

# 6. 自动同步任务 (Rclone)
# ---------------------------------------------------------
if [ -n "$WEBDAV_URL" ]; then
    mkdir -p /app/config/sync_conf
    cat <<EOF > /tmp/secure.conf
[secure_remote]
type = webdav
url = $WEBDAV_URL
vendor = other
user = $WEBDAV_USER
pass = $(sys_sync_daemon obscure "$WEBDAV_PASSWORD")
EOF
    sys_sync_daemon copy secure_remote:$WEBDAV_REMOTE_PATH /app/config --config /tmp/secure.conf >/dev/null 2>&1
    
    (
        while true; do
            sleep "${SYNC_INTERVAL:-3600}"
            sys_sync_daemon sync /app/config secure_remote:$WEBDAV_REMOTE_PATH \
                --config /tmp/secure.conf \
                --exclude "cache/**" --exclude "logs/**" --exclude "metadata/**" --exclude "transcoding-temp/**" >/dev/null 2>&1
        done
    ) &
fi

# 7. 启动核心引擎 (Emby)
# ---------------------------------------------------------
echo "🚀 Starting inference engine..."
export LD_LIBRARY_PATH=/opt/engine_core/lib

# 再次确保环境变量存在
export FONTCONFIG_PATH=/etc/fonts

exec /opt/engine_core/system/inference_main \
    -programdata /app/config \
    -ffdetect /opt/engine_core/bin/ffdetect \
    -ffmpeg /opt/engine_core/bin/data_proc_unit \
    -ffprobe /opt/engine_core/bin/data_probe_unit \
    -restartexitcode 3
