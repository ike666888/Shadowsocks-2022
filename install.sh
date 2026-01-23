#!/bin/bash
# Shadowsocks + Socks5 一键安装脚本 (v6.3 全能整合版)
# 适配: Debian/Ubuntu/CentOS/Alpine (Systemd & OpenRC)

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

# --- 0. 系统环境检测 ---
check_os() {
    if [ -f /etc/alpine-release ]; then
        OS_TYPE="alpine"
        INIT_SYSTEM="openrc"
        LIBC_TYPE="musl"
        if ! command -v bash >/dev/null 2>&1; then apk update && apk add bash; fi
    elif [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_TYPE=$ID
        INIT_SYSTEM="systemd"
        LIBC_TYPE="gnu"
    else
        echo -e "${RED}无法识别系统类型，脚本退出。${PLAIN}"
        exit 1
    fi
}

# --- 1. 权限与架构检查 ---
if [[ $EUID -ne 0 ]]; then echo -e "${RED}错误：必须使用 root 用户！${PLAIN}"; exit 1; fi
check_os

ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
    GOST_ARCH="amd64"
    if [[ "$LIBC_TYPE" == "musl" ]]; then
        SS_ARCH="x86_64-unknown-linux-musl"
        TLS_ARCH="x86_64-unknown-linux-musl"
    else
        SS_ARCH="x86_64-unknown-linux-gnu"
        TLS_ARCH="x86_64-unknown-linux-musl"
    fi
elif [[ "$ARCH" =~ (aarch64|arm64) ]]; then
    GOST_ARCH="arm64"
    if [[ "$LIBC_TYPE" == "musl" ]]; then
        SS_ARCH="aarch64-unknown-linux-musl"
        TLS_ARCH="aarch64-unknown-linux-musl"
    else
        SS_ARCH="aarch64-unknown-linux-gnu"
        TLS_ARCH="aarch64-unknown-linux-musl"
    fi
else
    echo -e "${RED}不支持的架构: $ARCH${PLAIN}"; exit 1
fi

# --- 2. 依赖安装与BBR ---
prepare_system() {
    echo -e "${YELLOW}[系统] 环境: $OS_TYPE ($INIT_SYSTEM / $LIBC_TYPE)${PLAIN}"
    echo -e "${YELLOW}[系统] 安装依赖...${PLAIN}"
    
    if [[ "$OS_TYPE" == "alpine" ]]; then
        apk update
        apk add curl wget tar xz openssl jq coreutils libcap
        modprobe tcp_bbr 2>/dev/null || true
    elif [[ "$OS_TYPE" =~ (ubuntu|debian|kali) ]]; then
        apt update -q && apt install -y wget tar openssl xz-utils curl jq lsof gzip
    elif [[ "$OS_TYPE" =~ (centos|rhel|almalinux|rocky) ]]; then
        yum install -y epel-release && yum install -y wget tar openssl xz curl jq lsof firewalld gzip
    fi

    if [[ "$OS_TYPE" != "alpine" ]] && [[ "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)" != "bbr" ]]; then
        echo "net.core.default_qdisc=fq" > /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        sysctl -p >/dev/null 2>&1
    fi
}

check_port() {
    local PORT=$1
    if command -v ss >/dev/null 2>&1; then
        if ss -tulpn | grep -q ":$PORT "; then return 1; fi
    elif command -v netstat >/dev/null 2>&1; then
        if netstat -tulpn | grep -q ":$PORT "; then return 1; fi
    elif command -v lsof >/dev/null 2>&1; then
        if lsof -i:$PORT >/dev/null 2>&1; then return 1; fi
    fi
    return 0
}

# --- 3. 服务创建 (Systemd/OpenRC) ---
create_service() {
    local NAME=$1
    local CMD=$2
    local ARGS=$3
    
    if [[ "$INIT_SYSTEM" == "systemd" ]]; then
        cat > /etc/systemd/system/${NAME}.service <<EOF
[Unit]
Description=${NAME} Service
After=network.target
[Service]
User=nobody
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
ExecStart=${CMD} ${ARGS}
Restart=always
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable --now ${NAME}

    elif [[ "$INIT_SYSTEM" == "openrc" ]]; then
        cat > /etc/init.d/${NAME} <<EOF
#!/sbin/openrc-run
name="${NAME}"
command="${CMD}"
command_args="${ARGS}"
command_background=true
pidfile="/run/${NAME}.pid"
output_log="/var/log/${NAME}.log"
error_log="/var/log/${NAME}.err"
depend() {
    need net
}
EOF
        chmod +x /etc/init.d/${NAME}
        setcap cap_net_bind_service=+ep ${CMD} 2>/dev/null
        rc-update add ${NAME} default
        rc-service ${NAME} restart
    fi
}

# --- 4. 卸载逻辑 ---
uninstall_services() {
    echo -e "${YELLOW}[卸载] 请选择:${PLAIN}"
    echo -e "  1) 卸载 Shadowsocks & ShadowTLS"
    echo -e "  2) 卸载 SOCKS5 (Gost)"
    echo -e "  3) 卸载 全部"
    read -p "选项 [1-3]: " UN_OPT
    
    stop_svc() {
        if [[ "$INIT_SYSTEM" == "systemd" ]]; then
            systemctl stop $1 2>/dev/null; systemctl disable $1 2>/dev/null
            rm -f /etc/systemd/system/$1.service
        else
            rc-service $1 stop 2>/dev/null; rc-update del $1 default 2>/dev/null
            rm -f /etc/init.d/$1
        fi
    }

    case "${UN_OPT:-3}" in
        1|3)
            stop_svc ss-rust
            stop_svc shadow-tls
            rm -f /usr/local/bin/ssserver /usr/local/bin/shadow-tls $CONFIG_FILE
            echo -e "${GREEN}SS 组件已卸载。${PLAIN}"
            ;;
    esac
    case "${UN_OPT:-3}" in
        2|3)
            stop_svc gost
            rm -f /usr/local/bin/gost
            echo -e "${GREEN}SOCKS5 组件已卸载。${PLAIN}"
            ;;
    esac
    [[ "$INIT_SYSTEM" == "systemd" ]] && systemctl daemon-reload
}

show_menu() {
    clear
    echo -e "${GREEN}==============================================${PLAIN}"
    echo -e "${GREEN}   Shadowsocks + Socks5 全能整合版 (v6.3)     ${PLAIN}"
    echo -e "${GREEN}==============================================${PLAIN}"
    echo -e "系统: ${YELLOW}$OS_TYPE${PLAIN} | 架构: ${YELLOW}$ARCH ($LIBC_TYPE)${PLAIN}"
    echo -e "----------------------------------------------"
    echo -e "${GREEN}1.${PLAIN} 安装 Shadowsocks 2022"
    echo -e "${GREEN}2.${PLAIN} 安装 Shadowsocks 2022 + ShadowTLS"
    echo -e "${GREEN}3.${PLAIN} 安装 SOCKS5 代理 (Gost v${GOST_VER})"
    echo -e "${RED}4.${PLAIN} 卸载服务"
    echo -e "${GREEN}5.${PLAIN} 退出"
    echo -e "----------------------------------------------"
    read -p "请输入选项 [1-5]: " MENU_CHOICE
}

# --- 底部署名函数 ---
show_footer() {
    echo -e ""
    echo -e "${GREEN}==============================================${PLAIN}"
    echo -e "${YELLOW}   脚本作者: ike${PLAIN}"
    echo -e "${YELLOW}   交流群组: https://t.me/pbox2026${PLAIN}"
    echo -e "${GREEN}==============================================${PLAIN}"
    echo -e ""
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

    echo -e "${YELLOW}[安装] Gost...${PLAIN}"
    if [[ "$OS_TYPE" == "alpine" ]]; then
        GOST_URL="https://github.com/ginuerzh/gost/releases/download/v2.11.5/gost-linux-${GOST_ARCH}-2.11.5.gz"
        wget -q "$GOST_URL" -O /tmp/gost.gz && gzip -d -f /tmp/gost.gz && mv /tmp/gost /usr/local/bin/gost
    else
        GOST_URL="https://github.com/ginuerzh/gost/releases/download/v${GOST_VER}/gost_${GOST_VER}_linux_${GOST_ARCH}.tar.gz"
        wget -q "$GOST_URL" -O /tmp/gost.tar.gz && tar -xzf /tmp/gost.tar.gz -C /tmp && mv /tmp/gost /usr/local/bin/gost
    fi
    chmod +x /usr/local/bin/gost

    create_service "gost" "/usr/local/bin/gost" "-L ${SOCK_USER}:${SOCK_PASS}@:${SOCK_PORT} socks5"
    
    PUBLIC_IP=$(curl -s4 ifconfig.me)
    SOCKS5_LINK="socks5://${SOCK_USER}:${SOCK_PASS}@${PUBLIC_IP}:${SOCK_PORT}"
    echo -e "\n${GREEN}>>> SOCKS5 部署成功 ($OS_TYPE) <<<${PLAIN}"
    echo -e "${YELLOW}链接:${PLAIN} ${SOCKS5_LINK}"
    show_footer
}

# --- SS 配置 ---
configure_ss() {
    echo -e "\n${YELLOW}[配置] 加密协议:${PLAIN}"
    echo -e "  1) 2022-blake3-aes-128-gcm ${GREEN}(推荐)${PLAIN}"
    echo -e "  2) 2022-blake3-aes-256-gcm"
    echo -e "  3) 2022-blake3-chacha20-poly1305"
    echo -e "  4) aes-128-gcm (经典)"
    echo -e "  5) aes-256-gcm (经典)"
    echo -e "  6) chacha20-ietf-poly1305 (经典)"
    
    read -p "选项 [1-6] (默认: 1): " M_NUM
    case "${M_NUM:-1}" in
        1) METHOD="2022-blake3-aes-128-gcm"; KEY_LEN=16 ;;
        2) METHOD="2022-blake3-aes-256-gcm"; KEY_LEN=32 ;;
        3) METHOD="2022-blake3-chacha20-poly1305"; KEY_LEN=32 ;;
        4) METHOD="aes-128-gcm"; KEY_LEN=16 ;;
        5) METHOD="aes-256-gcm"; KEY_LEN=32 ;;
        6) METHOD="chacha20-ietf-poly1305"; KEY_LEN=32 ;;
        *) METHOD="2022-blake3-aes-128-gcm"; KEY_LEN=16 ;;
    esac

    while true; do
        read -p "SS 端口 (默认: 9000): " IN_PORT
        SS_PORT=${IN_PORT:-9000}
        if check_port $SS_PORT; then break; else echo -e "${RED}端口占用！${PLAIN}"; fi
    done

    if [[ "$OS_TYPE" == "alpine" ]]; then
        echo -e "${YELLOW}Alpine 环境已自动关闭 Multiplex。${PLAIN}"
        MUX_CONF=""
    else
        read -p "开启 Multiplex? [y/n] (默认: n): " EN_MUX
        [[ "${EN_MUX:-n}" =~ ^[yY]$ ]] && MUX_CONF=', "multiplex": { "enabled": true }'
    fi
    SS_PASSWORD=$(openssl rand -base64 $KEY_LEN)
    
    if [[ "$MENU_CHOICE" == "2" ]]; then
        while true; do
            read -p "伪装域名 (默认: www.microsoft.com): " IN_DOM
            FAKE_DOMAIN=${IN_DOM:-www.microsoft.com}
            ping -c 1 -W 2 $FAKE_DOMAIN >/dev/null 2>&1 && break
            echo -e "${RED}无法连接 $FAKE_DOMAIN，请重试${PLAIN}"
            [[ "$OS_TYPE" == "alpine" ]] && break
        done
        TLS_PASSWORD=$(openssl rand -hex 8)
    fi
}

# --- SS 安装 ---
install_ss() {
    echo -e "${YELLOW}[安装] SS-Rust ($LIBC_TYPE)...${PLAIN}"
    SS_TAG=$(curl -s https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/latest | grep 'tag_name' | cut -d\" -f4)
    if [[ -z "$SS_TAG" ]]; then SS_TAG=$FALLBACK_SS_VER; fi
    
    SS_URL="https://github.com/shadowsocks/shadowsocks-rust/releases/download/${SS_TAG}/shadowsocks-${SS_TAG}.${SS_ARCH}.tar.xz"
    
    wget -q "$SS_URL" || { echo "${RED}下载失败，尝试回退版本${PLAIN}"; SS_TAG=$FALLBACK_SS_VER; SS_URL="https://github.com/shadowsocks/shadowsocks-rust/releases/download/${SS_TAG}/shadowsocks-${SS_TAG}.${SS_ARCH}.tar.xz"; wget -q "$SS_URL"; }
    
    tar -xf shadowsocks-*.tar.xz
    mv ssserver /usr/local/bin/ && chmod +x /usr/local/bin/ssserver
    rm -f sslocal ssurl ssmanager shadowsocks-*.tar.xz

    LISTEN_ADDR=$([ "$MENU_CHOICE" == "1" ] && echo "0.0.0.0" || echo "127.0.0.1")
    cat > $CONFIG_FILE <<EOF
{
    "server": "$LISTEN_ADDR", "server_port": $SS_PORT,
    "password": "$SS_PASSWORD", "method": "$METHOD",
    "mode": "tcp_and_udp", "tcp_fast_open": true$MUX_CONF
}
EOF
    chmod 644 $CONFIG_FILE
    create_service "ss-rust" "/usr/local/bin/ssserver" "-c $CONFIG_FILE"
}

# --- ShadowTLS 安装 ---
install_tls() {
    echo -e "${YELLOW}[安装] ShadowTLS...${PLAIN}"
    wget -q "https://github.com/ihciah/shadow-tls/releases/latest/download/shadow-tls-${TLS_ARCH}" -O /usr/local/bin/shadow-tls
    chmod +x /usr/local/bin/shadow-tls

    create_service "shadow-tls" "/usr/local/bin/shadow-tls" "--v3 server --listen 0.0.0.0:$TLS_PORT --server 127.0.0.1:$SS_PORT --tls $FAKE_DOMAIN:$TLS_PORT --password $TLS_PASSWORD"
}

finalize_ss() {
    [[ "$OS_TYPE" != "alpine" ]] && command -v ufw >/dev/null && ufw allow $SS_PORT/tcp && ufw allow $SS_PORT/udp
    echo -e "${YELLOW}[注意] 请务必在云服务器后台放行 TCP/UDP 端口！${PLAIN}"
}

show_ss_result() {
    PUBLIC_IP=$(curl -s4 ifconfig.me)
    USER_INFO=$(echo -n "${METHOD}:${SS_PASSWORD}" | base64 -w 0)
    
    echo -e "\n${GREEN}>>> SS/TLS 部署成功 ($OS_TYPE) <<<${PLAIN}"
    echo -e "IP: ${PUBLIC_IP}  端口: ${TLS_PORT}"
    echo -e "密码: ${SS_PASSWORD}"
    echo -e "加密: ${METHOD}"
    
    if [[ "$MENU_CHOICE" == "2" ]]; then
        ROCKET_JSON="{\"version\":\"3\",\"host\":\"${FAKE_DOMAIN}\",\"password\":\"${TLS_PASSWORD}\"}"
        ROCKET_PARAM=$(echo -n "$ROCKET_JSON" | base64 -w 0)
        ROCKET_LINK="ss://${USER_INFO}@${PUBLIC_IP}:${TLS_PORT}?shadow-tls=${ROCKET_PARAM}#ShadowTLS"
        echo -e "\n${YELLOW}[小火箭]${PLAIN} ${ROCKET_LINK}"
    else
        echo -e "\n${YELLOW}[SS链接]${PLAIN} ss://${USER_INFO}@${PUBLIC_IP}:${SS_PORT}#SS-Node"
    fi
    show_footer
}

# --- 主程序 ---
show_menu
case "$MENU_CHOICE" in
    1) prepare_system; configure_ss; install_ss; finalize_ss; show_ss_result ;;
    2) prepare_system; configure_ss; install_ss; install_tls; finalize_ss; show_ss_result ;;
    3) prepare_system; install_socks5 ;;
    4) uninstall_services; exit 0 ;;
    5) rm -- "$0"; echo "Bye"; exit 0 ;;
    *) echo "Error"; exit 1 ;;
esac
