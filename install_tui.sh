#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

check_root() {
    if [ "$(id -u)" -eq 0 ]; then
        echo -e "${YELLOW}警告：不建议使用root用户执行此脚本，请使用普通用户执行${NC}"
        read -p "是否继续？[y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

check_package_installed() {
    if dpkg -l | grep -q "^ii\s*$1\s"; then
        return 0
    else
        return 1
    fi
}

install_dependencies() {
    echo -e "\n${GREEN}====== 安装依赖 ======${NC}"
    DEPENDENCIES=(git zsh build-essential wget xz-utils fd-find btop fzf tmux tree)
    MISSING_DEPS=()

    for dep in "${DEPENDENCIES[@]}"; do
        if ! check_package_installed "$dep"; then
            MISSING_DEPS+=("$dep")
        fi
    done

    if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
        echo -e "${YELLOW}以下依赖未安装: ${MISSING_DEPS[*]}${NC}"
        echo -e "${GREEN}正在安装依赖...${NC}"
        sudo apt update
        sudo apt install -y "${MISSING_DEPS[@]}"
    else
        echo -e "${GREEN}所有依赖已安装${NC}"
    fi

    if ! command -v fd &> /dev/null; then
        sudo ln -sf $(command -v fdfind) /usr/local/bin/fd
        echo -e "${GREEN}软连接创建成功: fdfind → fd${NC}"
    fi

    echo -e "${GREEN}依赖安装完成！${NC}"
}

install_helix() {
    echo -e "\n${GREEN}====== 安装Helix编辑器 ======${NC}"
    if command -v hx &> /dev/null; then
        echo -e "${YELLOW}Helix已安装，跳过安装步骤${NC}"
        return 0
    fi

    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="x86_64" ;;
        aarch64) ARCH="aarch64" ;;
        armv7l) ARCH="armv7l" ;;
        *) echo -e "${RED}不支持的架构: $ARCH${NC}"; return 1 ;;
    esac

    echo -e "${YELLOW}从GitHub下载Helix（适配 ${ARCH}）...${NC}"
    LATEST_RELEASE=$(curl -s https://api.github.com/repos/helix-editor/helix/releases/latest | grep "browser_download_url.*-${ARCH}-linux.tar.xz" | cut -d '"' -f 4)

    if [ -z "$LATEST_RELEASE" ]; then
        echo -e "${RED}错误：无法获取Helix下载链接，请检查网络或手动安装${NC}"
        return 1
    fi

    wget -O helix.tar.xz "$LATEST_RELEASE"
    tar -xvf helix.tar.xz
    sudo mv helix-*/hx /usr/local/bin/
    mkdir -p ~/.config/helix
    sudo mv helix-*/runtime ~/.config/helix/
    rm -rf helix-* helix.tar.xz
    echo -e "${GREEN}Helix安装完成！${NC}"
}

install_docker() {
    echo -e "\n${GREEN}====== 安装Docker ======${NC}"
    if command -v docker &> /dev/null; then
        echo -e "${YELLOW}Docker已安装，跳过安装步骤${NC}"
        return 0
    fi

    echo -e "${GREEN}正在安装Docker...${NC}"
    sudo apt install -y ca-certificates
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    echo -e "${GREEN}Docker安装完成！请重新登录以使用docker命令。${NC}"
}

install_ohmyzsh() {
    echo -e "\n${GREEN}====== 安装Oh My Zsh ======${NC}"
    if [ -d "$HOME/.oh-my-zsh" ]; then
        echo -e "${YELLOW}Oh My Zsh已安装，跳过安装步骤${NC}"
        return 0
    fi

    yes | RUNZSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

    echo -e "\n${GREEN}安装zsh-autosuggestions插件...${NC}"
    AUTOSUGGESTIONS_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"
    if [ ! -d "$AUTOSUGGESTIONS_DIR" ]; then
        git clone https://github.com/zsh-users/zsh-autosuggestions.git "$AUTOSUGGESTIONS_DIR"
    else
        echo -e "${YELLOW}插件zsh-autosuggestions已安装，跳过安装步骤${NC}"
    fi

    echo -e "\n${GREEN}安装zsh-syntax-highlighting插件...${NC}"
    SYNTAX_HIGHLIGHTING_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting"
    if [ ! -d "$SYNTAX_HIGHLIGHTING_DIR" ]; then
        git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$SYNTAX_HIGHLIGHTING_DIR"
    else
        echo -e "${YELLOW}插件zsh-syntax-highlighting已安装，跳过安装步骤${NC}"
    fi

    echo -e "\n${GREEN}配置.zshrc文件...${NC}"
    ZSH_RC_FILE="$HOME/.zshrc"
    cat > "$ZSH_RC_FILE" << 'EOL'
# Oh My Zsh配置
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="ys"

plugins=(
    z
    fzf
    docker
    git
    sudo
    zsh-autosuggestions
    zsh-syntax-highlighting
)

source $ZSH/oh-my-zsh.sh

# 用户自定义配置可以添加在下面
EOL

    echo -e "${GREEN}配置已完成！${NC}"

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
}

install_fail2ban() {
    echo -e "\n${GREEN}====== 安装和配置fail2ban ======${NC}"
    if command -v fail2ban-server &> /dev/null; then
        echo -e "${YELLOW}fail2ban已安装，跳过安装步骤${NC}"
        return 0
    fi

    echo -e "${GREEN}正在安装fail2ban...${NC}"
    sudo apt install -y fail2ban

    echo -e "${GREEN}正在配置fail2ban...${NC}"
    JAIL_LOCAL_FILE="/etc/fail2ban/jail.local"
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

    echo -e "${GREEN}设置fail2ban开机启动并启动服务...${NC}"
    sudo systemctl enable fail2ban
    sudo systemctl start fail2ban

    if sudo systemctl is-active --quiet fail2ban; then
        echo -e "${GREEN}fail2ban服务启动成功！${NC}"
    else
        echo -e "${RED}警告：fail2ban服务启动失败，请检查配置。${NC}"
    fi
}

print_banner() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                    Dotfile 安装程序 v2.0                      ║${NC}"
    echo -e "${CYAN}║                    请选择要安装的组件                          ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo
}

print_menu() {
    echo -e "${YELLOW}可用选项：${NC}"
    echo -e "  ${GREEN}[1]${NC} 安装基础依赖      - git, zsh, build-essential, wget 等"
    echo -e "  ${GREEN}[2]${NC} 安装Helix编辑器   - 现代终端文本编辑器"
    echo -e "  ${GREEN}[3]${NC} 安装Docker         - 容器化平台"
    echo -e "  ${GREEN}[4]${NC} 安装Oh My Zsh     - zsh框架 + 插件"
    echo -e "  ${GREEN}[5]${NC} 安装fail2ban      - SSH入侵防护"
    echo
    echo -e "${YELLOW}快捷选项：${NC}"
    echo -e "  ${GREEN}[a]${NC} 全选    ${GREEN}[n]${NC} 反选    ${GREEN}[0]${NC} 开始安装"
    echo -e "  ${GREEN}[q]${NC} 退出"
    echo
}

toggle_selection() {
    local idx=$1
    if [[ " ${SELECTED[@]} " =~ " $idx " ]]; then
        SELECTED=("${SELECTED[@]/$idx}")
    else
        SELECTED+=("$idx")
    fi
}

show_selection() {
    echo -e "${CYAN}当前选择: ${NC}"
    for i in 1 2 3 4 5; do
        if [[ " ${SELECTED[@]} " =~ " $i " ]]; then
            case $i in
                1) echo -ne "  ${GREEN}✓${NC} 基础依赖  " ;;
                2) echo -ne "  ${GREEN}✓${NC} Helix编辑器  " ;;
                3) echo -ne "  ${GREEN}✓${NC} Docker  " ;;
                4) echo -ne "  ${GREEN}✓${NC} Oh My Zsh  " ;;
                5) echo -ne "  ${GREEN}✓${NC} fail2ban  " ;;
            esac
        fi
    done
    echo
    echo
}

main() {
    check_root

    SELECTED=()

    while true; do
        print_banner
        show_selection
        print_menu

        read -p "请输入选项: " choice

        case $choice in
            1) toggle_selection 1 ;;
            2) toggle_selection 2 ;;
            3) toggle_selection 3 ;;
            4) toggle_selection 4 ;;
            5) toggle_selection 5 ;;
            a|A)
                SELECTED=(1 2 3 4 5)
                ;;
            n|N)
                for i in 1 2 3 4 5; do
                    if [[ " ${SELECTED[@]} " =~ " $i " ]]; then
                        SELECTED=("${SELECTED[@]/$i}")
                    else
                        SELECTED+=("$i")
                    fi
                done
                ;;
            0)
                if [ ${#SELECTED[@]} -eq 0 ]; then
                    echo -e "${RED}请至少选择一个组件！${NC}"
                    sleep 1
                else
                    break
                fi
                ;;
            q|Q)
                echo -e "${YELLOW}已退出${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选项！${NC}"
                sleep 1
                ;;
        esac
    done

    echo -e "\n${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                        开始安装                               ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"

    for item in "${SELECTED[@]}"; do
        case $item in
            1) install_dependencies ;;
            2) install_helix ;;
            3) install_docker ;;
            4) install_ohmyzsh ;;
            5) install_fail2ban ;;
        esac
    done

    echo -e "\n${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    所有安装完成！                             ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo -e "${YELLOW}您可以运行以下命令测试安装：${NC}"
    echo "  - Docker: docker --version"
    echo "  - fail2ban封禁列表: fail2ban-client status"
    echo "  - tmux配置文件: curl -fsSL https://raw.githubusercontent.com/yjsx86/dotfile/main/.config/tmux/tmux.conf -o ~/.config/tmux/tmux.conf"
    echo "  - helix配置文件: curl -fsSL https://raw.githubusercontent.com/yjsx86/dotfile/main/.config/helix/config.toml -o ~/.config/helix/config.toml"
}

main "$@"