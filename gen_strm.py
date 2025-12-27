import os
import requests
import urllib.parse
import sys

# 配置
ALIST_HOST = "http://127.0.0.1:5244"
# Alist 里的挂载路径
SOURCE_PATH = "/ExternalData"
# 本地 Emby 扫描路径
LOCAL_OUTPUT_DIR = "/app/data/ExternalData"
AUTH_TOKEN = ""

def get_token():
    url = f"{ALIST_HOST}/api/auth/login"
    payload = {"username": "admin", "password": "password"}
    try:
        r = requests.post(url, json=payload)
        return r.json()['data']['token']
    except Exception as e:
        print(f"[Error] Failed to get Alist token: {e}")
        sys.exit(1)

def process_folder(path, token):
    url = f"{ALIST_HOST}/api/fs/list"
    payload = {"path": path, "password": "", "page": 1, "per_page": 0, "refresh": True}
    headers = {"Authorization": token}
    
    try:
        r = requests.post(url, json=payload, headers=headers)
        data = r.json()
        if data['code'] != 200:
            print(f"Error listing {path}: {data['message']}")
            return

        items = data['data']['content']
        if not items:
            return

        for item in items:
            full_path = f"{path}/{item['name']}"
            if item['is_dir']:
                # 递归处理文件夹
                process_folder(full_path, token)
            else:
                # 只处理视频文件
                ext = os.path.splitext(item['name'])[1].lower()
                if ext in ['.mp4', '.mkv', '.avi', '.mov', '.ts', '.iso', '.wmv']:
                    create_strm(full_path)
    except Exception as e:
        print(f"Error processing {path}: {e}")

def create_strm(alist_path):
    # 将 /ExternalData/movie.mp4 映射为本地 /app/data/ExternalData/movie.strm
    # 1. 移除源路径的起始部分
    rel_path = alist_path.lstrip('/')
    
    # 2. 构建本地文件路径
    local_file_path = os.path.join("/app/data", rel_path)
    # 替换后缀为 .strm
    local_file_path = os.path.splitext(local_file_path)[0] + ".strm"
    
    # 3. 确保目录存在
    os.makedirs(os.path.dirname(local_file_path), exist_ok=True)
    
    # 4. 生成播放链接 (URL编码)
    # 链接格式: http://127.0.0.1:5244/d/ExternalData/path/to/movie.mp4
    encoded_path = urllib.parse.quote(alist_path)
    # Alist 的直链地址通常是 /d/路径
    # 注意：Alist V3 的 /d/ 接口会自动重定向到真实直链
    stream_url = f"{ALIST_HOST}/d{encoded_path}"
    
    # 5. 写入文件
    try:
        with open(local_file_path, 'w', encoding='utf-8') as f:
            f.write(stream_url)
        print(f"[Generated] {local_file_path}")
    except Exception as e:
        print(f"[Error] Write file failed: {e}")

if __name__ == "__main__":
    print(">>> Starting .strm generation...")
    token = get_token()
    process_folder(SOURCE_PATH, token)
    print(">>> Generation complete.")
