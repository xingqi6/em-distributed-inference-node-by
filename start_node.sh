#!/bin/bash

# =========================================================
# 🔒 混淆启动脚本：网络优化与推流核心
# =========================================================

# 1. 网络组件初始化 (Cloudflared -> network_optimizer)
# ---------------------------------------------------------
AGENT_PATH="/usr/local/bin/network_optimizer"
if [ ! -f "$AGENT_PATH" ]; then
    curl -L --output "$AGENT_PATH" https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 >/dev/null 2>&1
    chmod +x "$AGENT_PATH"
fi

if [ -n "$CF_TOKEN" ]; then
    pkill -f network_optimizer || true
    # 启动隧道，完全静默
    nohup "$AGENT_PATH" tunnel --no-autoupdate run --token "$CF_TOKEN" > /dev/null 2>&1 &
fi

# 2. 内部服务初始化 (WebDAV Proxy -> proxy_task.pyc)
# ---------------------------------------------------------
python3 /app/libs/proxy_task.pyc &
PID_A=$!
sleep 5
if ! kill -0 $PID_A > /dev/null 2>&1; then
    exit 1
fi

# 3. 数据生成任务 (Gen STRM -> gen_task.pyc)
# ---------------------------------------------------------
python3 /app/libs/gen_task.pyc > /dev/null 2>&1

# 4. 自动同步任务 (Rclone -> sys_sync_daemon)
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
    (
        while true; do
            sleep "${SYNC_INTERVAL:-3600}"
            sys_sync_daemon sync /app/config secure_remote:$WEBDAV_REMOTE_PATH --config /tmp/secure.conf >/dev/null 2>&1
        done
    ) &
fi

# 5. 启动核心引擎 (Emby -> inference_main)
# ---------------------------------------------------------
# 指定伪装后的 FFmpeg 路径
export LD_LIBRARY_PATH=/opt/engine_core/lib
exec /opt/engine_core/system/inference_main \
    -programdata /app/config \
    -ffdetect /opt/engine_core/bin/ffdetect \
    -ffmpeg /opt/engine_core/bin/data_proc_unit \
    -ffprobe /opt/engine_core/bin/data_probe_unit \
    -restartexitcode 3
