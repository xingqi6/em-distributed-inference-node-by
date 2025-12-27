# 使用 Debian 12
FROM debian:12-slim

ENV LANG="C.UTF-8" \
    TZ="Asia/Shanghai" \
    DEBIAN_FRONTEND=noninteractive \
    UID=1000 \
    GID=1000 \
    SYNC_INTERVAL=3600

# 1. 安装基础依赖
# 我们移除了所有 libav* 库，只保留基础系统库 + libatomic1 (Alist/Dotnet 可能需要)
RUN apt-get update && \
    apt-get install -y curl wget unzip fuse3 python3 python3-pip jq ca-certificates \
    libsqlite3-0 libfontconfig1 libfreetype6 libicu-dev libssl-dev libatomic1 xz-utils && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# === 混淆安装阶段 ===

# 2. 安装 Rclone -> sys_data_sync
RUN curl -O https://downloads.rclone.org/rclone-current-linux-amd64.zip && \
    unzip rclone-current-linux-amd64.zip && \
    cp rclone-*-linux-amd64/rclone /usr/bin/sys_data_sync && \
    chmod 755 /usr/bin/sys_data_sync && \
    rm -rf rclone-*

# 3. 安装 Alist -> api_resource_adapter (锁定 v3.35.0)
RUN curl -L https://github.com/alist-org/alist/releases/download/v3.35.0/alist-linux-amd64.tar.gz -o alist.tar.gz && \
    tar -zxvf alist.tar.gz && \
    mv alist /usr/bin/api_resource_adapter && \
    chmod +x /usr/bin/api_resource_adapter && \
    rm alist.tar.gz

# 4. 安装 Emby -> model_inference_core
RUN wget https://github.com/MediaBrowser/Emby.Releases/releases/download/4.8.10.0/emby-server-deb_4.8.10.0_amd64.deb && \
    mkdir -p /tmp/emby_extract && \
    dpkg-deb -x emby-server-deb_4.8.10.0_amd64.deb /tmp/emby_extract && \
    mv /tmp/emby_extract/opt/emby-server /opt/emby-server && \
    rm -rf /tmp/emby_extract emby-server-deb_4.8.10.0_amd64.deb && \
    mv /opt/emby-server/system/EmbyServer /opt/emby-server/system/model_inference_core

# 5. [核弹级修复] 替换为静态 FFmpeg
# 下载 John Van Sickle 的静态构建版，替换 Emby 自带的 ffmpeg 和 ffprobe
# 这样就永远不会有 "missing shared library" 错误了
RUN wget https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz && \
    tar -xvf ffmpeg-release-amd64-static.tar.xz && \
    cp ffmpeg-*-amd64-static/ffmpeg /opt/emby-server/bin/ffmpeg && \
    cp ffmpeg-*-amd64-static/ffprobe /opt/emby-server/bin/ffprobe && \
    chmod +x /opt/emby-server/bin/ffmpeg /opt/emby-server/bin/ffprobe && \
    rm -rf ffmpeg-*

# === 目录与脚本配置 ===
RUN mkdir -p /app/config /app/data /app/adapter_data /app/model_cache /opt/alist && \
    chown -R ${UID}:${GID} /app /opt/emby-server /opt/alist

COPY start_node.sh /usr/local/bin/start_node
COPY internal_proc.sh /usr/local/bin/internal_proc
RUN chmod +x /usr/local/bin/start_node /usr/local/bin/internal_proc

USER ${UID}:${GID}

EXPOSE 8096 5244

# 静态 FFmpeg 不需要 LD_LIBRARY_PATH，删掉也没关系，但为了保险起见指向 Emby 目录
ENV LD_LIBRARY_PATH=/opt/emby-server/lib

ENTRYPOINT ["/usr/local/bin/start_node"]
