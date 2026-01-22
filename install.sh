#!/bin/bash
# Shadowsocks + Socks5一键安装脚本 (v6.1)

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

SS_PORT=9000
TLS_PORT=443
SOCK_PORT=1080
CONFIG_FILE="/etc/ss-config.json"
FALLBACK_SS_VER="v1.22.0"
FALLBACK_TLS_VER="v0.2.25"
GOST_VER="2.12.0"

# 权限检测
if [[ $EUID -ne 0 ]]; then echo -e "${RED}错误：必须使用 root 用户！${PLAIN}"; exit 1; fi

# 架构检测
ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
    SS_ARCH="x86_64-unknown-linux-gnu"; TLS_ARCH="x86_64-unknown-linux-musl"
    GOST_ARCH="amd64"
elif [[ "$ARCH" =~ (aarch64|arm64) ]]; then
    SS_ARCH="aarch64-unknown-linux-gnu"; TLS_ARCH="aarch64-unknown-linux-musl"
    GOST_ARCH="arm64"
else
    echo -e "${RED}不支持的架构: $ARCH${PLAIN}"; exit 1
fi

# 端口占用检测
check_port() {
    local PORT=$1
    if command -v ss >/dev/null 2>&1; then
        if ss -tulpn | grep -q ":$PORT "; then return 1; fi
    elif command -v lsof >/dev/null 2>&1; then
        if lsof -i:$PORT >/dev/null 2>&1; then return 1; fi
    fi
    return 0
}

# 卸载服务
uninstall_services() {
    echo -e "${YELLOW}[卸载] 请选择:${PLAIN}"
    echo -e "  1) 卸载 Shadowsocks & ShadowTLS"
    echo -e "  2) 卸载 SOCKS5 (Gost)"
    echo -e "  3) 卸载 全部"
    read -p "选项 [1-3]: " UN_OPT
    case "${UN_OPT:-3}" in
        1|3)
            systemctl stop ss-rust shadow-tls >/dev/null 2>&1
            systemctl disable ss-rust shadow-tls >/dev/null 2>&1
            rm -f /etc/systemd/system/ss-rust.service /etc/systemd/system/shadow-tls.service
            rm -f /usr/local/bin/ssserver /usr/local/bin/shadow-tls $CONFIG_FILE
            echo -e "${GREEN}SS 组件已卸载。${PLAIN}"
            ;;
    esac
    case "${UN_OPT:-3}" in
        2|3)
            systemctl stop gost >/dev/null 2>&1
            systemctl disable gost >/dev/null 2>&1
            rm -f /etc/systemd/system/gost.service /usr/local/bin/gost
            echo -e "${GREEN}SOCKS5 组件已卸载。${PLAIN}"
            ;;
    esac
    systemctl daemon-reload
}

show_menu() {
    clear
    echo -e "${GREEN}==============================================${PLAIN}"
    echo -e "${GREEN}   Shadowsocks + Socks5一键安装脚本 (v6.1)    ${PLAIN}"
    echo -e "${GREEN}==============================================${PLAIN}"
    echo -e "架构: ${YELLOW}$ARCH${PLAIN}"
    echo -e "----------------------------------------------"
    echo -e "${GREEN}1.${PLAIN} 安装 Shadowsocks 2022"
    echo -e "${GREEN}2.${PLAIN} 安装 Shadowsocks 2022 + ShadowTLS"
    echo -e "${GREEN}3.${PLAIN} 安装 SOCKS5 代理 (Gost v${GOST_VER})"
    echo -e "${RED}4.${PLAIN} 卸载服务"
    echo -e "${GREEN}5.${PLAIN} 退出"
    echo -e "----------------------------------------------"
    read -p "请输入选项 [1-5]: " MENU_CHOICE
}

prepare_system() {
    echo -e "${YELLOW}[系统] 准备环境...${PLAIN}"
    if [ -f /etc/os-release ]; then . /etc/os-release; OS=$ID; fi
    if [[ "$OS" =~ (ubuntu|debian|kali) ]]; then
        apt update -q && apt install -y wget tar openssl xz-utils curl jq lsof gzip
    elif [[ "$OS" =~ (centos|rhel|almalinux|rocky) ]]; then
        yum install -y epel-release && yum install -y wget tar openssl xz curl jq lsof firewalld gzip
    else
        echo -e "${RED}系统不支持${PLAIN}"; exit 1
    fi

    if [[ "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)" != "bbr" ]]; then
        read -p "开启 BBR? [y/n] (默认: y): " EN_BBR
        if [[ "${EN_BBR:-y}" =~ ^[yY]$ ]]; then
            echo "net.core.default_qdisc=fq" > /etc/sysctl.conf
            echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
            sysctl -p >/dev/null 2>&1
        fi
    fi
}

# --- SOCKS5 安装 ---
install_socks5() {
    echo -e "\n${YELLOW}[配置] SOCKS5 参数:${PLAIN}"
    while true; do
        read -p "SOCKS5 端口 (默认: 1080): " IN_PORT
        SOCK_PORT=${IN_PORT:-1080}
        if check_port $SOCK_PORT; then break; else echo -e "${RED}端口占用！${PLAIN}"; fi
    done
    read -p "用户名 (默认: admin): " IN_USER
    SOCK_USER=${IN_USER:-admin}
    read -p "密码 (默认: 随机): " IN_PASS
    SOCK_PASS=${IN_PASS:-$(openssl rand -hex 4)}

    echo -e "${YELLOW}[安装] Gost v${GOST_VER}...${PLAIN}"
    GOST_URL="https://github.com/ginuerzh/gost/releases/download/v${GOST_VER}/gost_${GOST_VER}_linux_${GOST_ARCH}.tar.gz"
    
    wget -q "$GOST_URL" -O /tmp/gost.tar.gz
    if [[ ! -f "/tmp/gost.tar.gz" ]]; then
        echo -e "${RED}下载失败！请检查网络。${PLAIN}"; return 1
    fi
    
    cd /tmp
    tar -xzf gost.tar.gz
    mv gost /usr/local/bin/gost
    chmod +x /usr/local/bin/gost
    rm -f gost.tar.gz LICENSE README.md

    cat > /etc/systemd/system/gost.service <<EOF
[Unit]
Description=Gost SOCKS5
After=network.target
[Service]
User=nobody
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
ExecStart=/usr/local/bin/gost -L $SOCK_USER:$SOCK_PASS@:$SOCK_PORT socks5
Restart=always
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload && systemctl enable --now gost
    
    PUBLIC_IP=$(curl -s4 ifconfig.me)
    SOCKS5_LINK="socks5://${SOCK_USER}:${SOCK_PASS}@${PUBLIC_IP}:${SOCK_PORT}"
    
    echo -e "\n${GREEN}>>> SOCKS5 部署成功 (v${GOST_VER}) <<<${PLAIN}"
    echo -e "IP: ${PUBLIC_IP}  端口: ${SOCK_PORT}"
    echo -e "用户: ${SOCK_USER}  密码: ${SOCK_PASS}"
    echo -e "${YELLOW}链接:${PLAIN} ${SOCKS5_LINK}"
    echo -e ""
}

# --- SS 配置 ---
configure_ss() {
    echo -e "\n${YELLOW}[配置] SS 参数:${PLAIN}"
    echo -e "  1) 2022-blake3-aes-128-gcm ${GREEN}(推荐)${PLAIN}"
    echo -e "  2) aes-128-gcm"
    read -p "选项 [1-2] (默认: 1): " M_NUM
    case "${M_NUM:-1}" in
        1) METHOD="2022-blake3-aes-128-gcm"; KEY_LEN=16 ;;
        *) METHOD="aes-128-gcm"; KEY_LEN=16 ;;
    esac

    while true; do
        read -p "SS 端口 (默认: 9000): " IN_PORT
        SS_PORT=${IN_PORT:-9000}
        if check_port $SS_PORT; then break; else echo -e "${RED}端口占用！${PLAIN}"; fi
    done

    read -p "开启 Multiplex? [y/n] (默认: n): " EN_MUX
    [[ "${EN_MUX:-n}" =~ ^[yY]$ ]] && MUX_CONF=', "multiplex": { "enabled": true }'
    SS_PASSWORD=$(openssl rand -base64 $KEY_LEN)
    
    if [[ "$MENU_CHOICE" == "2" ]]; then
        while true; do
            read -p "伪装域名 (默认: www.microsoft.com): " IN_DOM
            FAKE_DOMAIN=${IN_DOM:-www.microsoft.com}
            if ping -c 1 -W 2 $FAKE_DOMAIN >/dev/null 2>&1; then break; else 
                echo -e "${RED}无法连接 $FAKE_DOMAIN${PLAIN}"; read -p "强制使用? [y/n]: " FORCE_DOM; [[ "$FORCE_DOM" =~ ^[yY]$ ]] && break
            fi
        done
        TLS_PASSWORD=$(openssl rand -hex 8)
    fi
}

# --- SS 安装 ---
install_ss() {
    echo -e "${YELLOW}[安装] SS-Rust...${PLAIN}"
    SS_TAG=$(curl -s --connect-timeout 5 https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/latest | grep 'tag_name' | cut -d\" -f4)
    if [[ -z "$SS_TAG" ]]; then SS_TAG=$FALLBACK_SS_VER; echo -e "${RED}使用备用版本 $SS_TAG${PLAIN}"; fi
    
    wget -q "https://github.com/shadowsocks/shadowsocks-rust/releases/download/${SS_TAG}/shadowsocks-${SS_TAG}.${SS_ARCH}.tar.xz"
    tar -xf shadowsocks-*.tar.xz
    mv ssserver /usr/local/bin/ && rm sslocal ssurl ssmanager shadowsocks-*.tar.xz 2>/dev/null
    chmod +x /usr/local/bin/ssserver

    LISTEN_ADDR=$([ "$MENU_CHOICE" == "1" ] && echo "0.0.0.0" || echo "127.0.0.1")
    cat > $CONFIG_FILE <<EOF
{
    "server": "$LISTEN_ADDR", "server_port": $SS_PORT,
    "password": "$SS_PASSWORD", "method": "$METHOD",
    "mode": "tcp_and_udp", "tcp_fast_open": true$MUX_CONF
}
EOF
    chmod 644 $CONFIG_FILE

    cat > /etc/systemd/system/ss-rust.service <<EOF
[Unit]
Description=SS-Rust
After=network.target
[Service]
User=nobody
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
ExecStart=/usr/local/bin/ssserver -c $CONFIG_FILE
Restart=always
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
EOF
}

# --- ShadowTLS 安装 ---
install_tls() {
    echo -e "${YELLOW}[安装] ShadowTLS...${PLAIN}"
    wget -q "https://github.com/ihciah/shadow-tls/releases/latest/download/shadow-tls-${TLS_ARCH}" -O /usr/local/bin/shadow-tls
    if [[ ! -f "/usr/local/bin/shadow-tls" ]]; then
        wget -q "https://github.com/ihciah/shadow-tls/releases/download/${FALLBACK_TLS_VER}/shadow-tls-${TLS_ARCH}" -O /usr/local/bin/shadow-tls
    fi
    chmod +x /usr/local/bin/shadow-tls

    cat > /etc/systemd/system/shadow-tls.service <<EOF
[Unit]
Description=ShadowTLS
After=network.target
[Service]
User=nobody
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
ExecStart=/usr/local/bin/shadow-tls --v3 server --listen 0.0.0.0:$TLS_PORT --server 127.0.0.1:$SS_PORT --tls $FAKE_DOMAIN:$TLS_PORT --password $TLS_PASSWORD
Restart=always
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
EOF
    systemctl enable --now shadow-tls
}

finalize_ss() {
    systemctl daemon-reload && systemctl enable --now ss-rust
    OPEN_PORT=$([ "$MENU_CHOICE" == "1" ] && echo $SS_PORT || echo $TLS_PORT)
    if command -v firewall-cmd >/dev/null 2>&1; then
        firewall-cmd --zone=public --add-port=$OPEN_PORT/tcp --permanent >/dev/null 2>&1
        firewall-cmd --zone=public --add-port=$OPEN_PORT/udp --permanent >/dev/null 2>&1
        firewall-cmd --reload >/dev/null 2>&1
    elif command -v ufw >/dev/null 2>&1; then
        ufw allow $OPEN_PORT/tcp >/dev/null 2>&1; ufw allow $OPEN_PORT/udp >/dev/null 2>&1
    fi
}

show_ss_result() {
    PUBLIC_IP=$(curl -s4 ifconfig.me)
    USER_INFO=$(echo -n "${METHOD}:${SS_PASSWORD}" | base64 -w 0)
    
    echo -e "\n${GREEN}>>> SS/TLS 部署成功 (安全模式) <<<${PLAIN}"
    echo -e "IP: ${PUBLIC_IP}  端口: ${TLS_PORT}"
    
    if [[ "$MENU_CHOICE" == "2" ]]; then
        ROCKET_JSON="{\"version\":\"3\",\"host\":\"${FAKE_DOMAIN}\",\"password\":\"${TLS_PASSWORD}\"}"
        ROCKET_PARAM=$(echo -n "$ROCKET_JSON" | base64 -w 0)
        ROCKET_LINK="ss://${USER_INFO}@${PUBLIC_IP}:${TLS_PORT}?shadow-tls=${ROCKET_PARAM}#ShadowTLS"
        NORMAL_LINK="ss://${USER_INFO}@${PUBLIC_IP}:${TLS_PORT}/?plugin=shadow-tls%3Bhost%3D${FAKE_DOMAIN}%3Bpassword%3D${TLS_PASSWORD}"
        
        echo -e "\n${YELLOW}[小火箭]${PLAIN} ${ROCKET_LINK}"
        echo -e "\n${YELLOW}[通用]${PLAIN} ${NORMAL_LINK}"
    else
        echo -e "\n${YELLOW}[SS链接]${PLAIN} ss://${USER_INFO}@${PUBLIC_IP}:${SS_PORT}#SS-Node"
    fi
    echo -e ""
}

# 主流程
show_menu
case "$MENU_CHOICE" in
    1) prepare_system; configure_ss; install_ss; finalize_ss; show_ss_result ;;
    2) prepare_system; configure_ss; install_ss; install_tls; finalize_ss; show_ss_result ;;
    3) prepare_system; install_socks5 ;;
    4) uninstall_services; exit 0 ;;
    5) rm -- "$0"; echo "Bye"; exit 0 ;;
    *) echo "Error"; exit 1 ;;
esac
