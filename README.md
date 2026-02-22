# 本地语音输入工具 (macOS)

按快捷键录音，再按停止，自动将语音转换为文字输入。

## 功能

- **快捷键触发**: 默认 F8 键开始/停止录音
- **本地模型**: 使用 Whisper 模型，无需联网
- **自动输入**: 识别结果自动输入到当前文本框
- **模型可换**: 支持 tiny/base/small/medium/large 多种模型
- **后台运行**: 无 GUI，命令行运行，占用资源少
- **静音检测**: 可配置自动停止（设置 silence_timeout）

## 安装

```bash
# 一键安装
./install.sh

# 或者手动安装
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

## 使用

```bash
# 启动服务
./run.sh

# 或使用 Python 直接运行
python3 voice_input.py
```

启动后:
1. 按 **F8** 开始录音 (屏幕右上角显示通知)
2. 说话
3. 再按 **F8** 停止录音
4. 文字自动输入到当前光标位置

## 配置

编辑 `config.yaml`:

```yaml
# 修改快捷键 (示例: cmd+shift+r, ctrl+space, f9)
hotkey: "f8"

# 更换模型 (tiny/base/small/medium/large-v3)
model:
  size: "small"  # small 是速度与准确度的平衡
  device: "auto"  # auto/cpu/cuda
  compute_type: "int8"  # int8/float16/float32
  language: "auto"  # auto/zh/en/ja 等

# 输出模式 (type/paste/clipboard)
output:
  mode: "type"  # type=直接输入, paste=粘贴, clipboard=仅复制

# 高级选项
advanced:
  silence_timeout: 0  # 静音自动停止(秒)，0=禁用
  max_duration: 60    # 最大录音时长(秒)
```

## 模型说明

| 模型 | 大小 | 内存占用 | 速度 | 准确度 | 适用场景 |
|------|------|----------|------|--------|----------|
| tiny | 39 MB | ~100 MB | 最快 | 一般 | 快速测试 |
| base | 74 MB | ~200 MB | 很快 | 较好 | 日常简单使用 |
| small | 244 MB | ~600 MB | 快 | 好 | **推荐** |
| medium | 769 MB | ~1.5 GB | 中等 | 很好 | 高质量要求 |
| large | 1550 MB | ~3 GB | 慢 | 最好 | 专业用途 |

第一次使用会自动下载模型到 `~/.cache/whisper/`。

## 快捷键格式

```yaml
# 单独功能键
hotkey: "f8"
hotkey: "f9"

# 组合键
hotkey: "cmd+shift+r"
hotkey: "ctrl+space"
hotkey: "alt+f9"
hotkey: "cmd+shift+space"

# 其他按键
hotkey: "esc"
hotkey: "tab"
```

## macOS 权限设置

### 1. 麦克风权限

首次运行需要授权终端访问麦克风：

**系统偏好设置 → 安全性与隐私 → 隐私 → 麦克风**
- 勾选 **终端** 或你运行此工具的终端应用

### 2. 辅助功能权限

此工具需要控制键盘输入文字：

**系统偏好设置 → 安全性与隐私 → 隐私 → 辅助功能**
- 点击 **+** 添加终端应用
- 确保已勾选

### 3. 自动化权限

如果看到提示"是否允许控制此电脑"，请点击**允许**。

## 常见问题

**Q: 无法录音 / 没有声音**
A: 检查麦克风权限（见上文）

**Q: 模型下载慢**
A: 手动下载模型放到 `~/.cache/whisper/`
- 模型下载地址: https://huggingface.co/Systran
- 或使用镜像: https://hf-mirror.com/Systran

**Q: 快捷键冲突**
A: 在 config.yaml 中更换快捷键，避免与系统或其他应用冲突

**Q: 识别中文效果不好**
A: 在 config.yaml 中设置 `language: "zh"` 强制使用中文

**Q: 如何后台运行**
A: 使用 `nohup` 或 `screen`:
```bash
nohup ./run.sh > /dev/null 2>&1 &
```

**Q: 开机自启动**
A: 创建 LaunchAgent:
```bash
# 创建启动项
cat > ~/Library/LaunchAgents/com.voiceinput.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.voiceinput</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>/path/to/ole_asr/run.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
EOF

# 加载启动项
launchctl load ~/Library/LaunchAgents/com.voiceinput.plist
```

## 技术说明

- **录音**: pyaudio (16kHz 单声道)
- **识别**: faster-whisper (OpenAI Whisper CTranslate2 加速版)
- **快捷键**: pynput (全局热键监听)
- **输入**: pynput + AppleScript (模拟键盘输入)

## 退出程序

运行中按 **Ctrl+C** 即可退出。

## License

MIT
