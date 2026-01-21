#!/bin/bash
# Description: Multi-mode Installer for Shadowsocks-2022 & ShadowTLS
# Author: Gemini Assistant
# System: Debian/Ubuntu/CentOS/Rocky/Alma

# === 颜色定义 ===
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
PLAIN="\033[0m"

# === 全局变量 ===
SS_PORT=9000
TLS_PORT=443
CONFIG_FILE="/etc/ss-config.json"

# === 检查 Root ===
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}错误：必须使用 root 用户运行此脚本！${PLAIN}"
   exit 1
fi

# === 菜单函数 ===
show_menu() {
    clear
    echo -e "${GREEN}==============================================${PLAIN}"
    echo -e "${GREEN}   Shadowsocks 2022 全能安装脚本 (Rust版)     ${PLAIN}"
    echo -e "${GREEN}==============================================${PLAIN}"
    echo -e "请选择安装模式："
    echo -e "${GREEN}1.${PLAIN} 仅安装 Shadowsocks 2022 (普通模式)"
    echo -e "${GREEN}2.${PLAIN} 安装 Shadowsocks 2022 + ShadowTLS (伪装模式 - 推荐)"
    echo -e "${GREEN}3.${PLAIN} 退出脚本并清理残留文件"
    echo -e "----------------------------------------------"
    read -p "请输入选项 [1-3]: " MENU_CHOICE
}

# === 基础环境配置函数 ===
prepare_system() {
    echo -e "${YELLOW}[系统] 正在识别系统并安装依赖...${PLAIN}"
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        echo -e "${RED}无法检测系统版本。${PLAIN}"; exit 1
    fi

    if [[ "$OS" == "ubuntu" || "$OS" == "debian" || "$OS" == "kali" ]]; then
        apt update -q && apt install -y wget tar openssl xz-utils curl jq
    elif [[ "$OS" == "centos" || "$OS" == "rhel" || "$OS" == "almalinux" || "$OS" == "rocky" ]]; then
        yum install -y epel-release && yum install -y wget tar openssl xz curl jq firewalld
    else
        echo -e "${RED}不支持的系统: $OS${PLAIN}"; exit 1
    fi

    # === 智能性能优化 (BBR + IPv6) ===
    echo -e "${YELLOW}[优化] 正在检测网络配置...${PLAIN}"
    
    # 1. BBR 检测与交互
    CURRENT_ALGO=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
    if [[ "$CURRENT_ALGO" == "bbr" ]]; then
        echo -e "${GREEN}检测到 BBR 已开启，跳过配置。${PLAIN}"
    else
        read -p "是否开启 BBR + FQ 加速? [y/n] (默认: y): " ENABLE_BBR
        ENABLE_BBR=${ENABLE_BBR:-y}
        if [[ "$ENABLE_BBR" =~ ^[yY]$ ]]; then
            echo "net.core.default_qdisc=fq" > /etc/sysctl.conf
            echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
            echo -e "${GREEN}BBR 已配置开启。${PLAIN}"
        else
            echo -e "${YELLOW}已取消开启 BBR。${PLAIN}"
        fi
    fi

    # 2. IPv6 检测与交互
    IPV6_DISABLED=$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null)
    if [[ "$IPV6_DISABLED" == "1" ]]; then
        echo -e "${GREEN}检测到 IPv6 已关闭，跳过配置。${PLAIN}"
    else
        read -p "是否强制关闭 IPv6 (防断流)? [y/n] (默认: y): " DISABLE_IPV6
        DISABLE_IPV6=${DISABLE_IPV6:-y}
        if [[ "$DISABLE_IPV6" =~ ^[yY]$ ]]; then
            echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.conf
            echo "net.ipv6.conf.default.disable_ipv6 = 1" >> /etc/sysctl.conf
            echo -e "${GREEN}IPv6 关闭指令已写入。${PLAIN}"
        else
            echo -e "${YELLOW}保持 IPv6 开启。${PLAIN}"
        fi
    fi
    
    # 应用内核参数
    sysctl -p >/dev/null 2>&1

    # === Swap 检查 ===
    echo -e "${YELLOW}[内存] 检查 Swap 配置...${PLAIN}"
    if grep -q "swap" /etc/fstab; then
        echo -e "${GREEN}检测到 Swap 已配置，跳过创建。${PLAIN}"
    else
        read -p "是否创建 1GB 虚拟内存 (Swap)? [y/n] (默认: y): " CREATE_SWAP
        CREATE_SWAP=${CREATE_SWAP:-y}
        if [[ "$CREATE_SWAP" =~ ^[yY]$ ]]; then
            echo -e "${YELLOW}正在创建 Swap...${PLAIN}"
            fallocate -l 1G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
            echo '/swapfile none swap sw 0 0' >> /etc/fstab
            echo -e "${GREEN}Swap 创建成功。${PLAIN}"
        fi
    fi
}

# === 参数配置函数 ===
configure_params() {
    echo -e "\n${YELLOW}[配置] 请选择加密协议:${PLAIN}"
    echo -e "  1) 2022-blake3-aes-128-gcm       ${GREEN}(EPYC/x86 推荐)${PLAIN}"
    echo -e "  2) 2022-blake3-aes-256-gcm       (更高安全性)"
    echo -e "  3) 2022-blake3-chacha20-poly1305 (移动端/ARM)"
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

# === 安装 SS 函数 ===
install_ss() {
    echo -e "${YELLOW}[安装] Shadowsocks-Rust...${PLAIN}"
    SS_TAG=$(curl -s https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/latest | grep 'tag_name' | cut -d\" -f4)
    wget -q "https://github.com/shadowsocks/shadowsocks-rust/releases/download/${SS_TAG}/shadowsocks-${SS_TAG}.x86_64-unknown-linux-gnu.tar.xz"
    tar -xf shadowsocks-*.tar.xz
    mv ssserver /usr/local/bin/ && rm sslocal ssurl ssmanager shadowsocks-*.tar.xz 2>/dev/null
    chmod +x /usr/local/bin/ssserver

    # 根据模式决定监听地址
    if [[ "$MENU_CHOICE" == "1" ]]; then
        LISTEN_ADDR="0.0.0.0"  # 纯 SS 模式，对外开放
        FINAL_PORT=$SS_PORT
    else
        LISTEN_ADDR="127.0.0.1" # ShadowTLS 模式，仅对内开放
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

# === 安装 ShadowTLS 函数 ===
install_tls() {
    echo -e "${YELLOW}[安装] ShadowTLS...${PLAIN}"
    wget -q https://github.com/ihciah/shadow-tls/releases/latest/download/shadow-tls-x86_64-unknown-linux-musl -O /usr/local/bin/shadow-tls
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

# === 防火墙与启动函数 ===
finalize() {
    systemctl daemon-reload
    systemctl enable --now ss-rust
    
    # 确定要放行的端口
    if [[ "$MENU_CHOICE" == "1" ]]; then
        OPEN_PORT=$SS_PORT
    else
        OPEN_PORT=$TLS_PORT
    fi

    echo -e "${YELLOW}[网络] 配置防火墙放行端口: $OPEN_PORT${PLAIN}"
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

# === 结果输出函数 ===
show_result() {
    PUBLIC_IP=$(curl -s4 ifconfig.me)
    USER_INFO=$(echo -n "${METHOD}:${SS_PASSWORD}" | base64 -w 0)

    echo -e ""
    echo -e "${GREEN}==============================================${PLAIN}"
    echo -e "${GREEN}             安装配置完成！                   ${PLAIN}"
    echo -e "${GREEN}==============================================${PLAIN}"
    echo -e "服务器 IP    : ${PUBLIC_IP}"
    echo -e "端口 (Port)  : ${FINAL_PORT}"
    echo -e "SS 密码      : ${SS_PASSWORD}"
    echo -e "加密协议     : ${METHOD}"

    if [[ "$MENU_CHOICE" == "2" ]]; then
        echo -e "伪装域名     : ${FAKE_DOMAIN}"
        echo -e "ShadowTLS密码: ${TLS_PASSWORD}"
        # 生成标准 SS+Plugin 链接
        SS_LINK="ss://${USER_INFO}@${PUBLIC_IP}:${FINAL_PORT}/?plugin=shadow-tls%3Bhost%3D${FAKE_DOMAIN}%3Bpassword%3D${TLS_PASSWORD}"
    else
        # 生成纯 SS 链接
        SS_LINK="ss://${USER_INFO}@${PUBLIC_IP}:${FINAL_PORT}"
    fi

    echo -e "${GREEN}==============================================${PLAIN}"
    echo -e "${YELLOW}>>> 一键连接链接 (复制导入客户端) <<<${PLAIN}"
    echo -e "${SS_LINK}"
    echo -e ""
}

# === 主逻辑 ===
show_menu

case "$MENU_CHOICE" in
    1)
        # 仅安装 SS
        prepare_system
        configure_params
        install_ss
        finalize
        show_result
        ;;
    2)
        # 安装 SS + ShadowTLS
        prepare_system
        configure_params
        install_ss
        install_tls
        finalize
        show_result
        ;;
    3)
        # 退出并清理
        echo -e "${YELLOW}正在清理脚本文件...${PLAIN}"
        rm -- "$0"
        echo -e "${GREEN}脚本已删除，再见！${PLAIN}"
        exit 0
        ;;
    *)
        echo -e "${RED}无效选项，脚本退出。${PLAIN}"
        exit 1
        ;;
esac
