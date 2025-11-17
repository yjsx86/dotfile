#!/bin/bash
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# 检查是否为root用户
if [ "$(id -u)" -eq 0 ]; then
    echo -e "${YELLOW}警告：不建议使用root用户执行此脚本，请使用普通用户执行${NC}"
    read -p "是否继续？[y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# 获取CPU架构
ARCH=$(uname -m)
echo -e "${GREEN}检测到CPU架构: ${ARCH}${NC}"

# 1. 检查并安装依赖
sudo apt update
echo -e "${GREEN}[1/5] 检查并安装依赖 (git, zsh, build-essential, wget, xz-utils, fd-find, btop, fzf, tmux)...${NC}"
DEPENDENCIES=(git zsh build-essential wget xz-utils fd-find btop fzf tmux)
MISSING_DEPS=()

# 为每个包定义对应的检查命令或使用dpkg检查
check_package_installed() {
    # 使用dpkg -l检查包是否已安装
    if dpkg -l | grep -q "^ii\s*$1\s"; then
        return 0  # 包已安装
    else
        return 1  # 包未安装
    fi
}

for dep in "${DEPENDENCIES[@]}"; do
    if ! check_package_installed "$dep"; then
        MISSING_DEPS+=("$dep")
    fi
done

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    echo -e "${YELLOW}以下依赖未安装: ${MISSING_DEPS[*]}${NC}"
    echo -e "${GREEN}正在安装依赖...${NC}"
    sudo apt install -y "${MISSING_DEPS[@]}"
else
    echo -e "${GREEN}所有依赖已安装${NC}"
fi

# 特别处理 fd-find 的软连接
if command -v fd &> /dev/null; then
    sudo ln -sf $(command -v fdfind) /usr/local/bin/fd
    echo -e "${GREEN}软连接创建成功: fdfind → fd${NC}"
fi

# 2. 安装Helix编辑器
echo -e "\n${GREEN}[2/5] 安装Helix编辑器...${NC}"
if ! command -v hx &> /dev/null; then
    echo -e "${GREEN}正在安装Helix...${NC}"
    
    # 删除原有的apt安装逻辑，直接使用GitHub下载
    echo -e "${YELLOW}从GitHub下载Helix（适配 ${ARCH}）...${NC}"
    LATEST_RELEASE=$(curl -s https://api.github.com/repos/helix-editor/helix/releases/latest | grep "browser_download_url.*-${ARCH}-linux.tar.xz" | cut -d '"' -f 4)
    
    if [ -z "$LATEST_RELEASE" ]; then
        echo -e "${RED}错误：无法获取Helix下载链接，请检查网络或手动安装${NC}"
        exit 1
    fi
    
    wget -O helix.tar.xz "$LATEST_RELEASE"
    tar -xvf helix.tar.xz
    sudo mv helix-*/hx /usr/local/bin/
    
    # 创建运行时目录
    mkdir -p ~/.config/helix
    sudo mv helix-*/runtime ~/.config/helix/
    
    # 清理临时文件
    rm -rf helix-* helix.tar.xz
    echo -e "${GREEN}Helix安装完成！${NC}"
else
    echo -e "${YELLOW}Helix已安装，跳过安装步骤${NC}"
fi

# 3. 安装Docker
echo -e "\n${GREEN}[3/5] 安装Docker...${NC}"
if ! command -v docker &> /dev/null; then
    echo -e "${GREEN}正在安装Docker...${NC}"
    # 安装Docker官方依赖
    sudo apt install -y ca-certificates
    # 添加Docker官方GPG密钥
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    # 添加Docker仓库（适配Debian和CPU架构）
    echo \
	    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
	    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
	    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    # 安装Docker
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    echo -e "${GREEN}Docker安装完成！请重新登录以使用docker命令。${NC}"
else
    echo -e "${YELLOW}Docker已安装，跳过安装步骤${NC}"
fi

# 4. 安装Oh My Zsh
echo -e "\n${GREEN}[4/5] 安装Oh My Zsh...${NC}"
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    yes | RUNZSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

    # 安装zsh-autosuggestions插件
    echo -e "\n${GREEN}安装zsh-autosuggestions插件...${NC}"
    AUTOSUGGESTIONS_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"
    if [ ! -d "$AUTOSUGGESTIONS_DIR" ]; then
        git clone https://github.com/zsh-users/zsh-autosuggestions.git "$AUTOSUGGESTIONS_DIR"
    else
        echo -e "${YELLOW}插件zsh-autosuggestions已安装，跳过安装步骤${NC}"
    fi

    # 安装zsh-syntax-highlighting插件
    echo -e "\n${GREEN}安装zsh-syntax-highlighting插件...${NC}"
    SYNTAX_HIGHLIGHTING_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting"
    if [ ! -d "$SYNTAX_HIGHLIGHTING_DIR" ]; then
        git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$SYNTAX_HIGHLIGHTING_DIR"
    else
        echo -e "${YELLOW}插件zsh-syntax-highlighting已安装，跳过安装步骤${NC}"
    fi

    # 配置.zshrc文件
    echo -e "\n${GREEN}配置.zshrc文件...${NC}"
    ZSH_RC_FILE="$HOME/.zshrc"

    # 写入新配置
    cat > "$ZSH_RC_FILE" << 'EOL'
# Oh My Zsh配置
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="ys"

plugins=(
    fzf
    docker
    git
    sudo
    zsh-syntax-highlighting
    zsh-autosuggestions
)

source $ZSH/oh-my-zsh.sh

# 用户自定义配置可以添加在下面
EOL

    echo -e "${GREEN}配置已完成！${NC}"

    # 设置zsh为默认shell
    if [ "$SHELL" != "$(which zsh)" ]; then
        echo -e "\n${GREEN}设置zsh为默认shell...${NC}"
        if chsh -s "$(which zsh)"; then
            echo -e "${GREEN}完成！请重新登录或重启终端以使用zsh。${NC}"
        else
            echo -e "${RED}警告：无法更改默认shell，您可以手动运行: chsh -s $(which zsh)${NC}"
        fi
    else
        echo -e "\n${GREEN}zsh已经是您的默认shell${NC}"
    fi

else
    echo -e "${YELLOW}Oh My Zsh已安装，跳过安装步骤${NC}"
fi


# 5. 安装和配置fail2ban
echo -e "\n${GREEN}[5/5] 安装和配置fail2ban...${NC}"
if ! command -v fail2ban-server &> /dev/null; then
    echo -e "${GREEN}正在安装fail2ban...${NC}"
    sudo apt install -y fail2ban
    echo -e "${GREEN}fail2ban安装完成！${NC}"

    # 创建jail.local配置文件
    echo -e "${GREEN}正在配置fail2ban...${NC}"
    JAIL_LOCAL_FILE="/etc/fail2ban/jail.local"

    # 写入新配置
    sudo tee "$JAIL_LOCAL_FILE" > /dev/null << 'EOL'
[DEFAULT]
bantime  = 1d
findtime  = 10m
maxretry = 3
backend = systemd
[sshd]
enabled = true
port    = ssh
logpath = %(sshd_log)s
backend = %(sshd_backend)s
EOL

    # 设置fail2ban开机启动并立即启动
    echo -e "${GREEN}设置fail2ban开机启动并启动服务...${NC}"
    sudo systemctl enable fail2ban
    sudo systemctl start fail2ban

    # 检查服务状态
    if sudo systemctl is-active --quiet fail2ban; then
        echo -e "${GREEN}fail2ban服务启动成功！${NC}"
    else
        echo -e "${RED}警告：fail2ban服务启动失败，请检查配置。${NC}"
    fi

else
    echo -e "${YELLOW}fail2ban已安装，跳过安装步骤${NC}"
fi


echo -e "\n${GREEN}所有步骤已完成！${NC}"
echo -e "${YELLOW}您可以运行以下命令测试安装：${NC}"
echo "  - 即刻切换zsh: exec zsh"
echo "  - Helix编辑器: hx"
echo "  - Docker: docker --version"
echo "  - Docker运行测试: docker run hello-world"
echo "  - fail2ban状态检查: sudo systemctl status fail2ban"
echo "  - fail2ban封禁列表: sudo fail2ban-client status sshd"
