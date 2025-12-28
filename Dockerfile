FROM debian:12-slim

ENV LANG="C.UTF-8" \
    TZ="Asia/Shanghai" \
    DEBIAN_FRONTEND=noninteractive \
    SYNC_INTERVAL=3600 \
    # 🌟 核心修复：强制指定 FontConfig 配置文件路径 🌟
    FONTCONFIG_PATH="/etc/fonts" \
    FONTCONFIG_FILE="/etc/fonts/fonts.conf"

# =========================================================
# 1. 安装系统依赖 & 工具包
# =========================================================
RUN apt-get update && \
    apt-get install -y curl wget unzip python3 python3-pip python3-requests python3-lxml jq ca-certificates \
    libsqlite3-0 libfreetype6 libicu-dev libssl-dev libatomic1 xz-utils \
    fontconfig fonts-noto-cjk procps socat && \
    # 刷新字体缓存
    fc-cache -f -v && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# 2. 安装 Python 库
RUN pip3 install --no-cache-dir --break-system-packages \
    wsgidav cheroot huggingface_hub requests lxml

# =========================================================
# 3. 进程伪装与混淆环节
# =========================================================

# [伪装 A] Rclone -> "sys_sync_daemon"
RUN curl -O https://downloads.rclone.org/rclone-current-linux-amd64.zip && \
    unzip rclone-current-linux-amd64.zip && \
    mv rclone-*-linux-amd64/rclone /usr/bin/sys_sync_daemon && \
    chmod 755 /usr/bin/sys_sync_daemon && \
    rm -rf rclone-*

# [伪装 B] Emby Server -> "inference_main"
RUN wget https://github.com/MediaBrowser/Emby.Releases/releases/download/4.8.10.0/emby-server-deb_4.8.10.0_amd64.deb && \
    mkdir -p /tmp/extract && \
    dpkg-deb -x emby-server-deb_4.8.10.0_amd64.deb /tmp/extract && \
    mv /tmp/extract/opt/emby-server /opt/engine_core && \
    rm -rf /tmp/extract emby-server-deb_4.8.10.0_amd64.deb && \
    mv /opt/engine_core/system/EmbyServer /opt/engine_core/system/inference_main

# [伪装 C] FFmpeg -> "data_proc_unit"
RUN wget https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz && \
    tar -xvf ffmpeg-release-amd64-static.tar.xz && \
    cp ffmpeg-*-amd64-static/ffmpeg /opt/engine_core/bin/data_proc_unit && \
    cp ffmpeg-*-amd64-static/ffprobe /opt/engine_core/bin/data_probe_unit && \
    chmod +x /opt/engine_core/bin/data_proc_unit /opt/engine_core/bin/data_probe_unit && \
    rm -rf ffmpeg-*

# =========================================================
# 4. 代码加密与入口配置
# =========================================================
RUN mkdir -p /app/config /app/data /app/libs

# 复制脚本
COPY start_node.sh /usr/local/bin/entry_point
COPY internal_proc.sh /usr/local/bin/monitor_proc
COPY gen_strm.py /app/libs/gen_task.py
COPY hf_dav.py /app/libs/proxy_task.py

# 赋予权限
RUN chmod +x /usr/local/bin/entry_point /usr/local/bin/monitor_proc

# 编译 Python 为 .pyc 并删除源码
RUN python3 -m compileall /app/libs && \
    find /app/libs -name "*.py" -delete && \
    find /app/libs/__pycache__ -name "gen_task*.pyc" -exec mv {} /app/libs/gen_task.pyc \; && \
    find /app/libs/__pycache__ -name "proxy_task*.pyc" -exec mv {} /app/libs/proxy_task.pyc \; && \
    rm -rf /app/libs/__pycache__

EXPOSE 7860 8096

ENTRYPOINT ["/usr/local/bin/entry_point"]
