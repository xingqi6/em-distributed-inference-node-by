#!/usr/bin/env python3
import os
import requests
import urllib.parse
import sys
import time

# 配置
ALIST_HOST = "http://127.0.0.1:5244"
# Alist 里的挂载路径
SOURCE_PATH = "/ExternalData"
# 本地 Emby 扫描路径
LOCAL_OUTPUT_DIR = "/app/data/ExternalData"

def get_token():
    url = f"{ALIST_HOST}/api/auth/login"
    payload = {"username": "admin", "password": "password"}
    for i in range(10):
        try:
            r = requests.post(url, json=payload)
            if r.status_code == 200:
                return r.json()['data']['token']
        except:
            pass
        print(f"[Script] Waiting for Alist API ({i+1}/10)...")
        time.sleep(2)
    print("[Error] Failed to get Alist token.")
    sys.exit(1)

def process_folder(path, token):
    url = f"{ALIST_HOST}/api/fs/list"
    payload = {"path": path, "password": "", "page": 1, "per_page": 0, "refresh": True}
    headers = {"Authorization": token}
    
    try:
        r = requests.post(url, json=payload, headers=headers)
        data = r.json()
        if data['code'] != 200:
            print(f"[Skip] Error listing {path}: {data.get('message')}")
            return

        items = data['data']['content']
        if not items:
            return

        for item in items:
            full_path = f"{path}/{item['name']}"
            if item['is_dir']:
                process_folder(full_path, token)
            else:
                ext = os.path.splitext(item['name'])[1].lower()
                # 在这里定义你想支持的视频格式
                if ext in ['.mp4', '.mkv', '.avi', '.mov', '.ts', '.iso', '.wmv', '.flv']:
                    create_strm(full_path)
    except Exception as e:
        print(f"[Error] Processing {path}: {e}")

def create_strm(alist_path):
    # alist_path 例如: /ExternalData/Movies/Avatar.mp4
    # 1. 去掉开头的 /ExternalData (保留相对路径)
    if alist_path.startswith(SOURCE_PATH):
        rel_path = alist_path[len(SOURCE_PATH):].lstrip('/')
    else:
        rel_path = alist_path.lstrip('/')
    
    # 2. 构建本地文件路径 /app/data/ExternalData/Movies/Avatar.strm
    local_file_path = os.path.join(LOCAL_OUTPUT_DIR, rel_path)
    local_file_path = os.path.splitext(local_file_path)[0] + ".strm"
    
    # 3. 确保目录存在
    os.makedirs(os.path.dirname(local_file_path), exist_ok=True)
    
    # 4. 生成播放链接
    # 链接格式: http://127.0.0.1:5244/d/ExternalData/...
    encoded_path = urllib.parse.quote(alist_path)
    stream_url = f"{ALIST_HOST}/d{encoded_path}"
    
    # 5. 写入
    try:
        with open(local_file_path, 'w', encoding='utf-8') as f:
            f.write(stream_url)
        print(f"[Created] {local_file_path}")
    except Exception as e:
        print(f"[Error] Failed to write {local_file_path}: {e}")

if __name__ == "__main__":
    print(">>> Starting .strm generation...")
    # 确保本地输出目录存在
    os.makedirs(LOCAL_OUTPUT_DIR, exist_ok=True)
    
    token = get_token()
    # 稍微等一下挂载生效
    time.sleep(2)
    process_folder(SOURCE_PATH, token)
    print(">>> Generation complete.")
