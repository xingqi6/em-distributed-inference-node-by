#!/usr/bin/env python3
import os
import sys
import logging
from wsgidav.wsgidav_app import WsgiDAVApp
from wsgidav.dav_provider import DAVProvider, DAVCollection, DAVNonCollection
from huggingface_hub import HfApi

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='[%(levelname)s] %(name)s: %(message)s',
    stream=sys.stdout
)
log = logging.getLogger("hf_dav")
logging.getLogger("httpx").setLevel(logging.WARNING)

REPO_ID = os.environ.get("DATASET_MUSIC_NAME")
TOKEN = os.environ.get("MUSIC_TOKEN")
if TOKEN == "": TOKEN = None
PORT = 8080

if not REPO_ID:
    log.error("❌ DATASET_MUSIC_NAME not set. Exiting.")
    sys.exit(1)

log.info(f"🚀 Starting WebDAV Proxy for Dataset: {REPO_ID}")

class HFResource(DAVNonCollection):
    def __init__(self, path, environ, file_info):
        super().__init__(path, environ)
        self.file_info = file_info
        self.name = file_info.path.split('/')[-1]

    def get_content_length(self):
        return self.file_info.size

    def get_content_type(self):
        return "application/octet-stream"

    def get_creation_date(self): return None 
    def get_last_modified(self): return None
    def support_ranges(self): return False

    # === 修复点：添加 ETag 支持 ===
    def get_etag(self):
        return None
    def support_etag(self):
        return False

    def get_content(self):
        url = f"https://huggingface.co/datasets/{REPO_ID}/resolve/main/{self.file_info.path}"
        log.info(f"Redirecting: {self.path} -> {url}")
        raise 302 
        return url

class HFCollection(DAVCollection):
    def __init__(self, path, environ, children_map):
        super().__init__(path, environ)
        self.children_map = children_map

    def get_member_names(self):
        return list(self.children_map.keys())

    def get_member(self, name):
        return self.children_map.get(name)

class HFProvider(DAVProvider):
    def __init__(self):
        super().__init__()
        self.api = HfApi(token=TOKEN)
        self.tree = None
        # 构造 dummy_env
        self.dummy_env = {"wsgidav.provider": self}

        try:
            self.refresh_tree()
        except Exception as e:
            log.error(f"⚠️ Initial tree fetch failed: {e}")
            self.tree = HFCollection("/", self.dummy_env, {})

    def refresh_tree(self):
        log.info(f"📡 Fetching file list from Hugging Face...")
        files = self.api.list_repo_tree(repo_id=REPO_ID, repo_type="dataset", recursive=True)
        self.tree = self._build_tree(files)
        log.info(f"✅ Tree built successfully.")

    def _build_tree(self, files):
        root_map = {}
        path_to_map = {"": root_map}
        sorted_files = sorted(files, key=lambda x: len(x.path.split('/')))

        for f in sorted_files:
            parts = f.path.strip('/').split('/')
            filename = parts[-1]
            parent_path = "/".join(parts[:-1])
            
            parent_map = path_to_map.get(parent_path)
            if parent_map is None: continue 

            if hasattr(f, 'size') and f.size is not None:
                node = HFResource(f"/{f.path}", self.dummy_env, f)
                parent_map[filename] = node
            else:
                new_map = {}
                path_to_map[f.path] = new_map
                node = HFCollection(f"/{f.path}", self.dummy_env, new_map)
                parent_map[filename] = node

        return HFCollection("/", self.dummy_env, root_map)

    def get_resource_inst(self, path, environ):
        if self.tree is None: return None
        path = path.strip('/')
        if path == "": return self.tree
        
        parts = path.split('/')
        current = self.tree
        for part in parts:
            if isinstance(current, HFCollection):
                current = current.get_member(part)
                if current is None: return None
            else:
                return None
        return current

config = {
    "provider_mapping": {"/": HFProvider()},
    "port": PORT,
    "host": "0.0.0.0",
    "simple_dc": {"user_mapping": {"*": True}},
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
    log.info(f"🟢 Server listening on port {PORT}...")
    try:
        server.start()
    except KeyboardInterrupt:
        server.stop()
