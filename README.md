# 🚀 Shadowsocks 2022 + ShadowTLS V3 一键安装脚本

[![Powered By Rust](https://img.shields.io/badge/Core-Rust-orange?style=flat-square&logo=rust)](https://github.com/shadowsocks/shadowsocks-rust)
[![ShadowTLS V3](https://img.shields.io/badge/Protocol-ShadowTLS%20V3-blue?style=flat-square)](https://github.com/ihciah/shadow-tls)
[![Shell Script](https://img.shields.io/badge/Language-Bash-green?style=flat-square&logo=gnu-bash)](https://github.com/)

这是一个专为**高性能**与**低资源环境**（如 0.5G 内存 VPS）设计的代理搭建脚本。

它能够自动检测系统架构（x86_64 / ARM64），并部署基于 **Rust** 编写的 `Shadowsocks-2022` 和 `ShadowTLS V3`。在提供顶级的抗封锁伪装能力的同时，将内存占用控制在极低水平。

## ✨ 核心特性

* **⚡️ 极致轻量 (Rust)**: 采用 Rust 双内核，无 GC 开销。空闲状态下内存占用极低（约 10MB-20MB），完美适配小内存机器。
* **🛡️ 顶级伪装 (ShadowTLS)**: 集成 ShadowTLS V3，模拟真实的 HTTPS (TLS 1.3) 握手流量，通过大厂域名（如 Microsoft）进行伪装，完美绕过白名单检测。
* **💻 全架构支持**: 自动识别并适配 **AMD64 (x86_64)** 和 **ARM64 (aarch64)** 架构（支持 Oracle ARM、树莓派等）。
* **🚀 性能榨取**: 默认使用 `2022-blake3-aes-128-gcm` 算法，充分利用 CPU 的 AES 硬件指令集加速，跑满千兆带宽。
* **📱 客户端优化**: 安装完成后会自动生成**两组链接**：
    * **通用链接**: 适配 NekoBox, v2rayN, Sing-box。
    * **小火箭专用链接**: 包含 JSON 配置，解决 Shadowrocket 导入插件参数失败的问题。
* **🔧 智能环境配置**:
    * 自动检测并开启 **BBR + FQ** 拥塞控制。
    * 自动判断并创建 **Swap** (虚拟内存) 防止 OOM。
    * 交互式关闭 **IPv6** 防止断流。
    * 自动放行 **Firewalld / UFW** 防火墙端口。

## 🖥️ 支持环境

| 维度 | 支持列表 |
| :--- | :--- |
| **系统** | Debian 10+, Ubuntu 20.04+, CentOS 7+, AlmaLinux, Rocky Linux |
| **架构** | AMD64 (x86_64), ARM64 (aarch64) |
| **内存** | 最低 256MB (建议开启 Swap) |

## 📥 快速安装

使用 **Root** 用户 SSH 登录服务器，执行以下命令：

> ⚠️ **注意**: 请将下方命令中的 `你的用户名/仓库名` 替换为你实际的 GitHub 仓库地址。

```bash
bash <(curl -sL https://raw.githubusercontent.com/ike666888/Shadowsocks-2022/refs/heads/main/install.sh)
```
🛠️ 脚本功能说明
脚本运行后提供以下选项：

1. 仅安装 Shadowsocks 2022
模式: 纯净模式

端口: 9000

说明: 速度最快，开销最小。适合中转使用或对伪装要求不高的环境。

2. 安装 Shadowsocks 2022 + ShadowTLS V3 (✨ 推荐)
模式: 伪装模式

端口: 443

说明: 抗封锁能力最强。

对外暴露 443 端口，伪装成访问 www.microsoft.com。

Shadowsocks 隐藏在内网（127.0.0.1），只有通过 ShadowTLS 握手验证通过的流量才会被转发。

防御主动探测，防御重放攻击。

3. 退出脚本并清理
说明: 安装完成后选择此项，会自动删除脚本文件，保持 VPS 干净整洁。

📱 客户端连接指南
安装完成后，脚本会输出配置信息和链接。

🍎 iOS (Shadowrocket / 小火箭)
请务必复制脚本输出的 [Shadowrocket 专用链接]。

格式特征: 链接中包含 ?shadow-tls=eyJ2ZX... (Base64编码)。

原因: 小火箭目前对标准 SIP002 格式支持不完美，专用链接可自动配置插件参数。

🤖 Android (NekoBox / Sing-box)
请复制 [通用链接]。

推荐客户端: NekoBox for Android (原生支持 ShadowTLS)。

💻 Windows (v2rayN / NekoRay)
请复制 [通用链接]。

v2rayN: 请确保核心已更新，且版本在 6.0 以上。

NekoRay: 推荐使用 Sing-box 核心模式。

❓ 常见问题 (FAQ)
Q: 为什么连不上？

时间同步: SS-2022 协议防止重放攻击，要求服务器与客户端时间误差不能超过 30秒。请检查 VPS 时间。

云安全组: 如果是阿里云、AWS、Oracle 等云厂商，请务必在网页控制台的安全组中放行 TCP/UDP 443 端口。

Q: 为什么选择 AES-128 而不是 AES-256？ 对于翻墙场景，AES-128 安全性已完全足够。在 AES-NI 指令集加持下，128位的性能通常优于 256位，且发热量更低，更适合低配机器。
