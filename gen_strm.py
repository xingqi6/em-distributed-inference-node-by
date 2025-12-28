#!/usr/bin/env python3
import os
import requests
import urllib.parse
import sys
import time
from xml.etree import ElementTree as ET

WEBDAV_HOST = "http://127.0.0.1:8080"
LOCAL_OUTPUT_DIR = "/app/data/ExternalData"

VIDEO_EXTENSIONS = {'.mp4', '.mkv', '.avi', '.mov', '.ts', '.iso', '.wmv', 
                    '.flv', '.m4v', '.rmvb', '.webm', '.mpg', '.mpeg', '.m2ts'}

def list_webdav_folder(path="/"):
    """使用 WebDAV PROPFIND 列出目录"""
    url = f"{WEBDAV_HOST}{path}"
    headers = {
        'Depth': '1',
        'Content-Type': 'application/xml'
    }
    
    propfind_body = '''<?xml version="1.0" encoding="utf-8"?>
    <D:propfind xmlns:D="DAV:">
        <D:prop>
            <D:resourcetype/>
            <D:getcontentlength/>
            <D:displayname/>
        </D:prop>
    </D:propfind>'''
    
    try:
        response = requests.request('PROPFIND', url, headers=headers, data=propfind_body, timeout=10)
        if response.status_code not in [200, 207]:
            print(f"[WebDAV] ❌ Failed to list {path}: HTTP {response.status_code}")
            return []
        
        # 解析 XML 响应
        namespaces = {'D': 'DAV:'}
        root = ET.fromstring(response.content)
        items = []
        
        for response_elem in root.findall('D:response', namespaces):
            href = response_elem.find('D:href', namespaces)
            if href is None:
                continue
            
            href_path = urllib.parse.unquote(href.text)
            # 跳过当前目录本身
            if href_path == path or href_path == path.rstrip('/'):
                continue
            
            propstat = response_elem.find('D:propstat', namespaces)
            if propstat is None:
                continue
            
            prop = propstat.find('D:prop', namespaces)
            resourcetype = prop.find('D:resourcetype', namespaces)
            
            # 判断是文件夹还是文件
            is_dir = resourcetype.find('D:collection', namespaces) is not None
            
            items.append({
                'path': href_path,
                'is_dir': is_dir
            })
        
        return items
    
    except Exception as e:
        print(f"[WebDAV] ❌ Error listing {path}: {e}")
        return []

def process_folder(path="/"):
    """递归处理文件夹"""
    print(f"[Scan] 📁 {path}")
    items = list_webdav_folder(path)
    
    if not items:
        print(f"[Scan] 📭 Empty or inaccessible: {path}")
        return
    
    video_count = 0
    folder_count = 0
    
    for item in items:
        if item['is_dir']:
            folder_count += 1
            process_folder(item['path'])
        else:
            ext = os.path.splitext(item['path'])[1].lower()
            if ext in VIDEO_EXTENSIONS:
                video_count += 1
                create_strm(item['path'])
    
    if video_count > 0 or folder_count > 0:
        print(f"[Scan] 📊 {path}: {video_count} videos, {folder_count} folders")

def create_strm(webdav_path):
    """创建 .strm 文件"""
    # 移除开头的斜杠
    rel_path = webdav_path.lstrip('/')
    
    local_file_path = os.path.join(LOCAL_OUTPUT_DIR, rel_path)
    local_file_path = os.path.splitext(local_file_path)[0] + ".strm"
    
    os.makedirs(os.path.dirname(local_file_path), exist_ok=True)
    
    # HF 直链
    repo_id = os.environ.get("DATASET_MUSIC_NAME")
    stream_url = f"https://huggingface.co/datasets/{repo_id}/resolve/main/{urllib.parse.quote(rel_path)}"
    
    try:
        with open(local_file_path, 'w', encoding='utf-8') as f:
            f.write(stream_url)
        print(f"[STRM] ✅ {os.path.basename(local_file_path)}")
    except Exception as e:
        print(f"[STRM] ❌ {local_file_path}: {e}")

if __name__ == "__main__":
    print("=" * 60)
    print("🎬 STRM Generator - Direct WebDAV Mode")
    print("=" * 60)
    
    # 检查环境变量
    if not os.environ.get("DATASET_MUSIC_NAME"):
        print("❌ DATASET_MUSIC_NAME not set!")
        sys.exit(1)
    
    os.makedirs(LOCAL_OUTPUT_DIR, exist_ok=True)
    
    # 等待 WebDAV 就绪
    print("\n[Wait] Checking WebDAV availability...")
    for i in range(30):
        try:
            response = requests.request('PROPFIND', f"{WEBDAV_HOST}/", timeout=2)
            if response.status_code in [200, 207]:
                print("[Wait] ✅ WebDAV is ready")
                break
        except:
            pass
        time.sleep(2)
        if i == 29:
            print("[Wait] ❌ WebDAV timeout!")
            sys.exit(1)
    
    print("\n[Gen] Starting generation...")
    time.sleep(2)
    process_folder("/")
    
    # 统计结果
    total_strm = sum(1 for root, _, files in os.walk(LOCAL_OUTPUT_DIR) for f in files if f.endswith('.strm'))
    print("\n" + "=" * 60)
    print(f"✅ Generation complete: {total_strm} .strm files created")
    print("=" * 60)
