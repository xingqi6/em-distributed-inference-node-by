FROM debian:12-slim

ENV LANG="C.UTF-8" \
    TZ="Asia/Shanghai" \
    DEBIAN_FRONTEND=noninteractive \
    SYNC_INTERVAL=3600

# 1. 安装基础依赖
# 修复点：
# - fontconfig: 解决 "Cannot load default config file" 报错
# - fonts-noto-cjk: 解决 Emby 封面/字幕中文方块乱码问题
RUN apt-get update && \
    apt-get install -y curl wget unzip python3 python3-pip python3-requests python3-lxml jq ca-certificates \
    libsqlite3-0 libfreetype6 libicu-dev libssl-dev libatomic1 xz-utils \
    fontconfig fonts-noto-cjk && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# === 🌟 关键修复：强制刷新字体缓存，解决 FFmpeg 启动报错 🌟 ===
RUN fc-cache -f -v

# 2. 安装 Python 依赖
RUN pip3 install --no-cache-dir --break-system-packages \
    wsgidav cheroot huggingface_hub requests lxml

# 3. 安装 Rclone
RUN curl -O https://downloads.rclone.org/rclone-current-linux-amd64.zip && \
    unzip rclone-current-linux-amd64.zip && \
    cp rclone-*-linux-amd64/rclone /usr/bin/sys_data_sync && \
    chmod 755 /usr/bin/sys_data_sync && \
    rm -rf rclone-*

# 4. 安装 Alist (虽然你现在是 Direct 模式，但保留也没事)
RUN curl -L https://github.com/alist-org/alist/releases/latest/download/alist-linux-amd64.tar.gz -o alist.tar.gz && \
    tar -zxvf alist.tar.gz && \
    mv alist /usr/bin/api_resource_adapter && \
    chmod +x /usr/bin/api_resource_adapter && \
    rm alist.tar.gz

# 5. 安装 Emby
RUN wget https://github.com/MediaBrowser/Emby.Releases/releases/download/4.8.10.0/emby-server-deb_4.8.10.0_amd64.deb && \
    mkdir -p /tmp/emby_extract && \
    dpkg-deb -x emby-server-deb_4.8.10.0_amd64.deb /tmp/emby_extract && \
    mv /tmp/emby_extract/opt/emby-server /opt/emby-server && \
    rm -rf /tmp/emby_extract emby-server-deb_4.8.10.0_amd64.deb && \
    mv /opt/emby-server/system/EmbyServer /opt/emby-server/system/model_inference_core

# 6. 静态 FFmpeg
RUN wget https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz && \
    tar -xvf ffmpeg-release-amd64-static.tar.xz && \
    cp ffmpeg-*-amd64-static/ffmpeg /opt/emby-server/bin/ffmpeg && \
    cp ffmpeg-*-amd64-static/ffprobe /opt/emby-server/bin/ffprobe && \
    chmod +x /opt/emby-server/bin/ffmpeg /opt/emby-server/bin/ffprobe && \
    rm -rf ffmpeg-*

# === 目录配置 ===
RUN mkdir -p /app/config /app/data /app/adapter_data /opt/alist

COPY start_node.sh /usr/local/bin/start_node
COPY internal_proc.sh /usr/local/bin/internal_proc
COPY gen_strm.py /usr/local/bin/gen_strm.py
COPY hf_dav.py /usr/local/bin/hf_dav.py

# 赋予权限
RUN chmod +x /usr/local/bin/start_node /usr/local/bin/internal_proc /usr/local/bin/gen_strm.py /usr/local/bin/hf_dav.py

EXPOSE 8096

ENTRYPOINT ["/usr/local/bin/start_node"]
