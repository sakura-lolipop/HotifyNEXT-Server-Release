# Hotify Server

自托管的多设备消息与推送服务器：配合 Hotify 客户端（鸿蒙 / 安卓）实现设备间消息、图片与文件互发，离线时自动走系统级推送送达。数据全部保存在你自己的服务器上——单二进制、内嵌数据库、零外部依赖。

> **当前状态：未公开发布。**
> 本仓与镜像暂不公开，公开时间由项目方另行决定；届时 **Gitee 为主要下载口**（国内可达优先）。

## 特性

- **多设备消息同步**：在线走 WebSocket 实时收发，离线自动经系统级推送送达，两路互补不丢消息
- **发送去重与送达回执**：弱网重发不产生重复消息，发送结果如实反馈
- **媒体收发**：图片 / 音频 / 文件直传；配置 `external_url` 后，bark / gotify 类第三方客户端的通知也能直接显图、附件可点开
- **协议兼容**：兼容 bark / gotify 推送协议，现有工具链无需改造即可接入
- **部署极简**：单二进制零依赖；Docker（amd64 / arm64）与裸机均可；数据全在一个目录，备份即拷贝
- **自动清理**：内嵌存储限额（默认 16GiB，可配），超限自动淘汰最老内容

## 快速开始

### Docker（推荐）

```bash
# 1. 起容器（本仓自带 docker-compose.yml，改 environment: 块后执行）
docker compose up -d

# 2. 健康检查
curl -k https://localhost:8443/ping
# → {"code":200,"message":"pong"}
```

私有阶段拉镜像前先 `docker login`（凭证由项目方发放）。

### 二进制（Windows x64）

```bash
# 1. 下载 Release 附件 exe + checksums.txt，校验
sha256sum -c checksums.txt

# 2. 复制 config.example.yaml 为 config.yaml，改 token（同目录）

# 3. 起服
./hotify-server-v1.0-L2.1-windows-amd64.exe
```

完整指南（TLS / 反代 / 持久化 / 国内拉取加速）见 **[DEPLOY.md](DEPLOY.md)**。

## 文档

| 文件 | 内容 |
|---|---|
| [DEPLOY.md](DEPLOY.md) | 部署指南（Docker + 二进制两路，自包含） |
| `docker-compose.yml` | Compose 配置（全部可配项带注释） |
| `config.example.yaml` | 配置模板（逐项注释） |

## 版本

| 版本 | 日期 | 说明 |
|---|---|---|
| v1.0-L2.1 | 2026-08-18 | 发送去重；第三方客户端通知显图；大附件（单文件默认上限 4GiB） |

## 许可与源码

本仓未附许可证（保留所有权利）。源代码暂不公开，后续将以开源许可证发布，届时在此公告。
