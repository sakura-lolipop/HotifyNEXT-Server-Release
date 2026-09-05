#!/bin/sh
# install.sh — Hotify Server 一键部署（Docker；Linux / NAS）
#
# 用法：
#   curl -fsSL https://gitee.com/sakura-lolipop/HotifyNEXT-Server-Release/raw/main/install.sh | bash
#   ./install.sh                 # 部署（重复执行 = 升级：重新拉取镜像 + up -d，不影响数据卷）
#   ./install.sh --uninstall     # 仅打印卸载指令（不执行、不删数据）
#
# 可用环境变量覆盖默认值：HOTIFY_TAG（版本）、HOTIFY_PORT（主端口）。

set -u

TAG="${HOTIFY_TAG:-v1.4}"
REGISTRY_HOST="crpi-gi2hyqoir87c0lus.cn-hangzhou.personal.cr.aliyuncs.com"
IMAGE="$REGISTRY_HOST/sakura-lolipop/hotify-server"
PORT="${HOTIFY_PORT:-8443}"
COMPOSE_FILE="docker-compose.yml"

info() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m错误:\033[0m %s\n' "$*" >&2; exit 1; }

uninstall_help() {
    cat <<EOF
卸载指令（自行执行，脚本不代为删除数据）：

  docker compose down        # 停容器（数据卷 hotify-data 留存，消息/媒体不会丢失）
  docker compose down -v     # ⚠️ 停 + 删数据卷（全部消息与媒体被删除，不可恢复）
  docker rmi $IMAGE:$TAG     # 删镜像
EOF
    exit 0
}

preflight() {
    info "检测环境"
    command -v docker >/dev/null 2>&1 || die "未找到 docker。请先安装 Docker（https://docs.docker.com/engine/install/）"
    command -v curl >/dev/null 2>&1 || die "未找到 curl（健康检查依赖）"
    docker compose version >/dev/null 2>&1 || die "docker compose v2 不可用（旧版 docker-compose 请升级）"
    ARCH="$(docker info --format '{{.Architecture}}' 2>/dev/null || echo unknown)"
    case "$ARCH" in
        x86_64|amd64|aarch64|arm64) info "架构 $ARCH ✔（镜像支持 amd64 / arm64）" ;;
        *) die "架构 $ARCH 不在支持列表（amd64 / arm64）" ;;
    esac
    docker ps >/dev/null 2>&1 || die "当前用户无 docker 权限。可尝试：sudo ./install.sh，或将当前用户加入 docker 组后重新登录"
}

ensure_image() {
    info "拉取镜像 $IMAGE:$TAG"
    if ! docker pull "$IMAGE:$TAG"; then
        die "拉取失败。请检查网络；若提示需要认证（authentication required），说明该版本镜像暂不可匿名拉取"
    fi
}

write_compose() {
    if [ -f "$COMPOSE_FILE" ]; then
        info "已存在 $COMPOSE_FILE，保留不覆盖。升级：编辑 image tag 至 $TAG 后 docker compose up -d"
        return 0
    fi
    info "生成 $COMPOSE_FILE"
    cat > "$COMPOSE_FILE" <<EOF
# 由 install.sh 生成。全部可配项见仓内 docker-compose.yml（带完整注释）与 DEPLOY.md。
services:
  hotify-server:
    image: $IMAGE:$TAG
    container_name: hotify-server
    restart: unless-stopped
    ports:
      - "$PORT:8443"
    # environment 按需取消注释启用（离线推送默认开箱即用，无需配置）：
    # environment:
    #   CLOUD_FUNCTION_TOKEN: "your-own-token"      # 自建票端点开了 TICKET_AUTH_TOKEN 才填；默认空=匿名开放
    #   EXTERNAL_URL: "https://your-domain.example" # 反向代理/隧道后必须配置（第三方客户端通知显示图片）
    volumes:
      - hotify-data:/data

volumes:
  hotify-data:
    name: hotify-data # 固定卷名（备份/迁移直接引用，不带项目前缀）
EOF
}

start() {
    info "启动容器"
    docker compose -f "$COMPOSE_FILE" up -d || die "启动失败，查看日志：docker compose logs --tail=50"
}

healthcheck() {
    info "健康检查（最长等待 30s）"
    i=0
    while [ "$i" -lt 30 ]; do
        if curl -fs "http://localhost:$PORT/ping" >/dev/null 2>&1; then
            info "✔ ping 通过"
            return 0
        fi
        i=$((i+1)); sleep 1
    done
    echo "---- 最近日志 ----"
    docker compose -f "$COMPOSE_FILE" logs --tail=50 || true
    die "健康检查超时。上方日志为排查线索；常见原因：端口被占用 / 权限问题 / 远程访问需在云安全组放行该端口"
}

summary() {
    cat <<EOF

✔ Hotify Server 已启动：http://localhost:$PORT （ping 已通过）

下一步：
  0. 获取主凭证：浏览器打开 http://localhost:$PORT/console（或首台设备注册时自动生成）
  1. 通知显示图片（第三方客户端）：编辑 $COMPOSE_FILE 取消注释 EXTERNAL_URL
     （说明见 DEPLOY.md）→ docker compose up -d。离线推送已开箱即用，无需配置。
  2. 发消息：见 README「API 快速参考」
  3. 现成工具（SmsForwarder / Home Assistant / Bark App / gotify…）：见 README「兼容 bark / gotify 生态」
  数据在 docker 卷 hotify-data（备份见 DEPLOY.md）。
EOF
}

main() {
    [ "${1:-}" = "--uninstall" ] && uninstall_help
    preflight
    ensure_image
    write_compose
    start
    healthcheck
    summary
}

main "$@"
