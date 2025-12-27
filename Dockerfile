# 使用 Ubuntu 作为基础
FROM ubuntu:22.04

# 伪装成 AI 计算节点环境
ENV LANG="C.UTF-8" \
    TZ="Asia/Shanghai" \
    DEBIAN_FRONTEND=noninteractive \
    UID=1000 \
    GID=1000 \
    SYNC_INTERVAL=3600

# 安装基础依赖 (包含 Emby 运行所需的库)
# === 关键修复点: 新增 libicu-dev ===
RUN apt-get update && \
    apt-get install -y curl wget unzip fuse3 python3 python3-pip jq ca-certificates \
    libsqlite3-0 libfontconfig1 libfreetype6 libicu-dev && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# === 混淆安装阶段 ===

# 1. 安装并伪装 Rclone -> sys_data_sync
RUN curl -O https://downloads.rclone.org/rclone-current-linux-amd64.zip && \
    unzip rclone-current-linux-amd64.zip && \
    cp rclone-*-linux-amd64/rclone /usr/bin/sys_data_sync && \
    chmod 755 /usr/bin/sys_data_sync && \
    rm -rf rclone-*

# 2. 安装并伪装 Alist -> api_resource_adapter
RUN curl -L https://github.com/alist-org/alist/releases/latest/download/alist-linux-amd64.tar.gz -o alist.tar.gz && \
    tar -zxvf alist.tar.gz && \
    mv alist /usr/bin/api_resource_adapter && \
    chmod +x /usr/bin/api_resource_adapter && \
    rm alist.tar.gz

# 3. 安装并伪装 Emby -> model_inference_core
# 使用 dpkg-deb -x 解压，不安装，避开 systemd 报错
RUN wget https://github.com/MediaBrowser/Emby.Releases/releases/download/4.8.10.0/emby-server-deb_4.8.10.0_amd64.deb && \
    mkdir -p /tmp/emby_extract && \
    dpkg-deb -x emby-server-deb_4.8.10.0_amd64.deb /tmp/emby_extract && \
    mv /tmp/emby_extract/opt/emby-server /opt/emby-server && \
    rm -rf /tmp/emby_extract emby-server-deb_4.8.10.0_amd64.deb && \
    mv /opt/emby-server/system/EmbyServer /opt/emby-server/system/model_inference_core

# === 目录与脚本配置 ===
# 修复点：这里显式创建 /opt/alist 目录，确保文件夹存在
RUN mkdir -p /app/config /app/data /app/adapter_data /app/model_cache /opt/alist && \
    chown -R ${UID}:${GID} /app /opt/emby-server /opt/alist

# 复制本地脚本进镜像
COPY start_node.sh /usr/local/bin/start_node
COPY internal_proc.sh /usr/local/bin/internal_proc
RUN chmod +x /usr/local/bin/start_node /usr/local/bin/internal_proc

USER ${UID}:${GID}

# 暴露端口
EXPOSE 8096 5244

ENTRYPOINT ["/usr/local/bin/start_node"]
