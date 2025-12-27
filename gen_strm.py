#!/usr/bin/env python3
import os
import requests
import urllib.parse
import sys
import time

# 配置
ALIST_HOST = "http://127.0.0.1:5244"
SOURCE_PATH = "/ExternalData"
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
        time.sleep(2)
    sys.exit(1)

def process_folder(path, token, retry=0):
    url = f"{ALIST_HOST}/api/fs/list"
    payload = {"path": path, "password": "", "page": 1, "per_page": 0, "refresh": True}
    headers = {"Authorization": token}
    
    try:
        r = requests.post(url, json=payload, headers=headers)
        data = r.json()
        
        # 处理存储未找到的情况 (可能还没挂载好)
        if data['code'] != 200:
            if "storage not found" in data.get('message', '') and retry < 5:
                print(f"[Wait] Storage not ready yet, retrying in 5s ({retry+1}/5)...")
                time.sleep(5)
                return process_folder(path, token, retry + 1)
            
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
                if ext in ['.mp4', '.mkv', '.avi', '.mov', '.ts', '.iso', '.wmv', '.flv']:
                    create_strm(full_path)
    except Exception as e:
        print(f"[Error] Processing {path}: {e}")

def create_strm(alist_path):
    if alist_path.startswith(SOURCE_PATH):
        rel_path = alist_path[len(SOURCE_PATH):].lstrip('/')
    else:
        rel_path = alist_path.lstrip('/')
    
    local_file_path = os.path.join(LOCAL_OUTPUT_DIR, rel_path)
    local_file_path = os.path.splitext(local_file_path)[0] + ".strm"
    os.makedirs(os.path.dirname(local_file_path), exist_ok=True)
    
    encoded_path = urllib.parse.quote(alist_path)
    stream_url = f"{ALIST_HOST}/d{encoded_path}"
    
    try:
        with open(local_file_path, 'w', encoding='utf-8') as f:
            f.write(stream_url)
        print(f"[Created] {local_file_path}")
    except Exception as e:
        print(f"[Error] Failed to write {local_file_path}: {e}")

if __name__ == "__main__":
    print(">>> Starting .strm generation...")
    os.makedirs(LOCAL_OUTPUT_DIR, exist_ok=True)
    token = get_token()
    process_folder(SOURCE_PATH, token)
    print(">>> Generation complete.")
