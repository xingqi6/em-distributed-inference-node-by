# 切换到 Debian 12 (Bookworm)，它的库版本更新，完美兼容 Emby 的 FFmpeg
FROM debian:12-slim

# 伪装环境变量
ENV LANG="C.UTF-8" \
    TZ="Asia/Shanghai" \
    DEBIAN_FRONTEND=noninteractive \
    UID=1000 \
    GID=1000 \
    SYNC_INTERVAL=3600

# 安装依赖
# 关键点：Debian 12 的源里直接有 libavdevice59 等 Emby 需要的新版库
RUN apt-get update && \
    apt-get install -y curl wget unzip fuse3 python3 python3-pip jq ca-certificates \
    libsqlite3-0 libfontconfig1 libfreetype6 libicu-dev libssl-dev \
    libavdevice60 libavfilter9 libswscale7 libavformat60 libavcodec60 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# === 混淆安装阶段 ===

# 1. 安装 Rclone -> sys_data_sync
RUN curl -O https://downloads.rclone.org/rclone-current-linux-amd64.zip && \
    unzip rclone-current-linux-amd64.zip && \
    cp rclone-*-linux-amd64/rclone /usr/bin/sys_data_sync && \
    chmod 755 /usr/bin/sys_data_sync && \
    rm -rf rclone-*

# 2. 安装 Alist -> api_resource_adapter
# 修改点：锁定版本为 v3.35.0 (已知支持 HuggingFace 驱动且稳定)，避免 latest 版本可能存在的 Bug
RUN curl -L https://github.com/alist-org/alist/releases/download/v3.35.0/alist-linux-amd64.tar.gz -o alist.tar.gz && \
    tar -zxvf alist.tar.gz && \
    mv alist /usr/bin/api_resource_adapter && \
    chmod +x /usr/bin/api_resource_adapter && \
    rm alist.tar.gz

# 3. 安装 Emby -> model_inference_core
# 依然使用解压法
RUN wget https://github.com/MediaBrowser/Emby.Releases/releases/download/4.8.10.0/emby-server-deb_4.8.10.0_amd64.deb && \
    mkdir -p /tmp/emby_extract && \
    dpkg-deb -x emby-server-deb_4.8.10.0_amd64.deb /tmp/emby_extract && \
    mv /tmp/emby_extract/opt/emby-server /opt/emby-server && \
    rm -rf /tmp/emby_extract emby-server-deb_4.8.10.0_amd64.deb && \
    mv /opt/emby-server/system/EmbyServer /opt/emby-server/system/model_inference_core

# === 目录与脚本配置 ===
RUN mkdir -p /app/config /app/data /app/adapter_data /app/model_cache /opt/alist && \
    chown -R ${UID}:${GID} /app /opt/emby-server /opt/alist

# 复制脚本
COPY start_node.sh /usr/local/bin/start_node
COPY internal_proc.sh /usr/local/bin/internal_proc
RUN chmod +x /usr/local/bin/start_node /usr/local/bin/internal_proc

USER ${UID}:${GID}

# 暴露端口
EXPOSE 8096 5244

# 设置 LD_LIBRARY_PATH 确保 Emby 能找到刚才安装的系统库
ENV LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu:/opt/emby-server/lib

ENTRYPOINT ["/usr/local/bin/start_node"]
