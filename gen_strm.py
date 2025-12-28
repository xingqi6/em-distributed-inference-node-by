#!/usr/bin/env python3
import os
import requests
import urllib.parse
import sys
import time

ALIST_HOST = "http://127.0.0.1:5244"
SOURCE_PATH = "/ExternalData"
LOCAL_OUTPUT_DIR = "/app/data/ExternalData"

VIDEO_EXTENSIONS = {'.mp4', '.mkv', '.avi', '.mov', '.ts', '.iso', '.wmv', 
                    '.flv', '.m4v', '.rmvb', '.webm', '.mpg', '.mpeg', '.m2ts'}

def get_token():
    url = f"{ALIST_HOST}/api/auth/login"
    payload = {"username": "admin", "password": "password"}
    for i in range(10):
        try:
            r = requests.post(url, json=payload, timeout=5)
            if r.status_code == 200:
                print("[Token] ✅ Authenticated")
                return r.json()['data']['token']
        except Exception as e:
            print(f"[Token] Retry {i+1}/10: {e}")
        time.sleep(2)
    print("[Token] ❌ Failed")
    sys.exit(1)

def test_mount(token):
    """测试挂载点是否可访问"""
    url = f"{ALIST_HOST}/api/fs/list"
    payload = {"path": SOURCE_PATH, "password": "", "page": 1, "per_page": 10, "refresh": False}
    headers = {"Authorization": token}
    
    try:
        r = requests.post(url, json=payload, headers=headers, timeout=10)
        data = r.json()
        if data['code'] == 200:
            items = data['data']['content']
            print(f"[Mount] ✅ Accessible, {len(items)} items found")
            return True
        else:
            print(f"[Mount] ❌ Error: {data.get('message')}")
            return False
    except Exception as e:
        print(f"[Mount] ❌ Exception: {e}")
        return False

def process_folder(path, token, retry=0):
    print(f"[Scan] 📁 {path}")
    url = f"{ALIST_HOST}/api/fs/list"
    payload = {"path": path, "password": "", "page": 1, "per_page": 0, "refresh": True}
    headers = {"Authorization": token}
    
    try:
        r = requests.post(url, json=payload, headers=headers, timeout=15)
        data = r.json()
        
        if data['code'] != 200:
            if "storage not found" in data.get('message', '').lower() and retry < 5:
                print(f"[Scan] ⏳ Storage not ready, retry {retry+1}/5...")
                time.sleep(5)
                return process_folder(path, token, retry + 1)
            print(f"[Scan] ❌ Error: {data.get('message')}")
            return
        
        items = data['data']['content']
        if not items:
            print(f"[Scan] 📭 Empty folder")
            return
        
        video_count = 0
        folder_count = 0
        
        for item in items:
            full_path = f"{path}/{item['name']}"
            if item['is_dir']:
                folder_count += 1
                process_folder(full_path, token)
            else:
                ext = os.path.splitext(item['name'])[1].lower()
                if ext in VIDEO_EXTENSIONS:
                    video_count += 1
                    create_strm(full_path)
        
        if video_count > 0 or folder_count > 0:
            print(f"[Scan] 📊 {path}: {video_count} videos, {folder_count} folders")
    
    except Exception as e:
        print(f"[Scan] ❌ {path}: {e}")

def create_strm(alist_path):
    rel_path = alist_path[len(SOURCE_PATH):].lstrip('/') if alist_path.startswith(SOURCE_PATH) else alist_path.lstrip('/')
    local_file_path = os.path.join(LOCAL_OUTPUT_DIR, rel_path)
    local_file_path = os.path.splitext(local_file_path)[0] + ".strm"
    
    os.makedirs(os.path.dirname(local_file_path), exist_ok=True)
    
    encoded_path = urllib.parse.quote(alist_path)
    stream_url = f"{ALIST_HOST}/d{encoded_path}"
    
    try:
        with open(local_file_path, 'w', encoding='utf-8') as f:
            f.write(stream_url)
        print(f"[STRM] ✅ {os.path.basename(local_file_path)}")
    except Exception as e:
        print(f"[STRM] ❌ {local_file_path}: {e}")

if __name__ == "__main__":
    print("=" * 60)
    print("🎬 STRM Generator - Enhanced Debug Mode")
    print("=" * 60)
    
    os.makedirs(LOCAL_OUTPUT_DIR, exist_ok=True)
    
    token = get_token()
    print("\n[Test] Testing mount accessibility...")
    time.sleep(3)
    
    if not test_mount(token):
        print("\n❌ Mount point not accessible. Check:")
        print("  1. Is DATASET_MUSIC_NAME correct?")
        print("  2. Is hf_dav.py running?")
        print("  3. Did Alist mount succeed?")
        sys.exit(1)
    
    print("\n[Gen] Starting generation...")
    process_folder(SOURCE_PATH, token)
    
    # 统计结果
    total_strm = sum(1 for root, _, files in os.walk(LOCAL_OUTPUT_DIR) for f in files if f.endswith('.strm'))
    print("\n" + "=" * 60)
    print(f"✅ Generation complete: {total_strm} .strm files created")
    print("=" * 60)
