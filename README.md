# 🚀 Shadowsocks + Socks5 全能一键安装脚本 (v6.2)

> **极速、安全、抗检测。** > 集成 Shadowsocks 2022 (Rust)、ShadowTLS (v3) 和 Gost (SOCKS5) 的全能代理搭建脚本。

![Build Status](https://img.shields.io/badge/Build-Passing-brightgreen)
![Version](https://img.shields.io/badge/Version-v6.2-blue)
![License](https://img.shields.io/badge/License-GPLv3-orange)

## ✨ 核心特性

* **🛡️ 极致安全**：所有服务均以 `User=nobody` (非 Root) 身份运行，利用 Linux `AmbientCapabilities` 监听特权端口。即使被黑，系统依然安全。
* **⚡ 性能强悍**：基于 Rust 编写的 Shadowsocks 核心与 Gost 隧道，内存占用极低（512MB 内存小鸡也能跑满带宽），默认开启 BBR 加速。
* **🔌 协议全覆盖**：
    * **Shadowsocks 2022 (SIP022)**：抗检测、高性能（支持单端口多用户）。
    * **ShadowTLS v3**：伪装成正常的 HTTPS 流量，过墙神器。
    * **SOCKS5 (Gost)**：支持 UDP 转发，适合游戏/语音通话。
    * **Classic AEAD**：兼容老旧设备（OpenWRT/旧手机）。
* **🌍 跨平台**：自动适配 `x86_64` (AMD/Intel) 和 `aarch64` (ARM64) 架构。

## 📥 安装命令

使用 Root 用户登录服务器，执行以下命令：

```bash
bash <(curl -sL https://raw.githubusercontent.com/ike666888/Shadowsocks-2022/refs/heads/main/install.sh)
```
## 🛠️ 功能菜单

脚本运行后，提供以下安装选项：

1. **安装 Shadowsocks 2022 (推荐)**
   纯净的 SS 协议，适合绝大多数环境。

2. **安装 Shadowsocks 2022 + ShadowTLS (高阶)**
   在 SS 外层包裹 TLS 伪装（默认伪装成 Microsoft），适合高墙敏感时期。

3. **安装 SOCKS5 代理 (Gost v2.12.0)**
   通用的 SOCKS5 协议，支持 UDP，适合 Telegram、游戏加速。

4. **卸载服务**
   干净卸载，不留垃圾文件。

## 🔐 加密协议说明 (重要)

本脚本支持“新老两代”协议，**请务必在客户端选择匹配的选项，严禁混用！**

| 选项编号 | 协议类型 | 客户端配置名称 | 适用场景 | 备注 |
| :--- | :--- | :--- | :--- | :--- |
| **1 (推荐)** | **SS-2022** | `2022-blake3-aes-128-gcm` | 主流手机/PC | 极速，抗检测强 |
| **2** | **SS-2022** | `2022-blake3-aes-256-gcm` | 高安全需求 | CPU占用稍高 |
| **3** | **SS-2022** | `2022-blake3-chacha20...` | 移动设备 | 适合无AES指令集的CPU |
| **4** | **Classic** | `aes-128-gcm` | 老旧路由器/旧手机 | 兼容性最好 |
| **5** | **Classic** | `aes-256-gcm` | 老旧设备 | 经典加密 |

> **⚠️ 注意：**
> * 如果你在脚本选了 **1**，客户端必须选 `2022-blake3-aes-128-gcm`。
> * 如果你在脚本选了 **4**，客户端必须选 `aes-128-gcm`。
> * **选错会导致无法连接！**

## 📱 客户端避坑指南

为了保证连接稳定，请检查以下设置：

### 1. 时间必须同步 ⏰
* **Shadowsocks 2022** 对时间要求极严（误差不能超过 ±30秒）。
* 请确保你的手机/电脑时间是自动同步的。
* 服务器端脚本已自动配置 Chrony 校时。

### 2. 关闭 Multiplex (多路复用) 🚫
* **现象**：能连上但速度慢，或者频繁断流。
* **解决**：在小火箭/v2rayN 设置中，**关闭** `Multiplex` (Mux) 选项。SS-2022 协议不需要这个功能。

### 3. UDP 转发 (游戏/语音) 🎮
* 本脚本搭建的 SOCKS5 和 SS 均完美支持 UDP。
* **关键点**：请务必在**阿里云/腾讯云/AWS** 的网页控制台“安全组”中，**同时放行 TCP 和 UDP 协议**的端口。

## 📂 文件路径与管理

* **配置文件**：`/etc/ss-config.json`
* **服务管理**：
  * 查看状态：`systemctl status ss-rust`
  * 重启服务：`systemctl restart ss-rust`
  * SOCKS5服务：`systemctl status gost`

## ⚖️ 免责声明

本脚本仅供学习交流与网络技术研究使用。请勿用于任何违反当地法律法规的用途。使用本脚本产生的任何后果由使用者自行承担。
