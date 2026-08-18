# Hotify Server

自托管的多设备消息与推送服务器：配合 Hotify 客户端（鸿蒙 / 安卓）实现设备间消息、图片与文件互发，离线时自动走系统级推送送达。数据全部保存在你自己的服务器上——单二进制、内嵌数据库、零外部依赖。

> **当前状态：未公开发布。**
> 本仓与镜像暂不公开，公开时间由项目方另行决定；届时 **Gitee 为主要下载口**（国内可达优先）。

## 特性

- **多设备消息同步**：在线走 WebSocket 实时收发，离线自动经系统级推送送达，两路互补不丢消息
- **兼容 bark / gotify 生态**：bark / gotify 生态的现成 App、脚本与通知集成，改个地址直接用——见[下方专章](#兼容-bark--gotify-生态)
- **消息回执**：每条消息返回 id 与调用方关联 id（配合客户端实现发送去重与送达反馈；服务端本身不做幂等，见 [API.md](API.md)）
- **媒体收发**：图片 / 音频 / 视频 / 文件直传；配置 `external_url` 后，bark / gotify 类第三方客户端的通知也能直接显图、附件可点开
- **部署极简**：单二进制零依赖；Docker（amd64 / arm64）与裸机均可；数据全在一个目录，备份即拷贝
- **自动清理**：内嵌存储限额（默认 16GiB，可配），超限自动淘汰最老内容

## 快速开始

### Docker · 一键（推荐）

```bash
git clone <本仓地址> && cd HotifyNEXT-Server-Release
./install.sh          # 检测环境 → 拉镜像 → 生成 compose → 起容器 → 健康检查
```

私有阶段先 `docker login crpi-gi2hyqoir87c0lus.cn-hangzhou.personal.cr.aliyuncs.com`（凭证由项目方发放）。
公开后支持一条命令：`curl -fsSL <Gitee raw>/install.sh | bash`。

### Docker · 手动

```bash
# 起容器（本仓自带 docker-compose.yml，改 environment: 块后执行）
docker compose up -d

# 健康检查（默认无证书 = HTTP；配了 CERT_FILE 后改用 https）
curl http://localhost:8443/ping
# → {"code":200,"message":"pong"}
```

### 二进制（Windows x64）

```bash
# 1. 下载 Release 附件 exe + checksums.txt，校验（对比 checksums.txt 内的哈希）
sha256sum hotify-server-v1.0-L2.1-windows-amd64.exe
# Windows PowerShell 备选：
# Get-FileHash .\hotify-server-v1.0-L2.1-windows-amd64.exe -Algorithm SHA256

# 2. 复制本仓 config.example.yaml 为 config.yaml，改 token（与 exe 同目录）

# 3. 起服
./hotify-server-v1.0-L2.1-windows-amd64.exe

# 4. 健康检查
curl http://localhost:8443/ping
```

完整指南（TLS / 反代 / 持久化）见 **[DEPLOY.md](DEPLOY.md)**。推第一条消息 → 见下方「API 快速参考」与「兼容 bark / gotify 生态」。

## API 快速参考

Base URL 以下记为 `https://your-domain.example`（未配证书时为 `http://<主机>:8443`）。两种凭证：

- **`your_key1`** —— 主凭证，走 `Authorization: Bearer` 头，用于本节及 [API.md](API.md) 的全部 `/api/v1/*` 接口。首台设备注册时生成。
- **`your_device_key`** —— 单台设备的标识，用在 bark / gotify 兼容入口（见下一节）。

### 推一条消息（主接口）

```bash
curl -X POST https://your-domain.example/api/v1/push \
  -H 'Authorization: Bearer your_key1' \
  -H 'Content-Type: application/json' \
  -d '{"title":"服务器告警","body":"CPU 95%","url":"https://example.com/dashboard"}'
```

- `title` / `body` 至少填一个；`url`（点击跳转）、`image_url`（通知大图）可选
- 返回里的 `hlc` 是这条消息的 id（字符串），可用于后续删除、翻页
- 带图片 / 文件附件：同一接口改用 `multipart/form-data`，见 [API.md](API.md)
- ⚠️ `code:200` 不等于推送成功——`message` 含 `saved but push failed` 表示消息已保存但离线推送失败，脚本请检查 `message` 字段

### 拉历史 / 探活

```bash
# 最近消息（?limit=1..200；?before=<消息id> 向更早翻页）
curl -H 'Authorization: Bearer your_key1' \
  'https://your-domain.example/api/v1/messages?limit=50'

# 版本与存活探活（公开，无需凭证）
curl https://your-domain.example/api/v1/info
```

### 不想写代码？

下一节告诉你怎么让现成的 bark / gotify 工具直接往这里推。

完整接口（设备注册与管理、媒体上传与取回、WebSocket 实时通道、备份、错误码表）见 **[API.md](API.md)**。

## 兼容 bark / gotify 生态

Hotify 在端点级实现了 bark 与 gotify 两套推送协议。这意味着：**这两个生态里现成的 App、脚本和通知集成，把地址换成你的 Hotify 服务器就能用，一行代码不用改。**

能直接用的东西：

- **发送侧**：SmsForwarder（安卓短信/通知转发）、Home Assistant、Uptime Kuma 等监控面板，以及任何支持 bark 或 gotify 的通知脚本 / 集成
- **接收侧**：iPhone 上的 **Bark App** 可直接添加本服务收推送；**gotify 客户端**（Android / 桌面 / Web）可直连实时收消息、翻历史

### bark 风格：key 在路径里

```bash
# 定向推给某台设备
curl "https://your-domain.example/your_device_key/标题/正文"

# 参数也可以全放 query（POST/GET 均可）
curl "https://your-domain.example/your_device_key?title=标题&body=正文&url=https://example.com"

# key 换成 your_key1 → 广播到全部设备
curl "https://your-domain.example/your_key1/标题/正文"
```

- 路径最多四段：`/<key>`、`/<key>/<正文>`、`/<key>/<标题>/<正文>`、`/<key>/<标题>/<副标题>/<正文>`
- 常用 bark 参数照常支持：`url`（点击跳转）、`sound`、`group`（分组）、`call=1`（来电样式）等；未识别的字段不会丢弃，原样保留
- 返回 `{"code":200,"message":"success",…}`；key 不存在返回 400，不会入库

### gotify 风格：token 在参数或 header

```bash
curl -X POST "https://your-domain.example/message?token=your_device_key" \
  -H 'Content-Type: application/json' \
  -d '{"title":"标题","message":"正文","priority":5}'
# → 返回 gotify 原生格式的消息对象，按 gotify 响应解析的现有脚本无需改动
```

- 也支持 `X-Gotify-Key: your_device_key` 头或 `Authorization: Bearer your_device_key`
- `message` 必填；gotify 语义是「应用推送」——一条消息广播到你的全部设备；token 换成 `your_key1` 则匿名广播

### 广播全部设备（显式入口）

```bash
curl -X POST "https://your-domain.example/broadcast/your_device_key/标题/正文"       # bark 形（key 在路径）
curl -X POST "https://your-domain.example/broadcast?token=your_device_key" \
  -H 'Content-Type: application/json' -d '{"title":"标题","message":"正文"}'        # gotify 形（token 在 query/header）
```

### 用现成客户端收消息

- **Bark App（iPhone）**：App 内添加服务器，地址填 `https://your-domain.example` 即可
- **gotify for Android**：服务器地址同上，用户名任意，密码填 `your_key1`
- **gotify 桌面客户端**：浏览器打开 `https://your-domain.example/gotify/your_key1`，把返回的设备 key 粘进客户端的 token 栏

### 凭证从哪来

`your_key1` 在首台设备注册时生成；`your_device_key` 是每台设备的标识。两者都可在 Hotify 客户端的设备信息中查看；纯脚本用法（不经 Hotify 客户端）见 [API.md](API.md) 的「设备注册」。

> 提示：媒体消息要在第三方 App 的通知里直接显示图片、附件可点开，需配置 `external_url`，见 [DEPLOY.md](DEPLOY.md)。

## 文档

| 文件 | 内容 |
|---|---|
| [DEPLOY.md](DEPLOY.md) | 部署指南（一键 / Docker / 二进制，自包含） |
| [API.md](API.md) | 完整 API 文档（端点 / 鉴权 / 媒体上传 / 错误码） |
| `install.sh` | Docker 一键部署脚本 |
| `docker-compose.yml` | Compose 配置（全部可配项带注释） |
| `config.example.yaml` | 配置模板（逐项注释） |

## 版本

| 版本 | 日期 | 说明 |
|---|---|---|
| v1.0-L2.1 | 2026-08-18 | 消息回执；第三方客户端通知显图；大附件（单次上传上限默认 4GiB，含全部附件） |

## 许可与源码

本仓未附许可证（保留所有权利）。源代码暂不公开，后续将以开源许可证发布，届时在此公告。
