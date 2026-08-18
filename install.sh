#!/bin/sh
# install.sh — Hotify Server 一键部署（Docker；Linux / NAS）
#
# 用法：
#   ./install.sh                 # 部署（重复执行 = 升级：重拉镜像 + up -d，不动数据卷）
#   ./install.sh --uninstall     # 仅打印卸载指令（不执行、不删数据）
#
# 可用环境变量覆盖默认值：HOTIFY_TAG（版本）、HOTIFY_PORT（主端口）。
# 私有阶段需先：docker login crpi-gi2hyqoir87c0lus.cn-hangzhou.personal.cr.aliyuncs.com
# （凭证由项目方发放；公开后免登录）

set -u

TAG="${HOTIFY_TAG:-v1.0-L2.1}"
REGISTRY="crpi-gi2hyqoir87c0lus.cn-hangzhou.personal.cr.aliyuncs.com/sakura-lolipop/hotify-server"
PORT="${HOTIFY_PORT:-8443}"
COMPOSE_FILE="docker-compose.yml"

info() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m错误:\033[0m %s\n' "$*" >&2; exit 1; }

uninstall_help() {
    cat <<EOF
卸载指令（自行执行，脚本不代删数据）：

  docker compose down        # 停容器（数据卷 hotify-data 留存，消息/媒体不丢）
  docker compose down -v     # ⚠️ 停 + 删数据卷（全部消息与媒体被删除，不可恢复）
  docker rmi $REGISTRY:$TAG  # 删镜像
EOF
    exit 0
}

preflight() {
    info "检测环境"
    command -v docker >/dev/null 2>&1 || die "未找到 docker。请先安装 Docker（https://docs.docker.com/engine/install/）"
    docker compose version >/dev/null 2>&1 || die "docker compose v2 不可用（老版 docker-compose 请升级）"
    ARCH="$(docker info --format '{{.Architecture}}' 2>/dev/null || echo unknown)"
    case "$ARCH" in
        x86_64|amd64|aarch64|arm64) info "架构 $ARCH ✔（镜像支持 amd64 / arm64）" ;;
        *) die "架构 $ARCH 不在支持列表（amd64 / arm64）" ;;
    esac
    docker ps >/dev/null 2>&1 || die "当前用户无 docker 权限。试：sudo ./install.sh 或把用户加 docker 组后重新登录"
}

ensure_image() {
    info "拉取镜像 $REGISTRY:$TAG"
    if ! docker pull "$REGISTRY:$TAG"; then
        die "拉取失败。私有阶段需先执行：docker login $REGISTRY（凭证由项目方发放）"
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
    image: $REGISTRY:$TAG
    container_name: hotify-server
    restart: unless-stopped
    ports:
      - "$PORT:8443"
    environment:
      # —— 按需取消注释改值 ——
      # CLOUD_FUNCTION_TOKEN: "changeme"             # 离线推送必配（与云函数侧一致）；纯在线可不配
      # EXTERNAL_URL: "https://your-domain.example"  # 反代/隧道后必配（第三方客户端通知显图）
    volumes:
      - hotify-data:/data

volumes:
  hotify-data:
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
    die "健康检查超时。上方日志为排查线索；常见原因：端口被占用 / 权限问题"
}

summary() {
    cat <<EOF

✔ Hotify Server 已启动：http://localhost:$PORT （ping 已通过）

下一步：
  1. 离线推送 / 通知显图：编辑 $COMPOSE_FILE 的 environment: 块
     （CLOUD_FUNCTION_TOKEN / EXTERNAL_URL，说明见 DEPLOY.md）→ docker compose up -d
  2. 发消息：见 README「API 快速参考」
  3. 现成工具（SmsForwarder / Home Assistant / Bark App / gotify…）：见 README「兼容 bark / gotify 生态」
  数据在 docker 卷 hotify-data（备份见 DEPLOY.md）。
EOF
    grep -qE '^[[:space:]]*#.*CLOUD_FUNCTION_TOKEN' "$COMPOSE_FILE" 2>/dev/null && \
        echo "  提示：当前未配 CLOUD_FUNCTION_TOKEN —— 仅在线收发（WebSocket），离线推送见 DEPLOY.md。"
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
