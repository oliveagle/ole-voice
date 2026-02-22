#!/bin/bash
# MLX 版本安装脚本 (Apple Silicon 优化)

echo "安装语音输入工具 - MLX 版本..."
echo "此版本针对 Apple Silicon (M1/M2/M3) 优化，速度更快"
echo ""

# 检查是否为 Apple Silicon
if [[ $(uname -m) != "arm64" ]]; then
    echo "⚠️  警告: 当前不是 Apple Silicon (M1/M2/M3) 设备"
    echo "     MLX 版本仍可运行，但可能没有性能优势"
    echo ""
fi

# 检查 Python3
if ! command -v python3 &> /dev/null; then
    echo "错误: 需要先安装 Python3"
    exit 1
fi

# 创建虚拟环境
if [ ! -d "venv" ]; then
    echo "创建虚拟环境..."
    python3 -m venv venv
fi

source venv/bin/activate

echo "升级 pip..."
pip install --upgrade pip -q

echo "安装基础依赖..."
pip install -q pyaudio pynput pyyaml pyperclip

echo "安装 MLX Whisper (Apple Silicon 优化)..."
pip install -q mlx-whisper

echo ""
echo "✅ MLX 版本安装完成！"
echo ""
echo "使用方法:"
echo "  ./run_mlx.sh       # 启动 MLX 版本"
echo ""
echo "MLX 版本优势:"
echo "  - 在 M1/M2/M3 上推理速度提升 3-5 倍"
echo "  - 更低的功耗"
echo "  - 完全本地运行，无需联网"
echo ""
echo "注意: 模型首次使用时会自动下载到 ~/.cache/mlx_whisper/"
