#!/bin/bash

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

CONFIG_DIR="/etc/sing-box"
CONFIG_FILE="${CONFIG_DIR}/config.json"
BIN_PATH="/usr/local/bin/sing-box"
SHORTCUT_PATH="/usr/local/bin/sb"
IPV6_PREFERRED="false"
LINK_VIEW_MODE="dual"

check_os() {
    if [ -f /etc/alpine-release ]; then
        OS_TYPE="alpine"; INIT_SYSTEM="openrc"; LIBC_TYPE="musl"
        if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1 || ! command -v tar >/dev/null 2>&1 || ! command -v base64 >/dev/null 2>&1; then
            echo -e "${YELLOW}[系统] 补全依赖 (curl, jq, tar, base64)...${PLAIN}"
            apk update && apk add bash curl wget tar openssl ca-certificates jq coreutils libcap procps net-tools
        fi
    elif [ -f /etc/os-release ]; then
        . /etc/os-release; OS_TYPE=$ID; INIT_SYSTEM="systemd"; LIBC_TYPE="gnu"
    else echo -e "${RED}无法识别系统类型${PLAIN}"; exit 1; fi
}
if [[ $EUID -ne 0 ]]; then echo -e "${RED}错误：必须使用 root 用户！${PLAIN}"; exit 1; fi
check_os

ARCH=$(uname -m)
case $ARCH in
    x86_64) SB_ARCH="amd64" ;;
    aarch64|arm64) SB_ARCH="arm64" ;;
    *) echo -e "${RED}不支持的架构: $ARCH${PLAIN}"; exit 1 ;;
esac

install_shortcut() {
    cat > "$SHORTCUT_PATH" <<EOF
#!/bin/bash
bash <(curl -sL https://raw.githubusercontent.com/ike666888/Shadowsocks-2022/refs/heads/main/install.sh) \$@
EOF
    chmod +x "$SHORTCUT_PATH"
}

ensure_config_security() {
    mkdir -p "$CONFIG_DIR"
    chmod 700 "$CONFIG_DIR"

    if [[ -f "$CONFIG_FILE" ]]; then
        chmod 600 "$CONFIG_FILE"
        chown root:root "$CONFIG_FILE" 2>/dev/null || true
    fi
}

check_ipv6_status() {
    IPV6_DISABLED="$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null || echo 1)"
    IPV6_GLOBAL_ADDR="$(ip -6 addr show scope global 2>/dev/null | awk '/inet6/{print $2}' | head -n 1 | cut -d'/' -f1)"

    if [[ "$IPV6_DISABLED" != "0" ]]; then
        echo -e "${RED}[IPv6] 系统未开启 IPv6 (net.ipv6.conf.all.disable_ipv6=${IPV6_DISABLED})${PLAIN}"
        return 1
    fi

    if [[ -z "$IPV6_GLOBAL_ADDR" ]]; then
        echo -e "${RED}[IPv6] 未检测到全局 IPv6 地址，无法生成可用节点${PLAIN}"
        return 1
    fi

    echo -e "${GREEN}[IPv6] 可用，检测到地址: ${IPV6_GLOBAL_ADDR}${PLAIN}"
    return 0
}

validate_config_file() {
    if ! jq empty "$CONFIG_FILE" >/dev/null 2>&1; then
        echo -e "${RED}[错误] 配置文件 JSON 无效: $CONFIG_FILE${PLAIN}"
        return 1
    fi

    if command -v "$BIN_PATH" >/dev/null 2>&1; then
        if ! "$BIN_PATH" check -c "$CONFIG_FILE" >/dev/null 2>&1; then
            echo -e "${RED}[错误] sing-box 校验配置失败，请检查参数${PLAIN}"
            return 1
        fi
    fi
    return 0
}

prepare_system() {
    echo -e "${YELLOW}[系统] 环境: $OS_TYPE ($INIT_SYSTEM) / 核心: Sing-box${PLAIN}"
    install_shortcut
    if [[ "$OS_TYPE" =~ (ubuntu|debian|centos|rhel) ]]; then
        if ! command -v jq >/dev/null 2>&1; then
            if [[ "$OS_TYPE" =~ (centos|rhel) ]]; then yum install -y jq; else apt update && apt install -y jq; fi
        fi
        if ! command -v curl >/dev/null 2>&1; then apt install -y curl || yum install -y curl; fi
    fi
    if [[ "$OS_TYPE" != "alpine" ]] && [[ "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)" != "bbr" ]]; then
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        sysctl -p >/dev/null 2>&1
    fi
}

check_port() {
    if command -v ss >/dev/null 2>&1; then ss -tulpn | grep -q ":$1 " && return 1; fi
    if command -v netstat >/dev/null 2>&1; then netstat -tulpn | grep -q ":$1 " && return 1; fi
    return 0
}


validate_port() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] || return 1
    ((port >= 1 && port <= 65535)) || return 1
    return 0
}

warn_reserved_port() {
    local port="$1"
    if ((port < 1024)); then
        echo -e "${YELLOW}[提示] ${port} 属于系统保留端口，请确认是否有冲突${PLAIN}"
    fi
    case "$port" in
        22|53|80|123|443|3306|5432|6379|8080)
            echo -e "${YELLOW}[提示] ${port} 是常见服务端口，请确认不会影响现有业务${PLAIN}" ;;
    esac
}

ask_port() {
    local prompt="$1"
    local default_port="$2"
    local __resultvar="$3"
    local input

    while true; do
        read -p "${prompt} (默认: ${default_port}): " input
        input=${input:-$default_port}

        if ! validate_port "$input"; then
            echo -e "${RED}端口无效，请输入 1-65535 之间的数字${PLAIN}"
            continue
        fi

        if ! check_port "$input"; then
            echo -e "${RED}端口占用${PLAIN}"
            continue
        fi

        warn_reserved_port "$input"
        printf -v "$__resultvar" '%s' "$input"
        return 0
    done
}

install_singbox() {
    if [[ -f "$BIN_PATH" ]]; then
        mkdir -p $CONFIG_DIR
        if [[ ! -f "$CONFIG_FILE" ]]; then
            echo '{"log": {"level": "info", "timestamp": true}, "inbounds": [], "outbounds": [{"type": "direct"}]}' > "$CONFIG_FILE"
        fi
        ensure_config_security
        create_service
        return 0
    fi

    echo -e "${YELLOW}[核心] 获取 Sing-box 最新版本...${PLAIN}"
    RELEASE_JSON=$(curl -fsSL --retry 3 -H "User-Agent: sb-installer" "https://api.github.com/repos/SagerNet/sing-box/releases/latest")
    LATEST_URL=$(echo "$RELEASE_JSON" | jq -r --arg arch "$SB_ARCH" '.assets[] | select(.name | test("linux-" + $arch + "\\.tar\\.gz$")) | .browser_download_url' | head -n 1)
    VERSION=$(echo "$RELEASE_JSON" | jq -r '.tag_name // empty')

    if [[ -z "$LATEST_URL" || -z "$VERSION" ]]; then
        echo -e "${RED}[错误] 无法获取最新版本或下载链接，请检查网络后重试。${PLAIN}"; return 1
    fi

    echo -e "${GREEN}[核心] 正在下载 Sing-box ${VERSION}...${PLAIN}"
    wget -qO /tmp/sing-box.tar.gz "$LATEST_URL"
    if [[ ! -s /tmp/sing-box.tar.gz ]]; then echo -e "${RED}下载失败!${PLAIN}"; return 1; fi

    tar -xzf /tmp/sing-box.tar.gz -C /tmp
    mv /tmp/sing-box-*/sing-box $BIN_PATH
    chmod +x $BIN_PATH
    rm -rf /tmp/sing-box*
    
    mkdir -p $CONFIG_DIR
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo '{"log": {"level": "info", "timestamp": true}, "inbounds": [], "outbounds": [{"type": "direct"}]}' > "$CONFIG_FILE"
    fi
    ensure_config_security
    create_service
}

create_service() {
    if [[ "$INIT_SYSTEM" == "systemd" ]]; then
        cat > /etc/systemd/system/sing-box.service <<EOF
[Unit]
Description=Sing-box Service
After=network.target nss-lookup.target
[Service]
User=root
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
ExecStart=$BIN_PATH run -c $CONFIG_FILE
Restart=on-failure
RestartSec=10
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ReadWritePaths=$CONFIG_DIR
LimitNOFILE=infinity
[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload; systemctl enable sing-box >/dev/null 2>&1
    elif [[ "$INIT_SYSTEM" == "openrc" ]]; then
        cat > /etc/init.d/sing-box <<EOF
#!/sbin/openrc-run
name="sing-box"
command="$BIN_PATH"
command_args="run -c $CONFIG_FILE"
command_background=true
pidfile="/run/sing-box.pid"
depend() { need net; }
EOF
        chmod +x /etc/init.d/sing-box
        rc-update add sing-box default >/dev/null 2>&1
    fi
}

update_config() {
    ensure_config_security
    validate_config_file || return 1
    if [[ "$INIT_SYSTEM" == "systemd" ]]; then systemctl restart sing-box
    else rc-service sing-box restart; fi
}

install_socks5() {
    echo -e "\n${YELLOW}[配置] SOCKS5 参数:${PLAIN}"
    ask_port "端口" "1080" S_PORT
    read -p "用户 (默认: admin): " S_USER; S_USER=${S_USER:-admin}
    read -p "密码 (默认: 随机): " S_PASS; S_PASS=${S_PASS:-$(openssl rand -hex 4)}

    install_singbox || return 1

    tmp=$(mktemp)
    jq 'del(.inbounds[] | select(.tag=="socks-in"))' $CONFIG_FILE > $tmp && mv $tmp $CONFIG_FILE
    
    jq --arg port "$S_PORT" --arg user "$S_USER" --arg pass "$S_PASS" \
       '.inbounds += [{
           "type": "socks",
           "tag": "socks-in",
           "listen": "::",
           "listen_port": ($port|tonumber),
           "users": [{"username": $user, "password": $pass}],
           "udp": true
       }]' $CONFIG_FILE > $tmp && mv $tmp $CONFIG_FILE

    update_config
    view_config
}

configure_ss() {
    EXIST_SS=$(jq '.inbounds[] | select(.tag=="ss-in")' $CONFIG_FILE 2>/dev/null)
    if [[ "$MENU_CHOICE" == "2" && -n "$EXIST_SS" ]]; then
        echo -e "${YELLOW}[检测] 发现已有 SS 配置，是否保留并仅增加 ShadowTLS? [y/n] (默认: y)${PLAIN}"
        read -p "选择: " USE_EXIST
        if [[ "${USE_EXIST:-y}" =~ ^[yY]$ ]]; then
            SS_PORT=$(echo "$EXIST_SS" | jq -r '.listen_port')
            SS_PASS=$(echo "$EXIST_SS" | jq -r '.password')
            SS_METHOD=$(echo "$EXIST_SS" | jq -r '.method')
            SKIP_SS="true"
        fi
    fi

    if [[ "$SKIP_SS" != "true" ]]; then
        echo -e "\n${YELLOW}[配置] 加密协议:${PLAIN}"
        echo -e "  1) 2022-blake3-aes-128-gcm ${GREEN}(推荐)${PLAIN}"
        echo -e "  2) 2022-blake3-aes-256-gcm"
        echo -e "  3) 2022-blake3-chacha20-poly1305"
        echo -e "  4) aes-128-gcm (经典)"
        echo -e "  5) aes-256-gcm (经典)"
        echo -e "  6) chacha20-ietf-poly1305 (经典)"
        read -p "选项 (默认: 1): " M_OPT
        case "${M_OPT:-1}" in
            1) SS_METHOD="2022-blake3-aes-128-gcm";;
            2) SS_METHOD="2022-blake3-aes-256-gcm";;
            3) SS_METHOD="2022-blake3-chacha20-poly1305";;
            4) SS_METHOD="aes-128-gcm";;
            5) SS_METHOD="aes-256-gcm";;
            6) SS_METHOD="chacha20-ietf-poly1305";;
            *) SS_METHOD="2022-blake3-aes-128-gcm";;
        esac
        
        ask_port "SS 端口" "9000" SS_PORT
        SS_PASS=$(openssl rand -base64 16)
    fi

    if [[ "$MENU_CHOICE" == "2" ]]; then
        read -p "伪装域名 (默认: www.microsoft.com): " FAKE_DOMAIN; FAKE_DOMAIN=${FAKE_DOMAIN:-www.microsoft.com}
        TLS_PASS=$(openssl rand -hex 8)
        TLS_PORT=443
    fi
}

install_ss_core() {
    install_singbox || return 1
    tmp=$(mktemp)

    if [[ "$SKIP_SS" != "true" ]]; then
        jq 'del(.inbounds[] | select(.tag=="ss-in" or .tag=="stls-in"))' $CONFIG_FILE > $tmp && mv $tmp $CONFIG_FILE
        LISTEN_ADDR="::"
        [[ "$MENU_CHOICE" == "2" ]] && LISTEN_ADDR="127.0.0.1"
        
        jq --arg port "$SS_PORT" --arg pass "$SS_PASS" --arg method "$SS_METHOD" --arg listen "$LISTEN_ADDR" \
           '.inbounds += [{
               "type": "shadowsocks",
               "tag": "ss-in",
               "listen": $listen,
               "listen_port": ($port|tonumber),
               "method": $method,
               "password": $pass
           }]' $CONFIG_FILE > $tmp && mv $tmp $CONFIG_FILE
    fi

    if [[ "$MENU_CHOICE" == "2" ]]; then
        jq 'del(.inbounds[] | select(.tag=="stls-in"))' $CONFIG_FILE > $tmp && mv $tmp $CONFIG_FILE
        jq --arg port "$TLS_PORT" --arg hand "$FAKE_DOMAIN" --arg pass "$TLS_PASS" \
           '.inbounds += [{
               "type": "shadowtls",
               "tag": "stls-in",
               "listen": "::",
               "listen_port": ($port|tonumber),
               "version": 3,
               "users": [{"password": $pass}],
               "handshake": {"server": $hand, "server_port": 443},
               "detour": "ss-in"
           }]' $CONFIG_FILE > $tmp && mv $tmp $CONFIG_FILE
    fi

    update_config || return 1
    view_config
}

view_config() {
    local mode="${1:-$LINK_VIEW_MODE}"
    if [[ ! -f "$CONFIG_FILE" ]]; then 
        echo -e "${RED}错误：未找到配置文件，请先安装协议！${PLAIN}"
        read -p "按回车键返回主菜单..."
        show_menu
        return
    fi

    PUBLIC_IPV4="$(curl -s4 --max-time 5 ifconfig.me 2>/dev/null)"
    PUBLIC_IPV6="$(curl -s6 --max-time 5 ifconfig.me 2>/dev/null)"

    if [[ -z "$PUBLIC_IPV6" ]]; then
        PUBLIC_IPV6="$(ip -6 addr show scope global 2>/dev/null | awk '/inet6/{print $2}' | head -n 1 | cut -d'/' -f1)"
    fi
    [[ -z "$PUBLIC_IPV4" ]] && PUBLIC_IPV4="$(hostname -I | awk '{print $1}')"

    IP="$PUBLIC_IPV4"
    [[ "$IPV6_PREFERRED" == "true" && -n "$PUBLIC_IPV6" ]] && IP="$PUBLIC_IPV6"

    SHOW_IPV4="true"
    SHOW_IPV6="true"
    case "$mode" in
        ipv4) SHOW_IPV6="false" ;;
        ipv6) SHOW_IPV4="false" ;;
        *) ;;
    esac

    IPV4_HOST=""
    IPV6_HOST=""
    [[ "$SHOW_IPV4" == "true" && -n "$PUBLIC_IPV4" ]] && IPV4_HOST="$PUBLIC_IPV4"
    [[ "$SHOW_IPV6" == "true" && -n "$PUBLIC_IPV6" ]] && IPV6_HOST="[${PUBLIC_IPV6}]"
    
    echo -e "\n${GREEN}========= 当前配置信息 =========${PLAIN}"
    echo -e "链接显示模式: ${YELLOW}${mode}${PLAIN}"
    [[ -n "$PUBLIC_IPV4" ]] && echo -e "IPv4: ${PUBLIC_IPV4}"
    [[ -n "$PUBLIC_IPV6" ]] && echo -e "IPv6: ${PUBLIC_IPV6}"
    
    S_IN=$(jq -c '.inbounds[] | select(.tag=="socks-in")' $CONFIG_FILE 2>/dev/null)
    if [[ -n "$S_IN" ]]; then
        SP=$(echo "$S_IN" | jq -r '.listen_port')
        SU=$(echo "$S_IN" | jq -r '.users[0].username')
        SW=$(echo "$S_IN" | jq -r '.users[0].password')
        echo -e "${YELLOW}--- SOCKS5 ---${PLAIN}"
        echo -e "地址: ${IP}:${SP}"
        echo -e "用户: ${SU}"
        echo -e "密码: ${SW}"
        [[ -n "$IPV4_HOST" ]] && echo -e "IPv4链接: socks5://${SU}:${SW}@${IPV4_HOST}:${SP}"
        [[ -n "$IPV6_HOST" ]] && echo -e "IPv6链接: socks5://${SU}:${SW}@${IPV6_HOST}:${SP}"
    fi

    SS_IN=$(jq -c '.inbounds[] | select(.tag=="ss-in")' $CONFIG_FILE 2>/dev/null)
    if [[ -n "$SS_IN" ]]; then
        SSP=$(echo "$SS_IN" | jq -r '.listen_port')
        SSW=$(echo "$SS_IN" | jq -r '.password')
        SSM=$(echo "$SS_IN" | jq -r '.method')
        USER_INFO=$(echo -n "${SSM}:${SSW}" | base64 -w 0)
        
        STLS_IN=$(jq -c '.inbounds[] | select(.tag=="stls-in")' $CONFIG_FILE 2>/dev/null)
        
        if [[ -n "$STLS_IN" ]]; then
            TP=$(echo "$STLS_IN" | jq -r '.listen_port')
            TW=$(echo "$STLS_IN" | jq -r '.users[0].password')
            TH=$(echo "$STLS_IN" | jq -r '.handshake.server')
            
            echo -e "\n${YELLOW}--- ShadowTLS + SS ---${PLAIN}"
            echo -e "地址: ${IP}:${TP}"
            echo -e "SS密码: ${SSW}"
            echo -e "TLS密码: ${TW}"
            echo -e "域名: ${TH}"
            
            JSON="{\"version\":\"3\",\"host\":\"${TH}\",\"password\":\"${TW}\"}"
            PARAM=$(echo -n "$JSON" | base64 -w 0)

            PLUGIN="shadow-tls;host=${TH};password=${TW}"
            PLUGIN_ENC=$(echo -n "$PLUGIN" | sed 's/;/\%3B/g;s/=/\%3D/g')
            
            if [[ -n "$IPV4_HOST" ]]; then
                LINK4="ss://${USER_INFO}@${IPV4_HOST}:${TP}?shadow-tls=${PARAM}#ShadowTLS-IPv4"
                SIP4="ss://${USER_INFO}@${IPV4_HOST}:${TP}/?plugin=${PLUGIN_ENC}#ShadowTLS-SIP-IPv4"
            fi

            if [[ -n "$IPV6_HOST" ]]; then
                LINK6="ss://${USER_INFO}@${IPV6_HOST}:${TP}?shadow-tls=${PARAM}#ShadowTLS-IPv6"
                SIP6="ss://${USER_INFO}@${IPV6_HOST}:${TP}/?plugin=${PLUGIN_ENC}#ShadowTLS-SIP-IPv6"
            fi

            echo -e "\n${GREEN}[Shadowrocket]${PLAIN}"
            [[ -n "$LINK4" ]] && echo -e "${LINK4}"
            [[ -n "$LINK6" ]] && echo -e "${LINK6}"
            echo -e "\n${GREEN}[v2rayN / NekoBox / SIP]${PLAIN}"
            [[ -n "$SIP4" ]] && echo -e "${SIP4}"
            [[ -n "$SIP6" ]] && echo -e "${SIP6}"
        else
            echo -e "\n${YELLOW}--- Shadowsocks ---${PLAIN}"
            echo -e "地址: ${IP}:${SSP}"
            echo -e "密码: ${SSW}"
            echo -e "加密: ${SSM}"
            [[ -n "$IPV4_HOST" ]] && echo -e "IPv4链接: ss://${USER_INFO}@${IPV4_HOST}:${SSP}#SS-Node-IPv4"
            [[ -n "$IPV6_HOST" ]] && echo -e "IPv6链接: ss://${USER_INFO}@${IPV6_HOST}:${SSP}#SS-Node-IPv6"
            [[ "$IPV6_PREFERRED" == "true" ]] && echo -e "模式: IPv6 + SS2022"
        fi
    fi
    show_footer
}

set_link_view_mode() {
    echo -e "\n${YELLOW}[设置] 链接显示模式${PLAIN}"
    echo " 1) 双栈 (IPv4 + IPv6)"
    echo " 2) 仅 IPv4"
    echo " 3) 仅 IPv6"
    read -p "选项 (默认: 1): " MODE_OPT

    case "${MODE_OPT:-1}" in
        1) LINK_VIEW_MODE="dual" ;;
        2) LINK_VIEW_MODE="ipv4" ;;
        3) LINK_VIEW_MODE="ipv6" ;;
        *) LINK_VIEW_MODE="dual" ;;
    esac

    echo -e "${GREEN}[完成] 当前链接显示模式: ${LINK_VIEW_MODE}${PLAIN}"
}

reset_passwords() {
    install_singbox || return 1
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo -e "${RED}[错误] 未找到配置文件${PLAIN}"
        return 1
    fi

    echo -e "\n${YELLOW}[维护] 重置密码（端口不变）${PLAIN}"
    echo " 1) 重置 Shadowsocks 密码"
    echo " 2) 重置 ShadowTLS 密码"
    echo " 3) 重置 SOCKS5 密码"
    echo " 4) 一键重置全部"
    read -p "选项: " R_OPT

    tmp=$(mktemp)
    local changed="false"

    if [[ "$R_OPT" == "1" || "$R_OPT" == "4" ]]; then
        if jq -e '.inbounds[] | select(.tag=="ss-in")' "$CONFIG_FILE" >/dev/null 2>&1; then
            NEW_SS_PASS=$(openssl rand -base64 16)
            jq --arg pass "$NEW_SS_PASS" '(.inbounds[] | select(.tag=="ss-in").password) = $pass' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
            echo -e "${GREEN}[完成] SS 密码已重置${PLAIN}"
            changed="true"
        else
            echo -e "${YELLOW}[跳过] 未找到 ss-in${PLAIN}"
        fi
    fi

    if [[ "$R_OPT" == "2" || "$R_OPT" == "4" ]]; then
        if jq -e '.inbounds[] | select(.tag=="stls-in")' "$CONFIG_FILE" >/dev/null 2>&1; then
            NEW_TLS_PASS=$(openssl rand -hex 8)
            jq --arg pass "$NEW_TLS_PASS" '(.inbounds[] | select(.tag=="stls-in").users[0].password) = $pass' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
            echo -e "${GREEN}[完成] ShadowTLS 密码已重置${PLAIN}"
            changed="true"
        else
            echo -e "${YELLOW}[跳过] 未找到 stls-in${PLAIN}"
        fi
    fi

    if [[ "$R_OPT" == "3" || "$R_OPT" == "4" ]]; then
        if jq -e '.inbounds[] | select(.tag=="socks-in")' "$CONFIG_FILE" >/dev/null 2>&1; then
            NEW_SOCKS_PASS=$(openssl rand -hex 8)
            jq --arg pass "$NEW_SOCKS_PASS" '(.inbounds[] | select(.tag=="socks-in").users[0].password) = $pass' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
            echo -e "${GREEN}[完成] SOCKS5 密码已重置${PLAIN}"
            changed="true"
        else
            echo -e "${YELLOW}[跳过] 未找到 socks-in${PLAIN}"
        fi
    fi

    rm -f "$tmp"
    if [[ "$changed" == "true" ]]; then
        update_config || return 1
        view_config
    else
        echo -e "${YELLOW}[提示] 没有可更新的配置${PLAIN}"
    fi
}
uninstall() {
    echo -e "${YELLOW}[卸载] 选择:${PLAIN}"
    echo " 1) 卸载 Shadowsocks/TLS"
    echo " 2) 卸载 SOCKS5"
    echo " 3) 卸载 全部 (Sing-box)"
    read -p "选项: " OPT
    tmp=$(mktemp)
    case "$OPT" in
        1) jq 'del(.inbounds[] | select(.tag=="ss-in" or .tag=="stls-in"))' $CONFIG_FILE > $tmp && mv $tmp $CONFIG_FILE; echo -e "${GREEN}SS/TLS 已删除${PLAIN}";;
        2) jq 'del(.inbounds[] | select(.tag=="socks-in"))' $CONFIG_FILE > $tmp && mv $tmp $CONFIG_FILE; echo -e "${GREEN}SOCKS5 已删除${PLAIN}";;
        3) 
            if [[ "$INIT_SYSTEM" == "systemd" ]]; then systemctl stop sing-box && systemctl disable sing-box; rm -f /etc/systemd/system/sing-box.service; systemctl daemon-reload
            else rc-service sing-box stop; rc-update del sing-box; rm -f /etc/init.d/sing-box; fi
            rm -rf $CONFIG_DIR $BIN_PATH $SHORTCUT_PATH
            echo -e "${GREEN}Sing-box 已彻底卸载${PLAIN}"; exit 0 ;;
    esac
    update_config
}

show_footer() {
    echo -e "\n${GREEN}==============================================${PLAIN}"
    echo -e "${YELLOW}   脚本作者: ike${PLAIN}"
    echo -e "${YELLOW}   交流群组: https://t.me/pbox2026${PLAIN}"
    echo -e "${GREEN}==============================================${PLAIN}"
    echo -e "${GREEN}   快捷命令: 输入 ${YELLOW}sb${GREEN} 可随时查看链接${PLAIN}"
    echo -e "${GREEN}==============================================${PLAIN}\n"
}

show_menu() {
    clear
    install_shortcut
    echo -e "${GREEN}==============================================${PLAIN}"
    echo -e "${GREEN}   Shadowsocks + Socks5 一键脚本 (sb)              ${PLAIN}"
    echo -e "${GREEN}==============================================${PLAIN}"
    echo -e "系统: ${YELLOW}$OS_TYPE${PLAIN} | 架构: ${YELLOW}$ARCH${PLAIN}"
    echo -e "----------------------------------------------"
    echo -e "${GREEN}1.${PLAIN} 安装 Shadowsocks 2022"
    echo -e "${GREEN}2.${PLAIN} 安装 Shadowsocks 2022 + ShadowTLS"
    echo -e "${GREEN}3.${PLAIN} 安装 IPv6 + Shadowsocks 2022"
    echo -e "${GREEN}4.${PLAIN} 安装 SOCKS5 代理"
    echo -e "${GREEN}5.${PLAIN} 查看当前配置链接"
    echo -e "${GREEN}6.${PLAIN} 设置链接显示模式 (IPv4/IPv6/双栈)"
    echo -e "${GREEN}7.${PLAIN} 重置密码（端口不变）"
    echo -e "${RED}8.${PLAIN} 卸载服务"
    echo -e "${GREEN}9.${PLAIN} 退出"
    echo -e "----------------------------------------------"
    read -p "请输入选项 [1-9]: " MENU_CHOICE

    case "$MENU_CHOICE" in
        1|2) prepare_system; configure_ss; install_ss_core ;;
        3)
            prepare_system
            if check_ipv6_status; then
                IPV6_PREFERRED="true"
                configure_ss
                install_ss_core
            else
                echo -e "${YELLOW}[IPv6] 请先在服务器开通 IPv6 后重试${PLAIN}"
            fi
            ;;
        4) prepare_system; install_socks5 ;;
        5) prepare_system; view_config ;;
        6) set_link_view_mode ;;
        7) prepare_system; reset_passwords ;;
        8) uninstall ;;
        9) exit 0 ;;
        *) echo "错误选项";;
    esac
}

if [[ "$1" == "view" ]]; then
    view_config "$2"
else
    show_menu
fi
