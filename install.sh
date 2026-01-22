#!/bin/bash
# Shadowsocks 2022 + ShadowTLS V3 一键安装脚本
# 支持架构: AMD64 (x86_64) / ARM64 (aarch64)
# 支持系统: Debian/Ubuntu/CentOS/Rocky/Alma

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

SS_PORT=9000
TLS_PORT=443
CONFIG_FILE="/etc/ss-config.json"

# 检查 Root 权限
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}错误：必须使用 root 用户运行此脚本！${PLAIN}"
   exit 1
fi

# 架构检测
ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
    SS_ARCH="x86_64-unknown-linux-gnu"
    TLS_ARCH="x86_64-unknown-linux-musl"
elif [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
    SS_ARCH="aarch64-unknown-linux-gnu"
    TLS_ARCH="aarch64-unknown-linux-musl"
else
    echo -e "${RED}不支持的架构: $ARCH${PLAIN}"
    exit 1
fi

# 卸载清理函数
uninstall_services() {
    echo -e "${YELLOW}[清理] 正在停止服务并清除文件...${PLAIN}"
    systemctl stop ss-rust shadow-tls >/dev/null 2>&1
    systemctl disable ss-rust shadow-tls >/dev/null 2>&1
    
    rm -f /etc/systemd/system/ss-rust.service
    rm -f /etc/systemd/system/shadow-tls.service
    rm -f /usr/local/bin/ssserver
    rm -f /usr/local/bin/shadow-tls
    rm -f $CONFIG_FILE
    
    systemctl daemon-reload
    echo -e "${GREEN}[成功] 旧版本/旧文件已卸载完毕。${PLAIN}"
}

# 启动时检测
check_status() {
    if [[ -f "/etc/systemd/system/ss-rust.service" || -f "/usr/local/bin/ssserver" ]]; then
        echo -e "${RED}==============================================${PLAIN}"
        echo -e "${RED}警告：检测到系统中已安装过 Shadowsocks/ShadowTLS！${PLAIN}"
        echo -e "${RED}==============================================${PLAIN}"
        echo -e "建议先清理旧环境再进行安装。"
        read -p "是否删除旧版本并重新开始安装? [y/n] (默认: y): " REINSTALL
        REINSTALL=${REINSTALL:-y}
        
        if [[ "$REINSTALL" =~ ^[yY]$ ]]; then
            uninstall_services
        else
            echo -e "${YELLOW}跳过清理，直接进入菜单。可能导致配置冲突！${PLAIN}"
        fi
        echo -e "----------------------------------------------"
        sleep 1
    fi
}

show_menu() {
    clear
    echo -e "${GREEN}==============================================${PLAIN}"
    echo -e "${GREEN}   Shadowsocks 2022 一键安装脚本 (全架构版)   ${PLAIN}"
    echo -e "${GREEN}==============================================${PLAIN}"
    echo -e "当前架构: ${YELLOW}$ARCH${PLAIN}"
    echo -e "----------------------------------------------"
    echo -e "${GREEN}1.${PLAIN} 仅安装 Shadowsocks 2022"
    echo -e "${GREEN}2.${PLAIN} 安装 Shadowsocks 2022 + ShadowTLS V3 (推荐)"
    echo -e "${RED}3.${PLAIN} 卸载 Shadowsocks & ShadowTLS"
    echo -e "${GREEN}4.${PLAIN} 退出脚本"
    echo -e "----------------------------------------------"
    read -p "请输入选项 [1-4]: " MENU_CHOICE
}

prepare_system() {
    echo -e "${YELLOW}[系统] 识别系统并安装依赖...${PLAIN}"
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        echo -e "${RED}无法检测系统版本。${PLAIN}"; exit 1
    fi

    if [[ "$OS" =~ (ubuntu|debian|kali) ]]; then
        apt update -q && apt install -y wget tar openssl xz-utils curl jq
    elif [[ "$OS" =~ (centos|rhel|almalinux|rocky) ]]; then
        yum install -y epel-release && yum install -y wget tar openssl xz curl jq firewalld
    else
        echo -e "${RED}不支持的系统: $OS${PLAIN}"; exit 1
    fi

    echo -e "${YELLOW}[优化] 网络配置检测...${PLAIN}"
    
    # BBR
    if [[ "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)" == "bbr" ]]; then
        echo -e "${GREEN}BBR 已开启。${PLAIN}"
    else
        read -p "是否开启 BBR + FQ? [y/n] (默认: y): " ENABLE_BBR
        if [[ "${ENABLE_BBR:-y}" =~ ^[yY]$ ]]; then
            echo "net.core.default_qdisc=fq" > /etc/sysctl.conf
            echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
            echo -e "${GREEN}BBR 已开启。${PLAIN}"
        fi
    fi

    # IPv6
    if [[ "$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null)" == "1" ]]; then
        echo -e "${GREEN}IPv6 已关闭。${PLAIN}"
    else
        read -p "是否强制关闭 IPv6 (防断流)? [y/n] (默认: y): " DISABLE_IPV6
        if [[ "${DISABLE_IPV6:-y}" =~ ^[yY]$ ]]; then
            echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.conf
            echo "net.ipv6.conf.default.disable_ipv6 = 1" >> /etc/sysctl.conf
            echo -e "${GREEN}IPv6 已关闭。${PLAIN}"
        fi
    fi
    sysctl -p >/dev/null 2>&1

    # Swap
    echo -e "${YELLOW}[内存] Swap 检测...${PLAIN}"
    if grep -q "swap" /etc/fstab; then
        echo -e "${GREEN}Swap 已存在。${PLAIN}"
    else
        read -p "是否创建 1GB Swap? [y/n] (默认: y): " CREATE_SWAP
        if [[ "${CREATE_SWAP:-y}" =~ ^[yY]$ ]]; then
            fallocate -l 1G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
            echo '/swapfile none swap sw 0 0' >> /etc/fstab
            echo -e "${GREEN}Swap 创建成功。${PLAIN}"
        fi
    fi
}

configure_params() {
    echo -e "\n${YELLOW}[配置] 选择加密协议:${PLAIN}"
    echo -e "  1) 2022-blake3-aes-128-gcm       ${GREEN}(性能推荐)${PLAIN}"
    echo -e "  2) 2022-blake3-aes-256-gcm       (高安)"
    echo -e "  3) 2022-blake3-chacha20-poly1305 (ARM/移动端优化)"
    read -p "请输入选项 [1-3] (默认: 1): " METHOD_NUM
    METHOD_NUM=${METHOD_NUM:-1}

    case "$METHOD_NUM" in
        1) METHOD="2022-blake3-aes-128-gcm"; KEY_LEN=16 ;;
        2) METHOD="2022-blake3-aes-256-gcm"; KEY_LEN=32 ;;
        3) METHOD="2022-blake3-chacha20-poly1305"; KEY_LEN=32 ;;
        *) METHOD="2022-blake3-aes-128-gcm"; KEY_LEN=16 ;;
    esac

    SS_PASSWORD=$(openssl rand -base64 $KEY_LEN)
    
    if [[ "$MENU_CHOICE" == "2" ]]; then
        read -p "请输入伪装域名 (默认: www.microsoft.com): " INPUT_DOMAIN
        FAKE_DOMAIN=${INPUT_DOMAIN:-www.microsoft.com}
        TLS_PASSWORD=$(openssl rand -hex 8)
    fi
}

install_ss() {
    echo -e "${YELLOW}[安装] Shadowsocks-Rust ($ARCH)...${PLAIN}"
    SS_TAG=$(curl -s https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/latest | grep 'tag_name' | cut -d\" -f4)
    wget -q "https://github.com/shadowsocks/shadowsocks-rust/releases/download/${SS_TAG}/shadowsocks-${SS_TAG}.${SS_ARCH}.tar.xz"
    tar -xf shadowsocks-*.tar.xz
    mv ssserver /usr/local/bin/ && rm sslocal ssurl ssmanager shadowsocks-*.tar.xz 2>/dev/null
    chmod +x /usr/local/bin/ssserver

    # 监听地址逻辑
    if [[ "$MENU_CHOICE" == "1" ]]; then
        LISTEN_ADDR="0.0.0.0"
        FINAL_PORT=$SS_PORT
    else
        LISTEN_ADDR="127.0.0.1"
        FINAL_PORT=$TLS_PORT
    fi

    cat > $CONFIG_FILE <<EOF
{
    "server": "$LISTEN_ADDR",
    "server_port": $SS_PORT,
    "password": "$SS_PASSWORD",
    "method": "$METHOD",
    "mode": "tcp_and_udp",
    "tcp_fast_open": true
}
EOF

    cat > /etc/systemd/system/ss-rust.service <<EOF
[Unit]
Description=Shadowsocks-rust Server
After=network.target
[Service]
ExecStart=/usr/local/bin/ssserver -c $CONFIG_FILE
Restart=always
Environment=RUST_LOG=error
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
EOF
}

install_tls() {
    echo -e "${YELLOW}[安装] ShadowTLS V3 ($ARCH)...${PLAIN}"
    wget -q "https://github.com/ihciah/shadow-tls/releases/latest/download/shadow-tls-${TLS_ARCH}" -O /usr/local/bin/shadow-tls
    chmod +x /usr/local/bin/shadow-tls

    cat > /etc/systemd/system/shadow-tls.service <<EOF
[Unit]
Description=ShadowTLS Server
After=network.target
[Service]
ExecStart=/usr/local/bin/shadow-tls --v3 server --listen 0.0.0.0:$TLS_PORT --server 127.0.0.1:$SS_PORT --tls $FAKE_DOMAIN:$TLS_PORT --password $TLS_PASSWORD
Restart=always
RestartSec=5
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
EOF
    systemctl enable --now shadow-tls
}

finalize() {
    systemctl daemon-reload
    systemctl enable --now ss-rust
    
    OPEN_PORT=$([ "$MENU_CHOICE" == "1" ] && echo $SS_PORT || echo $TLS_PORT)

    echo -e "${YELLOW}[网络] 放行端口: $OPEN_PORT${PLAIN}"
    if command -v firewall-cmd >/dev/null 2>&1; then
        systemctl start firewalld 2>/dev/null
        firewall-cmd --zone=public --add-port=$OPEN_PORT/tcp --permanent >/dev/null 2>&1
        firewall-cmd --zone=public --add-port=$OPEN_PORT/udp --permanent >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
    elif command -v ufw >/dev/null 2>&1; then
        ufw allow $OPEN_PORT/tcp >/dev/null 2>&1
        ufw allow $OPEN_PORT/udp >/dev/null 2>&1
    fi
}

show_result() {
    PUBLIC_IP=$(curl -s4 ifconfig.me)
    USER_INFO=$(echo -n "${METHOD}:${SS_PASSWORD}" | base64 -w 0)

    echo -e ""
    echo -e "${GREEN}==============================================${PLAIN}"
    echo -e "${GREEN}             安装完成 ($ARCH)                 ${PLAIN}"
    echo -e "${GREEN}==============================================${PLAIN}"
    echo -e "服务器 IP    : ${PUBLIC_IP}"
    echo -e "端口 (Port)  : ${FINAL_PORT}"
    echo -e "SS 密码      : ${SS_PASSWORD}"
    echo -e "加密协议     : ${METHOD}"

    if [[ "$MENU_CHOICE" == "2" ]]; then
        echo -e "伪装域名     : ${FAKE_DOMAIN}"
        echo -e "ShadowTLS密码: ${TLS_PASSWORD}"
        echo -e "----------------------------------------------"
        
        # Shadowrocket 专用 JSON 参数
        ROCKET_JSON="{\"version\":\"3\",\"host\":\"${FAKE_DOMAIN}\",\"password\":\"${TLS_PASSWORD}\"}"
        ROCKET_PARAM=$(echo -n "$ROCKET_JSON" | base64 -w 0)
        
        ROCKET_LINK="ss://${USER_INFO}@${PUBLIC_IP}:${FINAL_PORT}?shadow-tls=${ROCKET_PARAM}#ShadowTLS-V3"
        NORMAL_LINK="ss://${USER_INFO}@${PUBLIC_IP}:${FINAL_PORT}/?plugin=shadow-tls%3Bhost%3D${FAKE_DOMAIN}%3Bpassword%3D${TLS_PASSWORD}"
        
        echo -e "${YELLOW}>>> Shadowrocket (小火箭) 专用链接 <<<${PLAIN}"
        echo -e "${ROCKET_LINK}"
        echo -e ""
        echo -e "${YELLOW}>>> NekoBox / v2rayN 通用链接 <<<${PLAIN}"
        echo -e "${NORMAL_LINK}"
    else
        SS_LINK="ss://${USER_INFO}@${PUBLIC_IP}:${FINAL_PORT}#SS-Node"
        echo -e "${YELLOW}>>> SS 链接 <<<${PLAIN}"
        echo -e "${SS_LINK}"
    fi
    echo -e ""
}

# --- 脚本执行入口 ---

# 1. 运行检测
check_status

# 2. 显示菜单
show_menu

case "$MENU_CHOICE" in
    1)
        prepare_system
        configure_params
        install_ss
        finalize
        show_result
        ;;
    2)
        prepare_system
        configure_params
        install_ss
        install_tls
        finalize
        show_result
        ;;
    3)
        # 单独的卸载逻辑
        uninstall_services
        echo -e "${GREEN}卸载完成。${PLAIN}"
        exit 0
        ;;
    4)
        echo -e "${YELLOW}正在清理脚本...${PLAIN}"
        rm -- "$0"
        echo -e "${GREEN}脚本已删除。${PLAIN}"
        exit 0
        ;;
    *)
        echo -e "${RED}无效选项。${PLAIN}"
        exit 1
        ;;
esac
