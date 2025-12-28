#!/bin/bash

# =========================================================
# 🌟 Cloudflare Tunnel 启动逻辑 (读取环境变量 CF_TOKEN) 🌟
# =========================================================

echo "🚀 [Network] 初始化 Cloudflare Tunnel..."

# 1. 下载 cloudflared (如果不存在)
if [ ! -f "/usr/local/bin/cloudflared" ]; then
    echo "📥 [Network] 正在下载 cloudflared..."
    curl -L --output cloudflared https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
    chmod +x cloudflared
    mv cloudflared /usr/local/bin/cloudflared
fi

# 2. 启动隧道
# 注意：这里读取环境变量 $CF_TOKEN，请在 HF Settings -> Secrets 中设置
if [ -n "$CF_TOKEN" ]; then
    echo "✅ [Network] 检测到 CF_TOKEN，正在启动加速隧道..."
    
    # 清理可能残留的进程
    pkill -f cloudflared || true
    
    # 后台启动，日志重定向防止刷屏
    nohup cloudflared tunnel --no-autoupdate run --token "$CF_TOKEN" > /dev/null 2>&1 &
    
    echo "✅ [Network] Cloudflare Tunnel 已在后台运行！请使用你的自定义域名访问。"
else
    echo "⚠️ [Network] 未检测到 CF_TOKEN 环境变量，跳过加速启动。"
fi

echo "========================================================"
echo "   网络配置完成，开始启动 Emby 服务..."
echo "========================================================"

# =========================================================
# 👇 下面是原有的启动逻辑 (保持不变) 👇
# =========================================================

echo "========== Inference Node (Direct WebDAV Mode) =========="

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

# 2. 启动 HF WebDAV 代理
echo "Starting HF WebDAV Proxy..."
python3 /usr/local/bin/hf_dav.py &
DAV_PID=$!
echo "Proxy PID: $DAV_PID"

# 等待代理启动
sleep 5
if ! kill -0 $DAV_PID > /dev/null 2>&1; then
    echo "❌ Fatal Error: WebDAV proxy crashed!"
    exit 1
fi

# 检查代理是否可访问
for i in {1..10}; do
    if curl -s http://127.0.0.1:8080/ > /dev/null 2>&1; then
        echo "✅ WebDAV proxy is ready"
        break
    fi
    sleep 2
    if [ $i -eq 10 ]; then
        echo "❌ WebDAV proxy not accessible!"
        exit 1
    fi
done

# 3. 生成 .strm（直接从 WebDAV 读取）
echo "Generating .strm files..."
python3 /usr/local/bin/gen_strm.py

# 4. 自动备份
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

# 5. 启动 Emby
echo "Starting Emby Server..."
export LD_LIBRARY_PATH=/opt/emby-server/lib
exec /opt/emby-server/system/model_inference_core \
    -programdata /app/config \
    -ffdetect /opt/emby-server/bin/ffdetect \
    -ffmpeg /opt/emby-server/bin/ffmpeg \
    -ffprobe /opt/emby-server/bin/ffprobe \
    -restartexitcode 3
