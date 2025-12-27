# 使用 Debian 12 (为了兼容性)
FROM debian:12-slim

ENV LANG="C.UTF-8" \
    TZ="Asia/Shanghai" \
    DEBIAN_FRONTEND=noninteractive \
    SYNC_INTERVAL=3600

# 1. 安装基础依赖
# 新增: python3-requests (用于 strm 生成脚本)
RUN apt-get update && \
    apt-get install -y curl wget unzip python3 python3-pip python3-requests jq ca-certificates \
    libsqlite3-0 libfontconfig1 libfreetype6 libicu-dev libssl-dev libatomic1 xz-utils && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# 2. 安装 Rclone (仅用于 WebDAV 备份配置)
RUN curl -O https://downloads.rclone.org/rclone-current-linux-amd64.zip && \
    unzip rclone-current-linux-amd64.zip && \
    cp rclone-*-linux-amd64/rclone /usr/bin/sys_data_sync && \
    chmod 755 /usr/bin/sys_data_sync && \
    rm -rf rclone-*

# 3. 安装 Alist (最新版，确保支持 HuggingFace)
RUN curl -L https://github.com/alist-org/alist/releases/latest/download/alist-linux-amd64.tar.gz -o alist.tar.gz && \
    tar -zxvf alist.tar.gz && \
    mv alist /usr/bin/api_resource_adapter && \
    chmod +x /usr/bin/api_resource_adapter && \
    rm alist.tar.gz

# 4. 安装 Emby
RUN wget https://github.com/MediaBrowser/Emby.Releases/releases/download/4.8.10.0/emby-server-deb_4.8.10.0_amd64.deb && \
    mkdir -p /tmp/emby_extract && \
    dpkg-deb -x emby-server-deb_4.8.10.0_amd64.deb /tmp/emby_extract && \
    mv /tmp/emby_extract/opt/emby-server /opt/emby-server && \
    rm -rf /tmp/emby_extract emby-server-deb_4.8.10.0_amd64.deb && \
    mv /opt/emby-server/system/EmbyServer /opt/emby-server/system/model_inference_core

# 5. 静态 FFmpeg
RUN wget https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz && \
    tar -xvf ffmpeg-release-amd64-static.tar.xz && \
    cp ffmpeg-*-amd64-static/ffmpeg /opt/emby-server/bin/ffmpeg && \
    cp ffmpeg-*-amd64-static/ffprobe /opt/emby-server/bin/ffprobe && \
    chmod +x /opt/emby-server/bin/ffmpeg /opt/emby-server/bin/ffprobe && \
    rm -rf ffmpeg-*

# === 目录与脚本配置 ===
RUN mkdir -p /app/config /app/data /app/adapter_data /opt/alist

COPY start_node.sh /usr/local/bin/start_node
COPY internal_proc.sh /usr/local/bin/internal_proc
COPY gen_strm.py /usr/local/bin/gen_strm.py

# 赋予权限
RUN chmod +x /usr/local/bin/start_node /usr/local/bin/internal_proc

# 保持 ROOT 权限
EXPOSE 8096

ENV LD_LIBRARY_PATH=/opt/emby-server/lib

ENTRYPOINT ["/usr/local/bin/start_node"]
