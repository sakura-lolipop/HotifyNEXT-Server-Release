# Hotify Server · 发行仓

Hotify 自托管推送服务器的**发行物仓库**：二进制、容器镜像与部署指南。

Hotify = 多设备隐私推送（鸿蒙 NEXT + 安卓客户端）的自部署后端：消息/媒体收发、多设备同步、离线推送。数据全部留在你自己的服务器上。

> **当前状态：私有阶段（未公开发布）**
>
> 本仓、源码与容器镜像暂不公开；公开时间由项目方另行决定。届时 **Gitee 为主要下载口**（终端用户国内可达优先）。

## 下载

| 渠道 | 地址 | 阶段 |
|---|---|---|
| GitHub Release | 本仓 Releases 页 | 私有（需协作权限） |
| Gitee Release | Gitee 同名仓 Releases | 私有 → 公开后主口 |
| 容器镜像 | `crpi-gi2hyqoir87c0lus.cn-hangzhou.personal.cr.aliyuncs.com/sakura-lolipop/hotify-server`（阿里云 ACR，国内） | 私有（pull 需 docker login）→ 公开后匿名可拉 |

每版附件附 `checksums.txt`（SHA256），下载后务必校验。

## 版本表

| 版本 | 日期 | 主题 |
|---|---|---|
| v1.0-L2.1 | 2026-08-18 | 消息去重回显（client_msg_id）、媒体通知跨生态显图（external_url + media 鉴权）、大附件限额（单附件默认 4GiB / 空间默认 16GiB） |

## 快速开始

```bash
# Docker（推荐）
docker compose up -d
curl -k https://localhost:8443/ping   # → {"code":200,"message":"pong"}

# 或 binary（当前仅 Windows amd64；Linux 走 Docker）
./hotify-server-v1.0-L2.1-windows-amd64.exe   # 同目录放 config.yaml（见 config.example.yaml）
```

完整部署指南：[DEPLOY.md](DEPLOY.md)

## 仓布局

| 文件 | 用途 |
|---|---|
| `DEPLOY.md` | 部署指南（Docker + binary 两路，自包含） |
| `docker-compose.yml` | 发行版 compose（镜像拉取，非本地构建） |
| `config.example.yaml` | 配置模板（binary 路线用） |

## 许可与源码

本仓未附许可证（保留所有权利）。源代码暂不公开，后续将以开源许可证发布，届时在源码仓与本项目页同步公告。
