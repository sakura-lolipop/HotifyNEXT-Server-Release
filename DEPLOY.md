# 部署指南（一键 / Docker / binary）

Hotify Server 是单二进制 Go 服务，零外部依赖（数据库/缓存全内嵌）。部署路线任选：

| 路线 | 适合 | 产物 |
|---|---|---|
| **A. Docker**（推荐，可一键） | Linux 服务器 / NAS / 群晖 | 容器镜像（amd64 + arm64） |
| **B. binary** | Windows 裸机 / 不想装 Docker | Release 附件 exe（当前仅 Windows amd64；Linux 请走 Docker） |

> 离线推送经项目方提供的推送云函数中转（消息体经其转发后送达华为推送服务）；纯在线使用（WebSocket 实时收发）不经过任何第三方。

---

## 路线 A：Docker

### 方式一：一键脚本

```bash
curl -fsSL https://gitee.com/sakura-lolipop/HotifyNEXT-Server-Release/raw/main/install.sh | bash
# 或 clone 本仓后执行 ./install.sh
```

脚本做五件事：环境检测（docker / curl / 架构）→ 拉镜像 → 生成 `docker-compose.yml`（**已存在则不覆盖**，提示手动升级）→ 起容器 → 健康检查并打印下一步。重复执行 = 升级（重拉镜像 + `up -d`），不动数据卷。`--uninstall` 只打印卸载指令（不删数据）。

### 方式二：手动

本仓根目录已备 `docker-compose.yml`：

```bash
docker compose up -d
docker compose logs -f                          # 看日志确认启动
curl http://localhost:8443/ping                 # 健康检查 → {"code":200,"message":"pong"}
```

> 默认（未配 `CERT_FILE`/`cert_file`）以 HTTP 起在主端口；配置证书后改用 `https://`。

配置**全部走 compose 的 `environment:` 块**（12-factor，不用 config.yaml 也能起）：

```yaml
environment:
  # —— 全部 opt-in，按需取消注释改值（不配任何项也能起：纯在线收发）——
  # CLOUD_FUNCTION_TOKEN: "changeme"              # 推送云函数口令，见下
  # EXTERNAL_URL: "https://your-domain.example"   # server 对外地址（反代/隧道后必配，见下
```

> ⚠️ 不用 `.env` 文件或 `env_file:`——群晖/Portainer 等 GUI 不认。直接编辑 `environment:` 块。

**两个关键配置**：

- `CLOUD_FUNCTION_TOKEN`：华为推送云函数的共享口令（仅作共享口令校验，不是安全边界）。**要用离线推送就必须配**，且与云函数侧 `AUTH_TOKEN` 一致；纯在线使用（WebSocket 实时收发）可以不配。
- `EXTERNAL_URL`：server 对外可达地址（含 scheme）。Docker/反代后 server 不知道自己的公网地址；不配则媒体消息在 bark/gotify 等第三方客户端通知里不显示图片、附件不可点击（原生 Hotify 客户端不受影响）。反代部署基本必配。

### 数据持久化

named volume `hotify-data` 一卷搞定，`docker compose down` 数据不丢（`down -v` 才删，慎用）：

| 路径 | 内容 |
|---|---|
| `/data/hotify.db` | 内嵌数据库（消息/设备/凭据） |
| `/data/blobs/` | 媒体文件（图片/音频/文件） |
| `/data/hotify.log` | 运行日志 |
| `/data/cli-token` | 内部管理文件（勿删） |

若改用 bind mount（`-v ./data:/data`），先 `chown -R 10001:10001 ./data`（容器内以 uid 10001 运行）。

### 备份 / 恢复 / 迁移

数据全在卷 `hotify-data` 里。备份（宿主机任意目录执行）：

```bash
docker run --rm -v hotify-data:/data -v "$(pwd)":/backup alpine \
  tar czf /backup/hotify-backup-$(date +%F).tar.gz -C /data .
```

恢复到新机：先 `docker compose up -d` 起一次让卷就位，再 `docker compose down`，确认备份文件无误后反向解包：

```bash
docker run --rm -v hotify-data:/data -v "$(pwd)":/backup alpine \
  sh -c "rm -rf /data/* && tar xzf /backup/hotify-backup-<日期>.tar.gz -C /data"
```

再 `docker compose up -d` 即完成迁移。binary 路线：exe 所在整个目录拷走即备份。

### TLS（容器里开 HTTPS）

两种形态：

- **直接 HTTPS**：证书挂只读进容器 + `CERT_FILE`/`KEY_FILE` 指过去。
- **反代终结 TLS**（Caddy/nginx 管 TLS，容器跑 plain HTTP）：不设 `CERT_FILE`/`KEY_FILE`，设 `TRUSTED_PROXIES: "172.16.0.0/12,127.0.0.1"` 让 server 正确解析 `X-Forwarded-For`。⚠️ nginx 默认**不转发 WebSocket**——实时通道（`/api/v1/stream`）会静默断掉，需加：

  ```nginx
  location / {
      proxy_pass http://127.0.0.1:8443;
      proxy_http_version 1.1;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection "upgrade";
      proxy_set_header Host $host;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  }
  ```

  （Caddy 的 `reverse_proxy` 原生支持 WebSocket，无需额外配置。）

### 国内拉取

镜像托管在阿里云 ACR（国内直连），无需额外加速配置。

---

## 路线 B：binary（Windows x64）

```bash
# 1. 从 Release 下载 exe（hotify-server-<版本>-windows-amd64.exe，版本以 Releases 页最新为准）
#    + checksums.txt，校验（对比 checksums.txt 内的哈希）
sha256sum hotify-server-<版本>-windows-amd64.exe
# Windows PowerShell 备选：
# Get-FileHash .\hotify-server-<版本>-windows-amd64.exe -Algorithm SHA256

# 2. 同目录放配置：复制本仓 config.example.yaml 为 config.yaml，改 token

# 3. 起服 + 健康检查
./hotify-server-<版本>-windows-amd64.exe
curl http://localhost:8443/ping
```

- 同目录生成 `hotify.db` / `blobs/` / `hotify.log` / `cli-token`——整个目录即全部状态，备份/迁移=拷目录。
- 配置字段全集见 `config.example.yaml` 内注释；环境变量可覆盖同名字段（裸字段名大写，如 `HTTPS_PORT`；`store.path` / `store.type` 除外——只走 config 文件/默认值）。
- 无证书时以 HTTP 起在主端口（配了 `tls.cert_file` 即 HTTPS）。
- **前台运行，关闭窗口即停止。**需要常驻可用 [NSSM](https://nssm.cc/) 注册为 Windows 服务，或用任务计划程序设为开机启动。

---

## 常用运维

```bash
docker compose up -d         # 起 / 改 environment: 后重建生效
docker compose logs -f       # 跟日志
docker compose restart       # 仅重启进程；不会应用 compose 文件的新改动（改 env 用上行）
docker compose down          # 停（数据留存）
curl http://localhost:8443/api/v1/info   # 版本/构建信息（排错先看这个）
# 升级：改 docker-compose.yml 里 image tag → docker compose up -d（数据在卷里不受影响）
```

## 接入

服务器起好后有三条路，按需选用：

- **Hotify 客户端**（鸿蒙/安卓）：客户端「设置 → 服务器」填入地址与注册凭证即可。客户端文档随源码开源后发布。
- **自写脚本 / 程序**：走 `POST /api/v1/push` 等原生接口，见 [API.md](API.md)。
- **现成的 bark / gotify 工具**（SmsForwarder、Home Assistant、Bark App、gotify App 等）：改个地址直接用，见 [README](README.md) 的「兼容 bark / gotify 生态」。
