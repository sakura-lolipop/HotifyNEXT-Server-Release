# aideploy.md · AI 智能部署 runbook

> **本文件写给 AI 部署助手**（Claude Code / Codex CLI / Cursor 等任何能执行命令、访问网络的 agent）。
> 用户对你说「读 aideploy.md 帮我部署 Hotify」时，你就是部署执行者，按本文件走：
> **先探测（§1）→ 问询收集参数（§2）→ 用户确认方案 → 选路径执行（§3）→ 验证交付（§4）**。
> **语言**：本文件以中文撰写；无论用户使用什么语言，你的问询、方案卡、进度报告与部署档案一律跟随用户的语言。
> **raw 基址**：`https://gitee.com/sakura-lolipop/HotifyNEXT-Server-Release/raw/main/`——下文提到的「本仓」文件都在此路径下取。
> 人类向详解：[DEPLOY.md](https://gitee.com/sakura-lolipop/HotifyNEXT-Server-Release/raw/main/DEPLOY.md) · 接口：[API.md](https://gitee.com/sakura-lolipop/HotifyNEXT-Server-Release/raw/main/API.md) · 配置字段全集：[config.example.yaml](https://gitee.com/sakura-lolipop/HotifyNEXT-Server-Release/raw/main/config.example.yaml)

## 0 · 铁律（先于一切）

1. **数据红线**：永不执行 `docker compose down -v`；永不删除 `hotify.db`、`blobs/`、`cli-token`、`hotify-data` 卷、二进制目录内的数据文件。目标机已有上述任一 = 已有安装，**先问用户意图**——升级（§5）/ 保持不动另装一套（§3.7）/ 卸载重装——不要不问就按新装流程执行。
2. **已存在不覆盖**：目标机已有 `docker-compose.yml` / `config.yaml` / systemd unit / NSSM 服务时，先展示现有内容与你计划的差异，征得确认再动。
3. **停服务必先问**：停/重启既有进程（含占用目标端口的其他服务）前必须征得用户确认。
4. **失败即停即报**：命令失败先读输出对照 §6 诊断，不盲目重试；同一路径失败两次换方法或报告现状。
5. **凭证不落盘不回显**：key1、密码、证书、SSH 私钥不写进任何会被提交的文件，不在对话中完整回显。
6. **公网第一件事**：服务启动成功后**立刻**引导用户完成 `/console` 首访初始化（先到先得，防陌生人抢注，见 §4）。
7. **应用商店包禁代装**：fpk 等经应用商店/安装器 GUI 安装的包，你只负责下载与移交文件，**安装动作必须由用户在对应界面完成**——不要尝试用命令行代装。

## 1 · 探测（先查后问，别问已能查到的）

**本机**（部署目标 = 你运行的机器时）：

```bash
uname -s -m                      # Linux(x86_64/aarch64) / Darwin；Windows agent 用 PowerShell: $env:PROCESSOR_ARCHITECTURE
command -v docker && docker compose version    # docker 有无
command -v ssh scp               # 远程部署的前提
ss -ltn | grep 8443              # 端口占用（Windows: netstat -ano | findstr 8443）
```

**远程机**（用户给了 SSH 目标时）：

```bash
ssh -p <port> <user>@<host> 'uname -s -m; command -v docker && docker compose version; command -v sudo >/dev/null && sudo -n true && echo SUDO_NOPASS'
```

- 连不上 / 只能密码登录 → 先走 §3.0。
- 记下：OS、arch、docker 有无、sudo 是否免密——§2 的 Q3 可据此自动作答。

**已安装检测（先于一切问询——装过就别当新装）**，按目标 OS 取用：

```bash
# docker 路线
docker ps -a --filter name=hotify-server --format '{{.Names}} {{.Status}}'   # 有输出=已有容器
docker volume ls --format '{{.Name}}' | grep -i hotify                        # 卷（含旧前缀卷）
ls docker-compose.yml 2>/dev/null                                             # 目标目录已有 compose
# binary 路线（目标机）
ls /opt/hotify-server ~/hotify-server 2>/dev/null                             # 常见位置（Windows: D:\hotify-server 等，找 hotify.db）
systemctl is-active hotify 2>/dev/null                                        # Linux systemd
sc query hotify 2>/dev/null                                                   # Windows 服务(NSSM)
```

命中后先分类再问（三类不是一回事）：

- **在跑实例**（容器 Up / systemd active）→ §2 首问三选一：**升级它 / 保持不动另装一套（多实例，§3.7）/ 卸载重装**，方案卡带上现有实例的版本与端口。
- **固定名孤儿卷 `hotify-data`**（无容器无 compose）→ 新装会**静默收养**它：旧消息与旧 key1 一起复活，`/console` 出登录页而非初始化表单。先问用户：沿用旧数据（保留卷）还是清掉（确认后 `docker volume rm hotify-data` 再装）。
- **旧前缀卷 `<目录名>_hotify-data`**（固定卷名之前的遗留）→ 对新装无影响（新 compose 会新建空卷），可无视或让用户自行清理。

**最新版本**（不要写死版本号）：

```bash
curl -s https://gitee.com/api/v5/repos/sakura-lolipop/HotifyNEXT-Server-Release/releases/latest
# 取 tag_name 与 assets[].browser_download_url（二进制 + checksums.txt 直链）
# 拿不到 → 退回本仓 install.sh 内置默认 tag，或问用户
```

## 2 · 问询（按序；探测已能回答的跳过；选项相近可合并成一轮问）

| # | 问题 | 选项与默认 | 备注 |
|---|---|---|---|
| Q1 | 部署到哪 | **本机** / 远程机(SSH) | 决定后续命令本地跑还是套 ssh |
| Q2 | （远程时）SSH 连接 | host / user / port / 密钥 or 密码 | 密码认证先按 §3.0 配置密钥 |
| Q3 | 部署形态 | **Docker（推荐）** / 二进制裸跑 | 无 docker 且不想装 → 降级二进制；Windows 目标默认二进制；飞牛 fnOS：从 §1 API 的 assets 取 `hotify-server.fpk` **移交用户**，由用户在 fnOS 应用中心手动安装（铁律 7，商店包禁代装） |
| Q4 | 网络形态 | **a 局域网 HTTP（最简默认）** / b 反代终结 TLS / c 直配证书 / d 有域名无证书→签发 | 选 b 追问：反代是 Caddy / nginx / 面板已装？域名是什么？ |
| Q5 | 对外地址 | `https://域名[:端口]`，没有则跳过 | 反代 / 公网 / 隧道场景必填（`EXTERNAL_URL`）；纯局域网可跳过 |
| Q6 | 端口 | 默认 **8443** | 被占时问换成哪个 |
| Q7 | 常驻方式（仅二进制路线） | Linux: systemd / Windows: NSSM / 先前台试跑 | 建议先试跑验证再装服务 |
| Q8 | 实例数 | **单实例（默认）** / 多实例（同机多用户各一套） | 探测到已有安装时必问；多实例走 §3.7。Hotify 一实例 = 单租户（一个主凭证（=key1）+ 设备群），多用户数据隔离靠多实例，不靠同实例分账号 |

问完输出**部署方案卡**让用户确认：目标 / 形态 / 版本 / 端口 / TLS 形态 / 数据位置 / 常驻方式。确认后才进 §3。

## 3 · 执行

### 3.0 SSH 通道前提（远程部署时）

- 优先密钥认证。只能密码登录时，给用户配置密钥的命令让其**自己**执行（有交互输密码）：
  ```bash
  ssh-keygen -t ed25519          # 没密钥先生成
  # Windows 本机（cmd.exe）：type %USERPROFILE%\.ssh\id_ed25519.pub | ssh -p <port> <user>@<host> "cat >> ~/.ssh/authorized_keys"
  # Windows 本机（PowerShell）：Get-Content $env:USERPROFILE\.ssh\id_ed25519.pub | ssh -p <port> <user>@<host> "cat >> ~/.ssh/authorized_keys"
  # Linux/macOS 本机：ssh-copy-id -p <port> <user>@<host>
  ```
- 远程 sudo 不免密：sudo 命令用 `ssh -t`（用户终端输密码），或请用户自行配置；**不要绕**。
- 远程命令先单条验证通过，再批量执行。

### 3.1 Docker · 一键脚本（Linux 本机/远程；幂等；推荐）

```bash
# 本机
curl -fsSL https://gitee.com/sakura-lolipop/HotifyNEXT-Server-Release/raw/main/install.sh | bash
# 远程（在其上执行同一条）
ssh -p <port> <user>@<host> 'curl -fsSL https://gitee.com/sakura-lolipop/HotifyNEXT-Server-Release/raw/main/install.sh | bash'
# 指定版本/端口（env 前缀必须贴着管道右端的 bash，或放进 ssh 引号内——挂错位置会静默装出默认值）：
curl -fsSL https://gitee.com/sakura-lolipop/HotifyNEXT-Server-Release/raw/main/install.sh | HOTIFY_TAG=vX.Y HOTIFY_PORT=9443 bash
ssh -p <port> <user>@<host> 'HOTIFY_PORT=9443 curl -fsSL https://gitee.com/sakura-lolipop/HotifyNEXT-Server-Release/raw/main/install.sh | bash'
```

特性：重复执行 = 刷新当前 tag 镜像（不动数据卷）；已存在 compose **不覆盖（tag 不变——跨版本升级须手动改 tag，见 §5）**；docker 缺失/架构不符会明确报错。跑通直接进 §4。

### 3.2 Docker · 手动 compose（需要精细控制 env 时；**Windows 本机 Docker Desktop 也走这条**——§3.1 一键脚本面向 Linux）

1. 把本仓 `docker-compose.yml` 传到目标目录（raw 基址拼文件名 curl 下来，或 scp）。
2. 按需编辑 `environment:` 块（矩阵见下）。⚠️ **别用 `.env` 或 `env_file:`**——群晖/Portainer 等 GUI 不读取。
3. compose 钉稳定 tag（有意的「确认升级」设计）：方案卡版本 ≠ compose 里 image tag 时，同步改 image 行；**不要改成 `latest`**（pull 会隐式升级到未预览版本）。
4. `docker compose up -d`，`docker compose logs --tail 20` 确认监听（人类交互终端才用 `-f`；agent 非交互执行 `-f` 会挂住）。

env 矩阵（全部 opt-in；一项不配也能启动，离线推送开箱即用）：

| env | 何时设 | 值与说明 |
|---|---|---|
| `EXTERNAL_URL` | 反代 / 公网 / 隧道（Q4=b/c/d 或 Q5 有值） | `https://域名[:端口]`。不设则 bark/gotify 等第三方客户端里媒体不显示、附件不可点（原生 Hotify 客户端不受影响） |
| `TRUSTED_PROXIES` | 反代终结 TLS | `"172.16.0.0/12,127.0.0.1"`（正确解析 X-Forwarded-For） |
| `CERT_FILE` / `KEY_FILE` | 直配证书（Q4=c） | 容器内路径，配合 `./certs:/data/certs:ro` 只读挂载 |
| `CLOUD_FUNCTION_TOKEN` | **基本不用** | 离线推送的出票服务（票端点）仅自建、且其开了 `TICKET_AUTH_TOKEN` 时才填同值；项目方公共端点匿名开放，留空 |

注意：`store.path` / `store.type` 不走 env。数据全在 named volume `hotify-data`（`/data` 下 db / blobs / log / cli-token）——本仓 compose 已用 `name:` 固定卷名，不随部署目录变。仅处理**固定卷名之前**的旧测试部署时才需 `docker volume ls -q | grep hotify` 核对（旧卷带 `<目录名>_` 前缀）；改 bind mount 须先 `chown -R 10001:10001 ./data`（容器以 uid 10001 运行）。

### 3.3 Windows · 二进制

```powershell
# 1) 下载：hotify-server-<tag>-windows-amd64.exe + checksums.txt（Release 附件；§1 的 API 取直链）
# 2) 校验（对比 checksums.txt 内对应行）
Get-FileHash .\hotify-server-<tag>-windows-amd64.exe -Algorithm SHA256
# 3) 建目录如 D:\hotify-server\：exe 放入，本仓 config.example.yaml 复制为同目录 config.yaml（默认值即可启动）
# 4) 前台试跑该 exe；新窗口 curl http://localhost:8443/ping 验证
```

常驻（Q7=NSSM，nssm 未装先去 https://nssm.cc 下载放 PATH）：

```cmd
nssm install hotify D:\hotify-server\hotify-server-<tag>-windows-amd64.exe
nssm set hotify AppDirectory D:\hotify-server
nssm start hotify
```

（无 NSSM 也可用任务计划程序设开机启动。）前台运行时**关窗口即停**。

### 3.4 Linux · 二进制 + systemd（远程无 docker 时）

```bash
# arch 映射：x86_64→amd64，aarch64→arm64，armv7l→armv7
# 1) 取二进制（§1 API 直链）放 /opt/hotify-server/hotify-server，chmod +x
# 2) 本仓 config.example.yaml → /opt/hotify-server/config.yaml（默认值可启动）
# 3) 写 /etc/systemd/system/hotify.service：
```

```ini
[Unit]
Description=Hotify Server
After=network-online.target
Wants=network-online.target

[Service]
WorkingDirectory=/opt/hotify-server
ExecStart=/opt/hotify-server/hotify-server
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload && sudo systemctl enable --now hotify && systemctl is-active hotify
```

（macOS 目标同理下载 `darwin-amd64/arm64` 二进制，常驻用 launchd，不再展开。）

### 3.5 反代（Q4=b）

服务侧：设 `TRUSTED_PROXIES`（+ 公网场景 `EXTERNAL_URL`），**不**设 `CERT_FILE`。反代侧二选一：

Caddy（自动签发 HTTPS，无需手工管证书）：

```caddyfile
your-domain.example {
    reverse_proxy 127.0.0.1:8443
}
```

nginx（⚠️ 默认**不转发 WebSocket**——实时通道会静默断开；默认 1M body 会挡媒体上传/备份）：

```nginx
server {
    listen 443 ssl;
    server_name your-domain.example;
    ssl_certificate     /path/fullchain.pem;
    ssl_certificate_key /path/privkey.pem;
    location / {
        proxy_pass http://127.0.0.1:8443;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        client_max_body_size 0;
    }
}
```

### 3.6 证书签发（Q4=d，独立机直签场景）

```bash
curl https://get.acme.sh | sh -s email=you@example.com
~/.acme.sh/acme.sh --issue -d your-domain.example --standalone    # 需 80 端口公网可达
~/.acme.sh/acme.sh --install-cert -d your-domain.example --ecc \
  --key-file /path/hotify/privkey.pem --fullchain-file /path/hotify/fullchain.pem \
  --reloadcmd "<重启命令：docker compose restart | systemctl restart hotify | nssm restart hotify>"
```

签好按 §3.2 直配证书（或 §3.5 反代挂载）走。目标机已有面板/反代管证书的，用它们自己的签发，**不要重复签**。

### 3.7 同机多实例（多用户）

Hotify 一实例 = 一套独立凭证与数据（单租户）。同机给多个用户各一套 = 多实例：复制本仓 `docker-compose.yml` 后**三处同改**（其余不动），第 N 套递增：

```yaml
# 1) 容器名
container_name: hotify-server-2
# 2) 宿主端口
ports:
  - "8444:8443"
# 3) 卷名（三处一致改名：service 挂载点 + 顶层 volumes 键 + name:）
volumes:
  - hotify-data-2:/data
# ……顶层：
volumes:
  hotify-data-2:
    name: hotify-data-2
```

`docker compose up -d` 后每套独立初始化（各自 `/console`）、独立备份（各卷名）。行为边界（均不损坏在跑实例的数据）：

- **什么都不改**原样再起 → 容器名冲突，创建直接失败中止。
- 只改容器名/端口、**漏改卷名** → 第二套反复重启，日志 `open bbolt hotify.db: timeout`——bbolt 文件锁拒绝两个进程共用同一数据库文件；把三处卷名改一致即可。
- 反代多实例：各子域名各 upstream，各自 `EXTERNAL_URL`。

## 4 · 验证与交付（三步，别跳步）

1. **服务级**：`curl http(s)://<host>:<port>/ping` → `{"code":200,"message":"pong"}`；`/api/v1/info` 看版本。服务端配的是自签证书时 curl 加 `-k`。
2. **初始化（立刻提醒）**：让用户**马上**浏览器打开 `http(s)://<host>:<port>/console`（或 `/setup`，首访两入口同一张表单）——已预填高熵随机值，保存即完成，成功页**一次性**显示 key1（=管理密码，仅此一次，提醒用户立即保存）。公网部署这是抢注竞速，**服务起好的第一件事就是提醒这步**。若出的是登录页而非初始化表单 = 该卷已有旧 key1（§1 收养分支）。换密码：/console 管理页或 `/setup`（需当前密码）；**忘记密码**：在服务器上跑同二进制 CLI——binary 路线在 exe 同目录执行 `hotify-server show password`（Windows 即该 exe 文件名），docker 路线 `docker exec hotify-server hotify-server show password`（读 cli-token 取回 key1）；或 `reset password`（重置，全部设备需重新接入）/ `reset register`（清 key1 重开初始化窗口）。
3. **首条推送冒烟**：用户在 Hotify App「设置 → 服务器」填地址（自动注册）；或用 bark / gotify App 按对应方式接入。用户在任意客户端发出第一条消息即视为冒烟通过（`POST /api/v1/push` 的 curl 由用户自己执行——key1 不经过你，用法见 [API.md](https://gitee.com/sakura-lolipop/HotifyNEXT-Server-Release/raw/main/API.md)）。

交付时输出**部署档案**（用户以后靠它）：

```
目标机 / 形态 / 版本 / 端口 / TLS 形态
数据位置（卷或目录）· 日志查看命令 · 升级一条命令 · 停服一条命令
```

## 5 · 升级 / 备份 / 卸载

- **升级（docker）**：**改 compose image tag → `docker compose up -d`（唯一可靠路径**，数据在卷不受影响）。重跑 install.sh **不会**跨版本——compose 已存在时脚本不覆盖、tag 不变，只刷新当前 tag 的镜像。
- **升级（binary）**：停服 → 覆盖二进制 → 重启服务（数据都在目录里）。
- **备份**（docker，宿主机任意目录执行）：
  ```bash
  docker run --rm -v hotify-data:/data -v "$(pwd)":/backup alpine \
    tar czf /backup/hotify-backup-$(date +%F).tar.gz -C /data .
  ```
  恢复/迁移步骤见 DEPLOY.md「备份 / 恢复 / 迁移」（raw 基址下；旧版部署的卷可能带前缀，先 `docker volume ls -q | grep hotify` 核对）；binary = 拷贝整个目录。
- **卸载**：`docker compose down`（数据留存）/ 停服删 unit；彻底清理另加 `docker rmi <compose 里 image 的完整地址>`（`install.sh --uninstall` 只打印指令不代删，同样安全）。彻底删数据必须用户**亲口确认后自己执行** `down -v`，你不代跑（纯测试/一次性部署经用户确认后可代跑，事后报告）。

## 6 · 排错速查

| 症状 | 先查 | 常见原因 |
|---|---|---|
| ping 不通 | `docker compose logs` / `journalctl -u hotify -n 50` / 进程在否 | 端口被占（换 `HOTIFY_PORT`/`HTTPS_PORT`）；防火墙/云安全组没放行 |
| 容器反复重启 | logs 尾部 | 卷/bind mount 没给 uid 10001 所有权（被外部工具以 root 写过也算，§3.2；症状 `permission denied`） |
| 本机通、浏览器/外网打不开 | 防火墙/云安全组、反代 upstream/DNS | 端口未放行；反代指错地址（WS 转发与 `EXTERNAL_URL` 不影响「打不开」，见下两行） |
| 第三方客户端图片不显示 | `EXTERNAL_URL` | 反代/公网场景没配（§3.2 矩阵） |
| 在线收得到、离线推不到 | WS 在线是否正常 | 推送云函数链路问题，与本次部署无关（见 [DEPLOY.md](DEPLOY.md) 顶部说明） |
| 拉镜像失败 | 到 ACR 的网络 | 海外机改拉 `ghcr.io/sakura-lolipop/hotify-server`（同 tag） |
| 同机再起一套：container name 冲突 | 是否已有实例在跑 | 单机单实例默认；要双实例按 §3.7 三处同改 |
| 第二套反复重启，日志 `bbolt timeout` | 卷名漏改，两容器共用同一数据库文件 | bbolt 文件锁拒绝（防止相互写坏数据，数据无损）；按 §3.7 改齐卷名 |
| 改了 env 后行为没变 | 是否只执行了 `restart` | `restart` 不重读 compose 改动，改 env 后要 `up -d`（§3.2） |
