# Hotify Server · 飞牛 fnOS 应用包（.fpk）

把 Hotify Server 打成 fnOS 应用中心可安装的 `.fpk`：桌面图标（入口=浏览器开 `http://<NAS>:8443/`，首次进 `/console` 初始化）、状态由容器健康代理、数据落在 docker named volume `hotify-data`（消息/媒体/DB 全在里面）。

## 安装

fnOS 桌面 → 应用中心 → 左下角「手动安装」→ 选 `hotify-server.fpk`。

- 镜像从阿里云 ACR 拉取（国内直连），tag 与本仓 docker-compose.yml 同步
- 默认端口 `8443`（HTTP；要 HTTPS 编辑 compose 挂证书 + `CERT_FILE`/`KEY_FILE`，见 DEPLOY.md）
- 改端口/环境变量：编辑 `/var/apps/hotify-server/target/docker/docker-compose.yaml` 后在应用中心重启应用

## 重新打包

官方工具 fnpack（developer.fnnas.com 直链下载，无需登录）。⚠️ 必须在 Linux 侧打（Windows fnpack 产物会丢 cmd 脚本执行位 + manifest 带 CRLF）：

```bash
# 下载 Linux 版（x86 NAS 用 amd64，ARM 用 arm64）
curl -LO https://static2.fnnas.com/fnpack/fnpack-1.2.3-linux-amd64
cd hotify-server/
tr -d '\r' < manifest > manifest.lf && mv manifest.lf manifest   # 防 CRLF（若在 Windows 编辑过）
chmod 755 cmd/* fnpack-1.2.3-linux-amd64
./fnpack-1.2.3-linux-amd64 build   # → hotify-server.fpk
```

Windows 开发机可用 Docker 等价执行：

```bash
MSYS_NO_PATHCONV=1 docker run --rm -v "<本目录的绝对路径>:/work" -w /work alpine sh -c \
  "tr -d '\r' < manifest > manifest.lf && mv manifest.lf manifest && chmod 755 cmd/* fnpack-linux && ./fnpack-linux build"
```

## 结构（fnpack create --template docker 官方骨架 + Hotify 定制）

```
hotify-server/
├── manifest                 # appname/version/platform=all（镜像双架构远程拉取，包内无架构二进制）/service_port=8443/changelog
├── ICON.PNG / ICON_256.PNG  # 64/256 应用图标（Hotify 客户端 icon.png 缩放）
├── app/
│   ├── docker/docker-compose.yaml  # 引用 ACR 镜像（版本与发行 tag 同步）+ TZ Asia/Shanghai + named volume
│   └── ui/                  # 桌面入口：type=url http://<NAS>:8443/（服务端 302 → /console）
├── cmd/                     # 官方模板脚本：main 的 status 查 container_name 对应容器；其余 no-op（生命周期交 fnOS Docker Project）
└── config/                  # privilege（官方默认 run-as package）+ resource（docker-project 声明）
```

## 发版步骤（每次新版本）

1. 源码仓打 `vX.Y` tag → CI 出镜像（ACR+GHCR）与 GitHub Release 二进制
2. 本目录 `manifest` 的 `version`/`changelog` 更新，compose 里 image tag 改 `:vX.Y`
3. 按上面「重新打包」出 `.fpk`，附到 GitHub Release + Gitee Release（镜像国内可达）
