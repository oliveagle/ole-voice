# 快速上手指南

## ✅ 环境状态

```
✓ Python 虚拟环境: 已创建
✓ 所有依赖包: 已安装
✓ 音频设备: MacBook Air麦克风 (可用)
✓ 配置文件: 正常
```

## 🚀 启动使用

```bash
# 直接运行
./run.sh
```

然后：
1. **按左 Command 键** 开始录音（屏幕右上角显示"开始录音"通知）
2. **说话**（中文/英文/日文都可以自动识别）
3. **再按左 Command 键** 停止录音
4. **文字自动输入**到当前光标位置

## ⚙️ 常用配置

编辑 `config.yaml`：

```yaml
# 更换快捷键
hotkey: "cmd_l"       # 左 Command 键
hotkey: "cmd_r"       # 右 Command 键
hotkey: "f8"          # F8 功能键
hotkey: "cmd+shift+r" # 组合键

# 换小模型（更快）
model:
  size: "tiny"  # tiny(39MB) / base(74MB) / small(244MB)

# 强制中文识别
  language: "zh"  # zh/en/ja/auto
```

## 🔒 macOS 权限（重要！）

首次使用需要在 **系统偏好设置** 中授权：

### 1. 麦克风权限
```
系统偏好设置 → 安全性与隐私 → 隐私 → 麦克风
→ 勾选"终端"（或你用的终端应用如 iTerm）
```

### 2. 辅助功能权限
```
系统偏好设置 → 安全性与隐私 → 隐私 → 辅助功能
→ 点击"+"添加终端应用 → 勾选启用
```

## 🛠 故障排除

**问题: 按 F8 没反应**
- 检查终端是否在前台（快捷键监听需要焦点）
- 尝试换快捷键：修改 config.yaml 中的 hotkey

**问题: 显示"开始录音"但没录到声音**
- 检查麦克风权限（见上文）
- 测试录音设备：
  ```bash
  source venv/bin/activate && python3 -c "
  import pyaudio
  p = pyaudio.PyAudio()
  for i in range(p.get_device_count()):
      info = p.get_device_info_by_index(i)
      if info['maxInputChannels'] > 0:
          print(f'[{i}] {info[\"name\"]}')
  p.terminate()
  "
  ```

**问题: 模型下载太慢**
- 手动下载模型放到 `~/.cache/whisper/`
- 使用镜像：`export HF_ENDPOINT=https://hf-mirror.com`

**问题: 识别结果不输入到文本框**
- 检查辅助功能权限（见上文）
- 尝试修改输出模式：
  ```yaml
  output:
    mode: "paste"  # 改为粘贴模式
  ```

## 📊 模型选择

| 模型 | 大小 | 首次加载 | 识别速度 | 适合场景 |
|------|------|----------|----------|----------|
| tiny | 39 MB | 快 | 极快 | 测试/简单使用 |
| base | 74 MB | 较快 | 很快 | 日常使用 |
| small | 244 MB | 中等 | 快 | **推荐** |
| medium | 769 MB | 慢 | 中等 | 高质量需求 |

## 💡 使用技巧

1. **后台运行**：
   ```bash
   nohup ./run.sh > /dev/null 2>&1 &
   ```

2. **开机自启**：
   ```bash
   # 创建自启动项（修改路径后执行）
   cat > ~/Library/LaunchAgents/com.voiceinput.plist << 'EOF'
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
       <key>Label</key>
       <string>com.voiceinput</string>
       <key>ProgramArguments</key>
       <array>
           <string>/Users/oliveagle/ole/repos/github.com/oliveagle/ole_asr/run.sh</string>
       </array>
       <key>RunAtLoad</key>
       <true/>
       <key>KeepAlive</key>
       <true/>
   </dict>
   </plist>
   EOF
   launchctl load ~/Library/LaunchAgents/com.voiceinput.plist
   ```

3. **查看运行状态**：
   ```bash
   ps aux | grep voice_input
   ```

4. **停止后台运行**：
   ```bash
   pkill -f voice_input
   ```

## 🎉 开始使用

现在运行 `./run.sh` 即可开始使用！
