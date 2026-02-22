# oleVoice - macOS 本地语音输入工具

基于 MLX 的本地语音输入工具，使用 Swift 悬浮窗界面，完全离线运行。

![截图占位]

## 功能特点

- **🎤 悬浮窗界面** - 精致的小窗口显示录音状态
- **⌨️ 全局快捷键** - 右 Command 键快速开始/停止录音
- **🤖 本地模型** - 使用 MLX Audio + Qwen3-ASR，无需联网
- **⚡ 实时转录** - 说话同时显示识别结果
- **🔄 模型切换** - 支持 0.6B（快速）和 1.7B（高精度）两种模型
- **🎯 自动输入** - 识别结果自动粘贴到当前光标位置

## 系统要求

- macOS 12.0+
- Apple Silicon (M1/M2/M3/M4)
- Python 3.10+
- Xcode Command Line Tools（用于编译 Swift）

## 快速安装

### 1. 克隆仓库

```bash
git clone https://github.com/oliveagle/ole-voice.git
cd ole-voice
```

### 2. 一键安装

```bash
chmod +x install.sh
./install.sh
```

安装脚本会自动完成：
- 安装 Homebrew（如未安装）
- 安装 Python 依赖（mlx-audio, pyyaml）
- 下载语音模型
- 编译 Swift 应用

### 3. 手动安装（如一键安装失败）

```bash
# 创建虚拟环境
python3 -m venv venv
source venv/bin/activate

# 安装依赖
pip install mlx-audio pyyaml

# 编译 Swift 应用
cd VoiceOverlay
swiftc -O main.swift -o VoiceOverlay \
    -framework Cocoa -framework Carbon -framework AVFoundation

# 回到项目根目录
cd ..
```

## 使用方法

### 启动应用

```bash
./run.sh
```

或手动启动：
```bash
cd VoiceOverlay
./VoiceOverlay
```

启动后会显示启动画面，然后出现菜单栏图标 🎤。

### 录音操作

1. **按右 Command 键** - 开始录音（悬浮窗出现）
2. **说话** - 悬浮窗显示波形动画
3. **再按右 Command 键** - 停止录音
4. **自动输入** - 识别结果粘贴到当前光标位置

### 切换模型

**通过菜单栏：**
1. 点击菜单栏 🎤 图标
2. 选择 ⚙️ **模型设置**
3. 选择 0.6B 或 1.7B 模型
4. 点击 🔄 **重启 ASR 服务** 应用更改

**通过命令行：**
```bash
# 切换到小模型（快速，适合日常使用）
python switch_model.py 0.6B

# 切换到大模型（高精度，适合长文本）
python switch_model.py 1.7B

# 查看当前配置
python switch_model.py
```

### 模型对比

| 模型 | 大小 | 内存占用 | 速度 | 适用场景 |
|------|------|----------|------|----------|
| 0.6B | ~600 MB | ~1 GB | 很快 | 日常使用、快速输入 |
| 1.7B | ~1.7 GB | ~2.5 GB | 中等 | 长文本、高精度要求 |

## 配置说明

编辑 `config.yaml`：

```yaml
# 快捷键设置（目前固定为右 Command，此选项保留用于未来扩展）
hotkey: "cmd_l"

# ASR 模型配置
asr:
  model: "0.6B"  # 或 "1.7B"
  language: "zh"  # zh(中文), en(英文), auto(自动)
  models:
    0.6B: mlx-community/Qwen3-ASR-0.6B-8bit
    1.7B: mlx-community/Qwen3-ASR-1.7B-8bit

# 录音配置
recording:
  sample_rate: 16000

# 输出配置
output:
  mode: "paste"  # paste=粘贴到光标位置
```

## 权限设置

首次使用需要授权：

### 1. 辅助功能权限（必需）
用于监听右 Command 键：

**系统设置 → 隐私与安全性 → 辅助功能**
- 点击 **+** 添加终端（或你运行此应用的方式）
- 确保已勾选

### 2. 麦克风权限（必需）
用于录音：

**系统设置 → 隐私与安全性 → 麦克风**
- 勾选 **终端** 或 **VoiceOverlay**

## 项目结构

```
ole-voice/
├── VoiceOverlay/
│   ├── main.swift          # Swift 应用源码
│   ├── asr_server.py       # ASR 服务
│   └── VoiceOverlay        # 编译后的可执行文件
├── config.yaml             # 配置文件
├── switch_model.py         # 模型切换脚本
├── install.sh              # 安装脚本
├── run.sh                  # 启动脚本
└── venv/                   # Python 虚拟环境
```

## 常见问题

**Q: 启动时提示"VoiceOverlay 已在运行中"**
A: 应用已经是单实例模式，检查菜单栏是否已有 🎤 图标。

**Q: 录音后没有文字输出**
A: 检查 ASR 服务是否运行：`ps aux | grep asr_server`

**Q: 模型切换后没有生效**
A: 需要在菜单中点击 🔄 重启 ASR 服务，或完全退出后重新启动应用。

**Q: 如何完全退出应用**
A: 点击菜单栏 🎤 → **退出**，或按 `Cmd+Q`。

**Q: 支持 Intel Mac 吗**
A: 目前仅支持 Apple Silicon (M1/M2/M3/M4)，因为依赖 MLX 框架。

## 技术栈

- **前端**: Swift + AppKit (悬浮窗界面)
- **ASR**: MLX Audio + Qwen3-ASR (本地语音识别)
- **通信**: Unix Socket (Swift ↔ Python)
- **输入**: CGEvent (模拟键盘粘贴)

## 开发计划

- [ ] 支持自定义快捷键
- [ ] 添加更多模型选择（2.5B、4B 等）
- [ ] 支持英文界面
- [ ] 打包成 .app 应用

## License

MIT License
