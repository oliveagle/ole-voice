#!/bin/bash
# VoiceOverlay 安装脚本
# 用于在新 Mac 上快速安装和配置

set -e

echo "🎤 VoiceOverlay 安装器"
echo "========================"

# 检查 macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "❌ 此应用仅支持 macOS"
    exit 1
fi

# 获取项目路径
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_DIR"

echo ""
echo "📁 项目路径: $PROJECT_DIR"

# 检查 Homebrew
if ! command -v brew &> /dev/null; then
    echo ""
    echo "🍺 安装 Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# 检查 Python
if ! command -v python3 &> /dev/null; then
    echo ""
    echo "🐍 安装 Python..."
    brew install python
fi

echo ""
echo "🐍 Python 版本: $(python3 --version)"

# 创建虚拟环境
echo ""
echo "📦 创建虚拟环境..."
if [ ! -d "venv" ]; then
    python3 -m venv venv
fi

source venv/bin/activate

# 安装 Python 依赖
echo ""
echo "📦 安装依赖..."
pip install -q --upgrade pip
pip install -q mlx-audio pyyaml

echo "✅ 依赖安装完成"

# 检查模型
echo ""
echo "🤖 检查模型..."

MODEL_0_6B="$HOME/.cache/modelscope/hub/models/mlx-community/Qwen3-ASR-0.6B-8bit"
MODEL_1_7B="$HOME/.cache/modelscope/hub/models/mlx-community/Qwen3-ASR-1.7B-8bit"

if [ -d "$MODEL_0_6B" ]; then
    echo "  ✅ 0.6B 模型已存在"
else
    echo "  📥 下载 0.6B 模型（首次使用会自动下载）..."
    python3 -c "from mlx_audio.stt.utils import load_model; load_model('mlx-community/Qwen3-ASR-0.6B-8bit')" 2>/dev/null || true
fi

if [ -d "$MODEL_1_7B" ]; then
    echo "  ✅ 1.7B 模型已存在"
else
    echo "  📥 1.7B 模型将在首次使用时自动下载"
fi

# 编译 Swift 应用
echo ""
echo "🔨 编译 VoiceOverlay..."
cd VoiceOverlay
swiftc -O main.swift -o VoiceOverlay \
    -framework Cocoa \
    -framework Carbon \
    -framework AVFoundation \
    -framework CoreVideo 2>&1

if [ $? -eq 0 ]; then
    echo "✅ 编译完成"
else
    echo "❌ 编译失败"
    exit 1
fi

# 也编译到 oleVoice.app 内
if [ -d "oleVoice.app/Contents/MacOS" ]; then
    echo ""
    echo "📦 更新 oleVoice.app..."
    cp VoiceOverlay oleVoice.app/Contents/MacOS/VoiceInputSwift
    echo "✅ 应用包已更新"
fi

# 设置权限
echo ""
echo "🔐 设置权限..."
chmod +x VoiceOverlay
chmod +x ../switch_model.py

# 创建启动脚本
cd ..
cat > run.sh << 'EOF'
#!/bin/bash
# VoiceOverlay 启动脚本

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/VoiceOverlay"

# 检查是否已在运行
if pgrep -x "VoiceOverlay" > /dev/null; then
    echo "VoiceOverlay 已在运行"
    exit 0
fi

# 清理可能残留的锁文件
rm -f /tmp/voiceoverlay.lock

# 启动应用
./VoiceOverlay &
echo "VoiceOverlay 已启动"
echo "按右 Command 键开始录音"
EOF

chmod +x run.sh

echo ""
echo "========================"
echo "✅ 安装完成！"
echo ""
echo "🚀 启动方法:"
echo "   ./run.sh"
echo ""
echo "⚙️  切换模型:"
echo "   python switch_model.py 0.6B  # 小模型（快速）"
echo "   python switch_model.py 1.7B  # 大模型（高精度）"
echo ""
echo "🔐 首次使用需要授权:"
echo "   1. 系统设置 -> 隐私与安全性 -> 辅助功能"
echo "   2. 添加 Terminal 或 VoiceOverlay"
echo "   3. 系统设置 -> 隐私与安全性 -> 麦克风"
echo "   4. 允许 VoiceOverlay 访问麦克风"
echo ""
