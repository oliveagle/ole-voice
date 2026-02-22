#!/usr/bin/env python3
"""
MLX ASR 服务端 - 为 Swift VoiceOverlay 提供转录服务
通过 Unix Socket 通信
支持多模型切换: 0.6B (快速) 和 1.7B (高质量)
"""

import os
import sys
import socket
import json
import tempfile
import wave
import struct
from pathlib import Path

# 默认配置
CONFIG = {
    "model": "0.6B",  # 默认使用小模型
    "language": "zh",
    "socket_path": "/tmp/voice_asr_socket",
    "models": {
        "0.6B": "mlx-community/Qwen3-ASR-0.6B-8bit",
        "1.7B": "mlx-community/Qwen3-ASR-1.7B-8bit"
    }
}

# 当前加载的模型缓存
_current_model = None
_current_model_key = None

# 热词缓存
_hotwords = None
_hotwords_mtime = 0

def load_hotwords():
    """加载热词词库，支持热更新"""
    global _hotwords, _hotwords_mtime

    # 支持多个热词文件位置
    hotwords_paths = [
        Path(__file__).parent.parent / "hotwords.txt",  # 项目根目录
        Path(__file__).parent / "hotwords.txt",         # VoiceOverlay 目录
        Path.home() / ".config/ole_voice/hotwords.txt", # 用户配置目录
    ]

    hotwords_file = None
    for path in hotwords_paths:
        if path.exists():
            hotwords_file = path
            break

    if hotwords_file is None:
        return None

    # 检查文件修改时间，避免重复加载
    try:
        mtime = hotwords_file.stat().st_mtime
        if mtime == _hotwords_mtime and _hotwords is not None:
            return _hotwords

        with open(hotwords_file, 'r', encoding='utf-8') as f:
            lines = [line.strip() for line in f if line.strip() and not line.startswith('#')]

        _hotwords = lines
        _hotwords_mtime = mtime

        if lines:
            print(f"[Hotwords] 加载 {len(lines)} 个热词 from {hotwords_file}")

        return _hotwords
    except Exception as e:
        print(f"[Hotwords] 加载失败: {e}")
        return None

def load_config():
    """加载用户配置"""
    global CONFIG
    try:
        config_path = Path(__file__).parent.parent / "config.yaml"
        import yaml
        with open(config_path, 'r', encoding='utf-8') as f:
            user_config = yaml.safe_load(f)
            if user_config:
                # 读取新的 asr 配置
                if 'asr' in user_config:
                    asr_config = user_config['asr']
                    CONFIG['model'] = asr_config.get('model', '0.6B')
                    CONFIG['language'] = asr_config.get('language', 'zh')
                    if 'models' in asr_config:
                        CONFIG['models'].update(asr_config['models'])
                # 兼容旧配置
                elif 'model' in user_config:
                    CONFIG['language'] = user_config['model'].get('language', 'zh')
    except Exception as e:
        print(f"[Config] 加载配置失败，使用默认配置: {e}")

def get_model_path(model_key: str) -> str:
    """获取模型路径，优先使用本地缓存"""
    model_name = CONFIG['models'].get(model_key, CONFIG['models']['0.6B'])

    # 检查本地缓存
    cache_dirs = [
        Path.home() / f".cache/modelscope/hub/models/{model_name}",
        Path.home() / f".cache/modelscope/hub/models/{model_name.replace('.', '___')}"
    ]

    for cache_dir in cache_dirs:
        if cache_dir.exists():
            print(f"[ASR] 使用本地模型: {cache_dir}")
            return str(cache_dir)

    print(f"[ASR] 使用远程模型: {model_name}")
    return model_name

def load_model(model_key: str):
    """加载指定模型（带缓存）"""
    global _current_model, _current_model_key

    # 如果模型已经加载，直接返回
    if _current_model is not None and _current_model_key == model_key:
        return _current_model

    from mlx_audio.stt.utils import load_model as mlx_load_model

    model_path = get_model_path(model_key)
    print(f"[ASR] 加载模型 [{model_key}]...")
    _current_model = mlx_load_model(model_path)
    _current_model_key = model_key
    print(f"[ASR] 模型 [{model_key}] 加载完成")

    return _current_model

# 音近词纠正映射表
PHONETIC_CORRECTIONS = {
    # AI/编程术语音近纠正
    "托肯": "token",
    "透肯": "token",
    "托卡": "token",
    "图肯": "token",
    "透卡": "token",
    "托克": "token",

    # 其他常见术语
    "恩 beds": "embeddings",
    "恩 bedding": "embeddings",
    "艾 beds": "embeddings",
    "啦 bed": "LoRA",
    "罗拉": "LoRA",
    "劳拉": "LoRA",
    "罗娜": "LoRA",

    # 编程术语
    "派森": "Python",
    "拍森": "Python",
    "拍森": "Python",
    "趴森": "Python",
    "泰普 script": "TypeScript",
    "泰普斯克瑞普特": "TypeScript",
    "凯特": "Kotlin",
    "考特林": "Kotlin",

    # 框架/工具
    "瑞艾科特": "React",
    "瑞艾克": "React",
    "维艾尤": "Vue",
    "维尤": "Vue",
    "维尤": "Vue",
    "安古勒": "Angular",
    "安哥拉": "Angular",
    "节普斯": "GitHub",
    "吉哈布": "GitHub",
    "吉哈伯": "GitHub",
    "吉特": "Git",
    "给特": "Git",

    # 数据库
    "麦斯库尔": "MySQL",
    "麦塞库尔": "MySQL",
    "迈斯库尔": "MySQL",
    "普斯特": "Postgres",
    "普斯格瑞": "PostgreSQL",
    "波斯格瑞": "PostgreSQL",
    "蒙勾DB": "MongoDB",
    "蒙勾": "MongoDB",
    "瑞迪斯": "Redis",
    "瑞地斯": "Redis",

    # 云计算/容器
    "达克": "Docker",
    "多克": "Docker",
    "道克": "Docker",
    "库伯奈特斯": "Kubernetes",
    "库伯奈提斯": "Kubernetes",
    "K八s": "K8s",
    "K八斯": "K8s",
    "奈克斯": "Nginx",
    "恩静克斯": "Nginx",

    # AI术语
    " attentions": "attention",
    "爱腾神": "attention",
    "爱腾审": "attention",
    "拔特": "BERT",
    "博特": "BERT",
    "伯特": "BERT",
    "吉皮梯": "GPT",
    "吉皮提": "GPT",
    "吉皮踢": "GPT",
    "爱奥艾姆": "LLM",
    "艾奥艾姆": "LLM",

    # 通用英文
    "API": "API",
    "埃批艾": "API",
    "阿批艾": "API",
    "埃普艾": "API",
    "尤艾": "UI",
    "尤克斯": "UX",
    "西艾": "CI",
    "西迪": "CD",
    "西艾西迪": "CI/CD",
}

def apply_phonetic_corrections(text: str) -> str:
    """应用音近词纠正"""
    if not text:
        return text

    corrected = text
    for wrong, correct in PHONETIC_CORRECTIONS.items():
        # 使用词边界匹配，避免误替换
        import re
        # 构建正则：匹配整个词，支持中文词边界
        pattern = re.escape(wrong)
        corrected = re.sub(pattern, correct, corrected)

    # 如果发生了纠正，记录日志
    if corrected != text:
        print(f"[Phonetic] '{text}' -> '{corrected}'")

    return corrected

def transcribe_audio(audio_path: str) -> dict:
    """使用 MLX Audio 转录音频"""
    try:
        from mlx_audio.stt.generate import generate_transcription

        # 获取当前配置的模型
        model_key = CONFIG['model']
        model = load_model(model_key)

        lang_map = {'zh': 'Chinese', 'en': 'English', 'auto': 'Chinese'}
        mlx_lang = lang_map.get(CONFIG['language'], 'Chinese')

        # 加载热词
        hotwords = load_hotwords()
        context = None
        if hotwords:
            # 将热词格式化为上下文提示
            context = "重要术语: " + ", ".join(hotwords[:20])  # 限制热词数量避免过长
            print(f"[ASR] 使用热词: {len(hotwords)} 个")

        print(f"[ASR] 开始转录 (模型: {model_key}, 语言: {mlx_lang})...")

        # 创建临时输出文件路径
        output_path = tempfile.NamedTemporaryFile(suffix='.txt', delete=False).name

        # 构建转录参数
        transcription_kwargs = {
            "model": model,
            "audio": audio_path,
            "output_path": output_path,
            "language": mlx_lang,
            "verbose": False
        }

        # 如果有热词，添加到 context 参数
        if context:
            transcription_kwargs["context"] = context

        result = generate_transcription(**transcription_kwargs)

        # 清理临时输出文件
        try:
            os.unlink(output_path)
        except:
            pass

        text = result.text.strip() if hasattr(result, 'text') else str(result).strip()

        # 音近词纠正（处理常见误识别）
        text = apply_phonetic_corrections(text)

        return {"success": True, "text": text}

    except Exception as e:
        print(f"[ASR] 错误: {e}")
        import traceback
        traceback.print_exc()
        return {"success": False, "error": str(e)}

def handle_client(conn: socket.socket):
    """处理客户端请求"""
    try:
        # 接收数据长度 (4字节)
        length_bytes = conn.recv(4)
        if not length_bytes:
            return

        data_length = struct.unpack('!I', length_bytes)[0]

        # 接收音频数据
        audio_data = b''
        while len(audio_data) < data_length:
            chunk = conn.recv(min(4096, data_length - len(audio_data)))
            if not chunk:
                break
            audio_data += chunk

        # 保存为临时 WAV 文件
        with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as f:
            temp_path = f.name

        # 写入 WAV 格式
        with wave.open(temp_path, 'wb') as wf:
            wf.setnchannels(1)
            wf.setsampwidth(2)
            wf.setframerate(16000)
            wf.writeframes(audio_data)

        # 转录
        result = transcribe_audio(temp_path)

        # 清理
        try:
            os.unlink(temp_path)
        except:
            pass

        # 发送结果
        response = json.dumps(result).encode('utf-8')
        conn.send(struct.pack('!I', len(response)))
        conn.send(response)

    except Exception as e:
        print(f"[Server] 处理错误: {e}")
        error_response = json.dumps({"success": False, "error": str(e)}).encode('utf-8')
        try:
            conn.send(struct.pack('!I', len(error_response)))
            conn.send(error_response)
        except:
            pass
    finally:
        conn.close()

def start_server():
    """启动 Unix Socket 服务端"""
    socket_path = CONFIG["socket_path"]

    # 清理旧 socket
    if os.path.exists(socket_path):
        os.unlink(socket_path)

    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(socket_path)
    server.listen(5)

    print(f"[ASR Server] 已启动，监听 {socket_path}")
    print(f"[ASR Server] 当前模型: {CONFIG['model']} ({CONFIG['models'][CONFIG['model']]})")
    print(f"[ASR Server] 语言: {CONFIG['language']}")
    print(f"[ASR Server] 可用模型: {', '.join(CONFIG['models'].keys())}")

    try:
        while True:
            conn, addr = server.accept()
            handle_client(conn)
    except KeyboardInterrupt:
        print("\n[ASR Server] 关闭中...")
    finally:
        server.close()
        if os.path.exists(socket_path):
            os.unlink(socket_path)

if __name__ == '__main__':
    load_config()
    start_server()
