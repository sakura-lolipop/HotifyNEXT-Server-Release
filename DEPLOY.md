# 部署指南（一键 / Docker / binary）

Hotify Server 是单二进制 Go 服务，零外部依赖（数据库/缓存全内嵌）。部署路线任选：

| 路线 | 适合 | 产物 |
|---|---|---|
| **A. Docker**（推荐，可一键） | Linux 服务器 / NAS / 群晖 | 容器镜像（amd64 + arm64） |
| **B. binary** | Windows 裸机 / 不使用 Docker / Linux 无容器环境 | Release 附件单文件二进制（6 平台：windows/linux/darwin × amd64/arm64 + linux-armv7；Linux 裸跑常驻的 systemd 模板见 [aideploy.md](aideploy.md) §3.4） |

> 离线推送分两路：华为系设备经项目方公共推送云函数中转至华为推送服务；iPhone（Bark App）由服务器直连 Apple APNs 送达（经 Apple，不经项目方）。纯在线使用（WebSocket 实时收发）不经过任何第三方。

> 🤖 在用 AI 助手（Claude Code / Codex 等）？让它读 [aideploy.md](aideploy.md)——它按 runbook 问你几个问题（部署到哪 / Docker 还是二进制 / 有没有反代），与你确认方案后代为执行部署与验证（浏览器初始化、密码输入等环节仍需你操作）；本机、远程 SSH、Docker 与二进制均支持。

---

## 路线 A：Docker

### 方式一：一键脚本

```bash
curl -fsSL https://gitee.com/sakura-lolipop/HotifyNEXT-Server-Release/raw/main/install.sh | bash
# 或 clone 本仓后执行 ./install.sh
```

脚本依次执行五步：环境检测（docker / curl / 架构）→ 拉取镜像 → 生成 `docker-compose.yml`（**已存在则不覆盖**，提示手动升级）→ 启动容器 → 健康检查并打印下一步。重复执行 = 升级（重新拉取镜像 + `up -d`），不影响数据卷。`--uninstall` 只打印卸载指令（不删数据）。

### 方式二：手动

本仓根目录已备 `docker-compose.yml`：

```bash
docker compose up -d
docker compose logs -f                          # 看日志确认启动
curl http://localhost:8443/ping                 # 健康检查 → {"code":200,"message":"pong"}
```

> 默认（未配 `CERT_FILE`/`cert_file`）在主端口以 HTTP 启动；配置证书后改用 `https://`。

配置**全部走 compose 的 `environment:` 块**（12-factor，不用 config.yaml 也可启动）：

```yaml
environment:
  # —— 全部 opt-in，按需取消注释改值（不配任何项也可启动：离线推送开箱即用）——
  # CLOUD_FUNCTION_TOKEN: "your-own-token"        # 自建票端点开了 TICKET_AUTH_TOKEN 才填；默认空=匿名开放
  # EXTERNAL_URL: "https://your-domain.example"   # server 对外地址（反代/隧道后必须配置，见下）
```

> ⚠️ 不用 `.env` 文件或 `env_file:`——群晖/Portainer 等 GUI 界面不读取。直接编辑 `environment:` 块。

**两个关键配置**：

- `CLOUD_FUNCTION_TOKEN`：票端点 Bearer。v1.2（CF2 票据化直推）起**默认空 = 不发头**，公共票端点匿名开放——离线推送开箱即用，无需配置；仅自建票端点且开了 `TICKET_AUTH_TOKEN` 时填同一值。纯在线使用（WebSocket 实时收发）则完全不涉及。
- `EXTERNAL_URL`：server 对外可达地址（含 scheme）。Docker/反代后 server 不知道自己的公网地址；不配则媒体消息在 bark/gotify 等第三方客户端通知里不显示图片、附件不可点击（原生 Hotify 客户端不受影响）。反向代理部署通常必须配置。

### 数据持久化

全部数据存于 named volume `hotify-data` 一个卷中，`docker compose down` 数据不丢失（`down -v` 才删，慎用）：

| 路径 | 内容 |
|---|---|
| `/data/hotify.db` | 内嵌数据库（消息/设备/凭据） |
| `/data/blobs/` | 媒体文件（图片/音频/文件） |
| `/data/hotify.log` | 运行日志 |
| `/data/hooks/` | **webhook 插件目录**（一个插件一个 yaml，挂载 `./hooks:/data/hooks`；装=放文件+设 `HOOKS_<ID>_SECRET`+重启。现成插件与规则见 [HotifyNEXT-Plugins](https://gitee.com/sakura-lolipop/hotifynext-plugins)） |
| `/data/cli-token` | 内部管理文件（勿删） |

若改用 bind mount（`-v ./data:/data`），先 `chown -R 10001:10001 ./data`（容器内以 uid 10001 运行）。

> 卷名已在 compose 中固定（`name: hotify-data`），不随部署目录变，备份/迁移直接引用。更早的测试部署卷名带 `<目录名>_hotify-data` 前缀：升级 compose 后首启会新建空的 `hotify-data` 卷，旧测试数据仍在旧卷（`docker volume ls` 可见），可弃或自行迁移。

> 本 compose 为**单机单实例**设计（容器名/端口/卷名固定）：同机原样再起会因容器名冲突中止，不伤在跑实例。同机多实例（多用户各一套独立数据）：复制 compose 后三处同改——`container_name`、宿主端口、卷名（service 挂载 + 顶层 `volumes:` 键 + `name:`）——漏改卷名的第二实例会被 bbolt 文件锁拒绝（起不来，不会互踩数据）。

### 备份 / 恢复 / 迁移

数据全在卷 `hotify-data` 里。备份（宿主机任意目录执行）：

```bash
docker run --rm -v hotify-data:/data -v "$(pwd)":/backup alpine \
  tar czf /backup/hotify-backup-$(date +%F).tar.gz -C /data .
```

恢复到新机：先 `docker compose up -d` 执行一次以创建卷，再 `docker compose down`，确认备份文件无误后反向解包：

```bash
docker run --rm -v hotify-data:/data -v "$(pwd)":/backup alpine \
  sh -c "rm -rf /data/* && tar xzf /backup/hotify-backup-<日期>.tar.gz -C /data"
```

再 `docker compose up -d` 即完成迁移。binary 路线：拷贝 exe 所在的整个目录即完成备份。

### TLS（在容器中启用 HTTPS）

两种方式：

- **直接 HTTPS**：证书挂只读进容器 + `CERT_FILE`/`KEY_FILE` 指过去。
- **反代终结 TLS**（Caddy/nginx 管 TLS，容器跑 plain HTTP）：不设 `CERT_FILE`/`KEY_FILE`，设 `TRUSTED_PROXIES: "172.16.0.0/12,127.0.0.1"` 让 server 正确解析 `X-Forwarded-For`。⚠️ nginx 默认**不转发 WebSocket**——实时通道（`/api/v1/stream`）会静默断开，需加：

  ```nginx
  location / {
      proxy_pass http://127.0.0.1:8443;
      proxy_http_version 1.1;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection "upgrade";
      proxy_set_header Host $host;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      client_max_body_size 0;   # nginx 默认 1M 会挡媒体上传/备份（不限制；或按需设上限）
  }
  ```

  （Caddy 的 `reverse_proxy` 原生支持 WebSocket，无需额外配置。）

### 国内拉取

镜像托管在阿里云 ACR（国内直连），无需额外加速配置。

### 镜像 tag 说明

- `vX.Y`：与 Release 同名的稳定版本——compose / install.sh 默认钉此 tag，升级 = 显式改一行 tag（这就是你的「确认升级」动作）
- `latest`：始终指向最新版，`docker compose pull` 会隐式升级到未预览的版本，**不建议**生产默认使用
- 海外服务器可改拉 `ghcr.io/sakura-lolipop/hotify-server`（同 tag）

---

## 路线 B：binary（Windows x64）

```bash
# 1. 从 Release 下载 exe（hotify-server-<版本>-windows-amd64.exe，版本以 Releases 页最新为准）
#    + checksums.txt，校验（对比 checksums.txt 内的哈希）
sha256sum hotify-server-<版本>-windows-amd64.exe
# Windows PowerShell 备选：
# Get-FileHash .\hotify-server-<版本>-windows-amd64.exe -Algorithm SHA256

# 2. 同目录放配置：复制本仓 config.example.yaml 为 config.yaml
#    （默认值即可启动，离线推送开箱即用；按需调整见文件内注释）

# 3. 启动服务 + 健康检查
./hotify-server-<版本>-windows-amd64.exe
curl http://localhost:8443/ping
```

- 同目录生成 `hotify.db` / `blobs/` / `hotify.log` / `cli-token`——整个目录即全部状态，备份/迁移 = 拷贝该目录。
- 配置字段全集见 `config.example.yaml` 内注释；环境变量可覆盖同名字段（直接用字段名的大写形式，如 `HTTPS_PORT`；`store.path` / `store.type` 除外——只走 config 文件/默认值）。
- 无证书时在主端口以 HTTP 启动（配了 `tls.cert_file` 即 HTTPS）。
- **前台运行，关闭窗口即停止。**需要常驻可用 [NSSM](https://nssm.cc/) 注册为 Windows 服务，或用任务计划程序设为开机启动。

---

## 常用运维

```bash
docker compose up -d         # 启动 / 修改 environment: 后重建生效
docker compose logs -f       # 查看日志
docker compose restart       # 仅重启进程；不会应用 compose 文件的新改动（改 env 用上行）
docker compose down          # 停（数据留存）
curl http://localhost:8443/api/v1/info   # 版本/构建信息（排错时先查看此接口）
# 升级：改 docker-compose.yml 里 image tag → docker compose up -d（数据在卷里不受影响）
```

## 接入

服务器启动后有三种接入方式，按需选用：

- **Hotify 客户端**（鸿蒙）：客户端「设置 → 服务器」填入服务器地址，首个设备注册时自动完成凭证配置（添加更多设备见 App 内引导）。客户端文档随源码开源后发布。
- **自写脚本 / 程序**：走 `POST /api/v1/push` 等原生接口，见 [API.md](API.md)。
- **现成的 bark / gotify 工具**（SmsForwarder、Home Assistant、Bark App、gotify App 等）：只需修改推送地址即可使用，见 [README](README.md) 的「兼容 bark / gotify 生态」。各平台客户端下载：**安卓** Gotify App（[官方 APK](https://github.com/gotify/android/releases)，密码填 key1）；**Windows PC** GotifyClient（[gotify_pc 发行页](https://github.com/sakura-lolipop/gotify_pc/releases)，密码 key1）；**iPhone** App Store 搜索 **Bark**（添加服务器即自动注册）。
