#!/usr/bin/env python3
import os
import sys
from wsgidav.wsgidav_app import WsgiDAVApp
from wsgidav.dav_provider import DAVProvider, DAVCollection, DAVNonCollection
from wsgidav.server.server_cli import ServerOptions
from huggingface_hub import HfApi
import logging

# 配置日志
logging.basicConfig(level=logging.INFO)
log = logging.getLogger("hf_dav")

# 环境变量
REPO_ID = os.environ.get("DATASET_MUSIC_NAME")
TOKEN = os.environ.get("MUSIC_TOKEN")
PORT = 8080

if not REPO_ID:
    log.error("DATASET_MUSIC_NAME not set")
    sys.exit(1)

# === 自定义 WebDAV 提供者 ===
class HFResource(DAVNonCollection):
    def __init__(self, path, environ, file_info):
        super().__init__(path, environ)
        self.file_info = file_info
        self.name = file_info.path.split('/')[-1]

    def get_content_length(self):
        return self.file_info.size

    def get_content_type(self):
        return "application/octet-stream"

    def get_creation_date(self):
        return None 

    def get_last_modified(self):
        return None

    def support_ranges(self):
        return False

    def get_content(self):
        # 核心逻辑：直接重定向到 HF 的下载链接
        # 链接格式: https://huggingface.co/datasets/{repo}/resolve/main/{path}
        url = f"https://huggingface.co/datasets/{REPO_ID}/resolve/main/{self.file_info.path}"
        if TOKEN:
            # 私有仓库可能需要带 Token，但 WebDAV 重定向通常不支持带 Header
            # 如果是公开数据集，这个 URL 是可以直接访问的
            pass
        
        # 返回重定向，让客户端(Alist)自己去下载
        log.info(f"Redirecting {self.path} -> {url}")
        # WsgiDAV 特性: 抛出 302 响应
        raise 302 
        return url # Fallback

class HFCollection(DAVCollection):
    def __init__(self, path, environ, children_map):
        super().__init__(path, environ)
        self.children_map = children_map # {filename: node}

    def get_member_list(self):
        return [self.children_map[name] for name in self.children_map]

    def get_member(self, name):
        return self.children_map.get(name)

class HFProvider(DAVProvider):
    def __init__(self):
        super().__init__()
        self.api = HfApi(token=TOKEN)
        self.tree = None
        self.refresh_tree()

    def refresh_tree(self):
        log.info(f"Fetching file list from HF: {REPO_ID}...")
        try:
            # 获取所有文件信息
            files = self.api.list_repo_tree(repo_id=REPO_ID, repo_type="dataset", recursive=True)
            self.tree = self._build_tree(files)
            log.info("Tree built successfully.")
        except Exception as e:
            log.error(f"Failed to fetch HF tree: {e}")
            self.tree = {}

    def _build_tree(self, files):
        # 构建目录树结构
        root_map = {} # {filename: node}
        
        # 辅助字典，存储路径到 map 的映射
        path_to_map = {"": root_map} # "" 代表根目录的 children_map

        # 先按路径长度排序，确保父目录先创建
        sorted_files = sorted(files, key=lambda x: len(x.path.split('/')))

        for f in sorted_files:
            parts = f.path.strip('/').split('/')
            filename = parts[-1]
            parent_path = "/".join(parts[:-1])
            
            # 找到父容器
            parent_map = path_to_map.get(parent_path)
            if parent_map is None:
                continue # 理论上不会发生

            if isinstance(f,  type(None)): continue # Skip unknown

            # 判断是文件还是文件夹 (huggingface_hub > 0.14 返回的是 RepoFolder/RepoFile)
            # 简单的判断方式：看有没有 size 属性
            if hasattr(f, 'size') and f.size is not None:
                # 是文件
                node = HFResource(f"/{f.path}", None, f)
                parent_map[filename] = node
            else:
                # 是文件夹
                new_map = {}
                path_to_map[f.path] = new_map
                node = HFCollection(f"/{f.path}", None, new_map)
                parent_map[filename] = node

        # 根节点
        return HFCollection("/", None, root_map)

    def get_resource_inst(self, path, environ):
        # 每次请求都会遍历树
        if self.tree is None: return None
        
        path = path.strip('/')
        if path == "":
            return self.tree

        parts = path.split('/')
        current = self.tree
        
        for part in parts:
            if isinstance(current, HFCollection):
                current = current.get_member(part)
                if current is None: return None
            else:
                return None
        
        return current

# === 启动服务器 ===
config = {
    "provider_mapping": {"/": HFProvider()},
    "port": PORT,
    "host": "0.0.0.0",
    "simple_dc": {"user_mapping": {"*": True}}, # 允许匿名访问
    "logging": {"enable": True},
}

if __name__ == "__main__":
    app = WsgiDAVApp(config)
    
    from cheroot import wsgi
    server = wsgi.Server(
        bind_addr=(config["host"], config["port"]),
        wsgi_app=app,
        numthreads=10,
    )
    log.info(f"Serving HF WebDAV on port {PORT}...")
    try:
        server.start()
    except KeyboardInterrupt:
        server.stop()
