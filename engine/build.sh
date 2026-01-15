#!/bin/bash

# 设置控制台输出颜色
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 镜像源地址
MIRROR_URL="https://pypi.tuna.tsinghua.edu.cn/simple"

# 操作系统检测
OS_TYPE="unknown"
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS_TYPE="macos"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS_TYPE="linux"
elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ "$OS" == "Windows_NT" ]]; then
    OS_TYPE="windows"
fi

echo -e "${GREEN}=== 字幕引擎构建工具 ===${NC}"
echo -e "${GREEN}检测到系统: $OS_TYPE${NC}"

# 函数：打印分割线
print_line() {
    echo -e "${GREEN}----------------------------------------${NC}"
}

# 菜单选择
echo -e "\n请选择操作模式："
echo "1. [仅构建] 跳过依赖安装，直接打包"
echo "2. [Conda] 使用 Conda 安装依赖并打包 (推荐)"
echo "3. [Venv]  使用 Venv (虚拟环境) 安装依赖并打包"
read -p "请输入选项 [1-3]: " MODE

# 依赖安装阶段
if [ "$MODE" == "2" ] || [ "$MODE" == "3" ]; then
    # 询问是否使用镜像
    read -p "是否使用国内镜像源加速 pip 下载 (清华源)? [Y/n] " USE_MIRROR
    PIP_ARGS=""
    if [[ "$USE_MIRROR" =~ ^[Nn]$ ]]; then
        echo -e "已选择：不使用镜像源"
    else
        echo -e "已选择：使用清华镜像源"
        PIP_ARGS="-i $MIRROR_URL"
        
        # 设置 Brew 镜像源环境变量
        if [ "$OS_TYPE" == "macos" ]; then
            export HOMEBREW_BOTTLE_DOMAIN="https://mirror.tuna.tsinghua.edu.cn/homebrew-bottles"
            export HOMEBREW_API_DOMAIN="https://mirror.tuna.tsinghua.edu.cn/homebrew-api"
            echo -e "已配置 Homebrew 环境变量 (Tuna)"
        fi
    fi
    print_line
fi

if [ "$MODE" == "2" ]; then

    # 处理 macOS 特有的 portaudio 依赖提示
    if [ "$OS_TYPE" == "macos" ]; then
        if ! brew list portaudio &> /dev/null; then
            echo -e "${YELLOW}警告: 未检测到 portaudio。macOS 安装 pyaudio 可能需要它。${NC}"
            echo -e "建议运行: brew install portaudio"
            read -p "是否尝试自动安装 portaudio (需要 Homebrew)? [y/N] " INSTALL_PA
            if [[ "$INSTALL_PA" =~ ^[Yy]$ ]]; then
                
                brew install portaudio
            fi
        fi
    fi

    # --- Conda 模式 ---
    echo -e "${YELLOW}>>> 进入 Conda 依赖安装流程${NC}"
    
    # 检测是否存在 condaEnv.yaml
    if [ -f "condaEnv.yaml" ]; then
        echo -e "${GREEN}检测到 condaEnv.yaml 文件。${NC}"
        read -p "是否使用此文件更新/创建当前目录下的 .venv 环境? [Y/n] " USE_YAML
        if [[ ! "$USE_YAML" =~ ^[Nn]$ ]]; then
            echo -e "${YELLOW}正在使用 condaEnv.yaml 更新/创建环境 (强制路径: ./engine/.venv)...${NC}"
            # 使用 update 命令，如果环境不存在会自动创建，存在则更新
            conda env update -p ./.venv -f condaEnv.yaml --prune
            
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}环境更新成功！${NC}"
                # 尝试激活新环境或指定 Python 路径
                # 由于 shell 脚本中激活 conda 环境比较复杂，我们这里直接设置 PYTHON_CMD 指向新环境
                if [ "$OS_TYPE" == "windows" ]; then
                    export PATH="$(pwd)/.venv/Scripts:$PATH"
                    PYTHON_CMD="$(pwd)/.venv/python.exe"
                else
                    export PATH="$(pwd)/.venv/bin:$PATH"
                    PYTHON_CMD="$(pwd)/.venv/bin/python"
                fi
                echo -e "已临时将 .venv 加入 PATH"
                
                # 重新检查 pyinstaller
                if ! command -v pyinstaller &> /dev/null; then
                     echo -e "${RED}警告: 在新环境中未找到 pyinstaller，尝试重新安装...${NC}"
                     conda install -p ./.venv -c conda-forge pyinstaller -y
                fi

                # 确保关键 pip 包已安装 (补救措施)
                echo -e "${YELLOW}检查关键 pip 依赖 (ollama, sherpa-onnx)...${NC}"
                $PYTHON_CMD -m pip install ollama sherpa-onnx $PIP_ARGS
                
                # 跳过手动安装步骤
                echo -e "${GREEN}依赖安装完成 (基于 condaEnv.yaml)${NC}"
                # 继续到构建阶段
            else
                echo -e "${RED}conda env create 失败。将尝试手动安装模式。${NC}"
            fi
        else
            echo -e "已跳过 condaEnv.yaml，进入手动安装模式。"
        fi
    fi

    # 如果没有使用 yaml 或者 yaml 安装失败，则继续手动检查流程
    if [[ "$USE_YAML" =~ ^[Nn]$ ]] || [ ! -f "condaEnv.yaml" ]; then
        # 检查 Conda 环境
        if [ -z "$CONDA_DEFAULT_ENV" ] && [ -z "$CONDA_PREFIX" ]; then
            echo -e "${RED}错误: 未检测到激活的 Conda 环境。${NC}"
            echo -e "请先在终端执行 ${YELLOW}conda activate <您的环境名>${NC}，然后重新运行此脚本。"
            exit 1
        fi
        echo -e "当前 Conda 环境: ${GREEN}${CONDA_DEFAULT_ENV:-$CONDA_PREFIX}${NC}"

        # 定义 Conda 包列表
        # 基础包
        CONDA_PKGS="dashscope numpy resampy pyinstaller googletrans requests openai"
        
        # 平台特定包
        if [ "$OS_TYPE" == "windows" ]; then
            echo -e "检测到 Windows 系统，添加 pyaudiowpatch..."
            CONDA_PKGS="$CONDA_PKGS pyaudiowpatch"
        else
            echo -e "检测到 macOS/Linux 系统，添加 pyaudio..."
            CONDA_PKGS="$CONDA_PKGS pyaudio"
        fi

        echo -e "准备通过 conda-forge 安装以下包："
        echo -e "${YELLOW}$CONDA_PKGS${NC}"
        
        echo -e "正在执行 Conda 安装..."
        conda install -c conda-forge $CONDA_PKGS -y
        
        if [ $? -ne 0 ]; then
            echo -e "${RED}Conda 安装部分包失败，将尝试继续...${NC}"
            read -p "按回车键继续，或 Ctrl+C 退出检查..."
        fi

        # 单独安装 vosk (使用 pip)
        echo -e "\n${YELLOW}正在通过 pip 安装 requirements.txt 中的依赖，确保依赖都已安装...${NC}"
        # 使用当前环境的 pip
        if [ -f "./.venv/bin/pip" ]; then
             ./.venv/bin/pip install -r requirements.txt $PIP_ARGS
        elif [ -f "./.venv/Scripts/pip.exe" ]; then
             ./.venv/Scripts/pip.exe install -r requirements.txt $PIP_ARGS
        else
             conda run -p ./.venv pip install -r requirements.txt $PIP_ARGS
        fi
    fi

elif [ "$MODE" == "3" ]; then
    # --- Venv 模式 ---
    echo -e "${YELLOW}>>> 进入 Venv 依赖安装流程${NC}"
    
    # 检查/创建 .venv
    if [ -z "$VIRTUAL_ENV" ]; then
        if [ ! -d ".venv" ]; then
            echo -e "未检测到 .venv，正在创建..."
            # 尝试找到合适的 python 命令
            if command -v python3.12 &> /dev/null; then
                PYTHON_CMD=python3.12
            elif command -v python3.10 &> /dev/null; then
                PYTHON_CMD=python3.10
            elif command -v python3 &> /dev/null; then
                PYTHON_CMD=python3
            else
                PYTHON_CMD=python
            fi
            echo -e "使用解释器: $PYTHON_CMD"
            $PYTHON_CMD -m venv .venv
        fi
        
        # 激活环境
        echo -e "激活虚拟环境..."
        if [ -f ".venv/bin/activate" ]; then
            source .venv/bin/activate
            PYTHON_CMD="$(pwd)/.venv/bin/python"
        elif [ -f ".venv/Scripts/activate" ]; then
            source .venv/Scripts/activate
            PYTHON_CMD="$(pwd)/.venv/Scripts/python.exe"
        else
            echo -e "${RED}错误: 无法激活虚拟环境。${NC}"
            exit 1
        fi
    else
        echo -e "已在虚拟环境中: $VIRTUAL_ENV"
        PYTHON_CMD="python"
    fi

    # 安装依赖
    echo -e "正在安装依赖 (requirements.txt)..."
    
    # 处理 macOS 特有的 portaudio 依赖提示
    if [ "$OS_TYPE" == "macos" ]; then
        if ! brew list portaudio &> /dev/null; then
            echo -e "${YELLOW}警告: 未检测到 portaudio。macOS 安装 pyaudio 可能需要它。${NC}"
            echo -e "建议运行: brew install portaudio"
            read -p "是否尝试自动安装 portaudio (需要 Homebrew)? [y/N] " INSTALL_PA
            if [[ "$INSTALL_PA" =~ ^[Yy]$ ]]; then
                
                brew install portaudio
            fi
        fi
    fi
    
    pip install -r requirements.txt $PIP_ARGS
fi

# --- 构建阶段 ---
print_line
echo -e "${YELLOW}>>> 开始构建流程${NC}"

# 确定构建命令
if [ -z "$PYTHON_CMD" ]; then
    PYTHON_CMD=".venv/bin/python"
fi

echo -e "使用 Python: $PYTHON_CMD"

# 检查 PyInstaller
if $PYTHON_CMD -m PyInstaller --version &> /dev/null; then
    PYINSTALLER_CMD="$PYTHON_CMD -m PyInstaller"
elif command -v pyinstaller &> /dev/null; then
    echo -e "${YELLOW}警告: Python 环境中未找到 PyInstaller 模块，尝试使用系统 pyinstaller 命令...${NC}"
    PYINSTALLER_CMD="pyinstaller"
else
    echo -e "${RED}错误: 未找到 PyInstaller。请确保已安装 pyinstaller。${NC}"
    exit 1
fi

echo -e "${GREEN}正在清理旧构建...${NC}"
rm -rf build dist

echo -e "${GREEN}执行 PyInstaller 打包...${NC}"
$PYINSTALLER_CMD ./main.spec --clean --noconfirm

if [ $? -eq 0 ]; then
    print_line
    echo -e "${GREEN}✔ 构建成功！${NC}"
    echo -e "可执行文件位于 dist 目录中。"
    ls -lh dist/
else
    echo -e "${RED}✘ 构建失败。${NC}"
    exit 1
fi
