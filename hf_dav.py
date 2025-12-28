#!/usr/bin/env python3
import os
import sys
import logging
from wsgidav.wsgidav_app import WsgiDAVApp
from wsgidav.dav_provider import DAVProvider, DAVCollection, DAVNonCollection
from huggingface_hub import HfApi

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
    log.error("❌ DATASET_MUSIC_NAME not set.")
    sys.exit(1)

log.info(f"🚀 Starting WebDAV Proxy for Dataset: {REPO_ID}")

class HFResource(DAVNonCollection):
    def __init__(self, path, environ, file_info):
        super().__init__(path, environ)
        self.file_info = file_info
        self.name = file_info.path.split('/')[-1]
    
    def get_content_length(self):
        return self.file_info.size if hasattr(self.file_info, 'size') else 0
    
    def get_content_type(self):
        return "application/octet-stream"
    
    def get_creation_date(self): return None 
    def get_last_modified(self): return None
    def support_ranges(self): return True  # 改为 True 支持断点续传
    def get_etag(self): return None
    def support_etag(self): return False
    
    def get_content(self):
        url = f"https://huggingface.co/datasets/{REPO_ID}/resolve/main/{self.file_info.path}"
        log.info(f"📥 Stream request: {self.path}")
        # 返回 302 重定向到 HF CDN
        from wsgidav.util import get_module_logger
        raise get_module_logger("wsgidav").exception("302 redirect")

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
        self.dummy_env = {"wsgidav.provider": self}
        
        try:
            self.refresh_tree()
        except Exception as e:
            log.error(f"⚠️ Initial fetch failed: {e}")
            log.error("请检查 DATASET_MUSIC_NAME 是否正确")
            self.tree = HFCollection("/", self.dummy_env, {})
    
    def refresh_tree(self):
        log.info(f"📡 Fetching from HF: {REPO_ID}")
        files = list(self.api.list_repo_tree(
            repo_id=REPO_ID, 
            repo_type="dataset", 
            recursive=True
        ))
        
        if not files:
            log.warning("⚠️ Dataset is empty!")
            self.tree = HFCollection("/", self.dummy_env, {})
            return
        
        log.info(f"📦 Found {len(files)} items")
        self.tree = self._build_tree(files)
        
        # 统计视频文件
        video_exts = {'.mp4', '.mkv', '.avi', '.mov', '.ts', '.iso', '.wmv', '.flv', '.m4v', '.rmvb', '.webm'}
        video_count = sum(1 for f in files if hasattr(f, 'size') and any(f.path.lower().endswith(ext) for ext in video_exts))
        log.info(f"🎬 Video files detected: {video_count}")
    
    def _build_tree(self, files):
        root_map = {}
        path_to_map = {"": root_map}
        sorted_files = sorted(files, key=lambda x: len(x.path.split('/')))
        
        for f in sorted_files:
            parts = f.path.strip('/').split('/')
            filename = parts[-1]
            parent_path = "/".join(parts[:-1])
            
            parent_map = path_to_map.get(parent_path)
            if parent_map is None: 
                continue
            
            if hasattr(f, 'size') and f.size is not None:
                parent_map[filename] = HFResource(f"/{f.path}", self.dummy_env, f)
            else:
                new_map = {}
                path_to_map[f.path] = new_map
                parent_map[filename] = HFCollection(f"/{f.path}", self.dummy_env, new_map)
        
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
    log.info(f"🟢 Listening on {config['host']}:{PORT}")
    try:
        server.start()
    except KeyboardInterrupt:
        log.info("👋 Shutting down...")
        server.stop()
