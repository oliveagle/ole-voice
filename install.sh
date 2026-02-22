#!/bin/bash
# 安装脚本

echo "安装语音输入工具..."

# 检查 Python3
if ! command -v python3 &> /dev/null; then
    echo "错误: 需要先安装 Python3"
    exit 1
fi

# 创建虚拟环境
echo "创建虚拟环境..."
python3 -m venv venv
source venv/bin/activate

# 升级 pip
echo "升级 pip..."
pip install --upgrade pip

# 安装依赖
echo "安装依赖..."
pip install -r requirements.txt

echo ""
echo "安装完成！"
echo ""
echo "使用方法:"
echo "  ./run.sh       # 启动语音输入"
echo ""
echo "配置文件: config.yaml"
echo "  - 修改快捷键: hotkey: f8"
echo "  - 更换模型: model.size: small"
echo "  - 修改语言: model.language: zh"
