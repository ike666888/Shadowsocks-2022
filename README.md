# Shadowsocks 2022 + ShadowTLS 一键安装脚本 (Rust版)

这是一个专为**低配置 VPS**（如 0.5G 内存、单核 CPU）设计的轻量级、高性能代理搭建脚本。

它采用 **Rust** 语言编写的 `Shadowsocks-Rust` 和 `ShadowTLS` 核心，在提供目前最强抗封锁能力的同时，将内存占用控制在极致水平（空闲仅需 10MB-20MB）。

## ✨ 核心特性

* **极致轻量**: 采用 Rust 双内核，无 GC 机制，拒绝内存泄露，完美适配 512MB 甚至 256MB 内存机器。
* **抗封锁伪装**: 集成 **ShadowTLS v3**，将流量伪装成正常的 HTTPS (TLS 1.3) 握手，完美通过白名单防火墙检测。
* **高性能**: 默认使用 `2022-blake3-aes-128-gcm` 算法，充分利用服务器 CPU 的 AES-NI 指令集加速。
* **智能优化**:
    * 自动检测并开启 **BBR + FQ** 拥塞控制。
    * 自动检测并创建 **Swap** (虚拟内存)，防止 OOM。
    * 交互式选择是否关闭 **IPv6** (防止断流)。
* **多系统支持**: 完美支持 Debian, Ubuntu, CentOS, AlmaLinux, Rocky Linux。
* **无痕安装**: 脚本执行完毕后支持自毁，不留任何垃圾文件。

## 🖥️ 支持系统

| 系统 | 版本要求 | 架构 |
| :--- | :--- | :--- |
| **Debian** | 10 / 11 / 12 | AMD64 (x86_64) |
| **Ubuntu** | 20.04 / 22.04+ | AMD64 (x86_64) |
| **CentOS** | 7 / 8 / 9 / Stream | AMD64 (x86_64) |
| **Alma/Rocky**| 8 / 9 | AMD64 (x86_64) |

## 🚀 快速安装

请使用 **Root** 用户登录 VPS，执行以下命令：

> ⚠️ **注意**：请将下方命令中的 `你的用户名/仓库名` 替换为你实际的 GitHub 地址。

```bash
bash <(curl -sL https://raw.githubusercontent.com/ike666888/Shadowsocks-2022/refs/heads/main/install.sh)
```
🛠️ 脚本菜单说明脚本运行后将提供以下三种模式：仅安装 Shadowsocks 2022 (普通模式)架构: 客户端 -> SS-Rust (端口 9000)特点: 速度最快，适合对伪装要求不高的环境。安装 Shadowsocks 2022 + ShadowTLS (伪装模式 - 推荐) 🌟架构: 客户端 -> ShadowTLS (端口 443) -> [内网转发] -> SS-Rust特点: 极高抗封锁性。对外表现为正常的 HTTPS 流量，且完全隐藏 SS 服务端，防止主动探测。退出脚本并清理残留文件安装完成后可选择此项，删除脚本本身，保持系统整洁。📱 客户端支持本脚本生成的链接为 SIP002 标准格式，推荐使用以下支持 Shadowsocks 2022 及 ShadowTLS 插件的客户端：平台推荐客户端说明AndroidNekoBox / Sing-box原生支持，直接导入链接即可Windowsv2rayN / NekoRayv2rayN 需 6.0+ 版本iOSShadowrocket / Stash小火箭需更新至最新版macOSSing-box / V2RayU-
