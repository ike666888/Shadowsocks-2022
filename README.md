# 🚀 Shadowsocks-2022 一键安装脚本

> 支持 **SS2022**、**SS2022 + ShadowTLS**、**IPv6 + SS2022**、**SOCKS5** 的交互式安装脚本（基于 sing-box）。

![Build Status](https://img.shields.io/badge/Build-Passing-brightgreen)
![Version](https://img.shields.io/badge/Version-v6.3-blue)
![License](https://img.shields.io/badge/License-GPLv3-orange)

## ✨ 核心特性

- **交互式菜单**：按需安装 SS2022 / ShadowTLS / IPv6+SS2022 / SOCKS5，并支持密码重置与链接显示模式切换。
- **IPv6 自动检查**：安装 IPv6+SS2022 前自动检测：
  - 系统是否开启 IPv6（`net.ipv6.conf.all.disable_ipv6=0`）
  - 是否存在全局 IPv6 地址
- **双栈链接展示**：查看配置时可同时输出 IPv4/IPv6 链接，IPv6 链接自动加 `[]`。
- **配置安全增强**：
  - 自动收敛配置目录权限：`/etc/sing-box` 为 `700`
  - 配置文件权限为 `600`（仅 root 可读写）
  - 写入后自动校验 JSON 与 `sing-box check`
- **服务安全加固（systemd）**：启用 `NoNewPrivileges`、`PrivateTmp`、`ProtectSystem`、`ProtectHome` 等限制。
- **多加密方式**：支持 SS2022 与经典 AEAD，方便新旧客户端兼容。

## 📥 安装命令

请使用 root 用户执行：

```bash
bash <(curl -sL https://raw.githubusercontent.com/ike666888/Shadowsocks-2022/refs/heads/main/install.sh)
```

Alpine 可先补齐基础依赖：

```bash
if [ -f /etc/alpine-release ]; then apk update && apk add bash curl; fi && bash <(curl -sL https://raw.githubusercontent.com/ike666888/Shadowsocks-2022/refs/heads/main/install.sh)
```

## 🛠️ 功能菜单

当前菜单如下：

1. 安装 Shadowsocks 2022
2. 安装 Shadowsocks 2022 + ShadowTLS
3. 安装 IPv6 + Shadowsocks 2022（自动检查 IPv6）
4. 安装 SOCKS5 代理
5. 查看当前配置链接
6. 设置链接显示模式（双栈 / 仅 IPv4 / 仅 IPv6）
7. 重置密码（端口不变）
8. 卸载服务
9. 退出

### 快捷命令

安装后可直接使用：

```bash
sb
sb view
sb view ipv4
sb view ipv6
```


### 端口输入校验

- 所有端口输入均校验为 **1-65535** 的数字。
- 输入常见业务端口（如 22/80/443/3306）或系统保留端口（<1024）会给出提示。
- 若端口已占用会要求重新输入。

## 🔐 加密协议说明

| 选项编号 | 协议类型 | 客户端配置名称 |
| :--- | :--- | :--- |
| 1（推荐） | SS-2022 | `2022-blake3-aes-128-gcm` |
| 2 | SS-2022 | `2022-blake3-aes-256-gcm` |
| 3 | SS-2022 | `2022-blake3-chacha20-poly1305` |
| 4 | Classic AEAD | `aes-128-gcm` |
| 5 | Classic AEAD | `aes-256-gcm` |
| 6 | Classic AEAD | `chacha20-ietf-poly1305` |

> ⚠️ 客户端加密方式必须与服务端一致，否则无法连接。

## 🌐 IPv6 模式说明

当你选择“**安装 IPv6 + Shadowsocks 2022**”时，脚本会先检查：

- 内核是否启用了 IPv6
- 服务器是否获取到了全局 IPv6 地址

若检查失败，脚本会提示先开通 IPv6，不会盲目写入不可用配置。

启用成功后，在“查看当前配置链接”中会展示 IPv4/IPv6 两套链接（若可用），其中 IPv6 地址会自动使用 `[]` 包裹，避免 URI 解析错误。

## 📂 文件路径与管理

- 配置目录：`/etc/sing-box`
- 配置文件：`/etc/sing-box/config.json`
- 二进制：`/usr/local/bin/sing-box`
- 快捷命令：`/usr/local/bin/sb`

常用管理命令（systemd）：

```bash
systemctl status sing-box
systemctl restart sing-box
systemctl stop sing-box
```

## ✅ 配置安全建议（额外）

除了脚本内置加固，建议你再检查：

- 云厂商安全组仅放行你实际使用的端口（TCP/UDP 按需）。
- 不要复用旧密码，定期重置 SS/ShadowTLS 密码。
- 尽量避免使用过于显眼的伪装域名，并定期更换。
- 若无 IPv6 需求，优先走 IPv4；有 IPv6 需求时确认客户端支持 IPv6 节点。

## 🔧 维护功能说明

- 可在菜单中切换“链接显示模式”：双栈 / 仅 IPv4 / 仅 IPv6，便于复制。
- 支持“重置密码（端口不变）”，可单独重置 SS / ShadowTLS / SOCKS5，也可一键重置全部。
- 重置后会自动重启服务并重新展示最新链接。

## ⚖️ 免责声明

本脚本仅供学习交流与网络技术研究使用。请勿用于任何违反当地法律法规的用途。使用本脚本产生的任何后果由使用者自行承担。
