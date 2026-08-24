#!/usr/bin/env bash
# scripts/gitee-upload.sh — 发版后本地传附件到 Gitee Release（国内机→Gitee 国内，快、不挂）。
#
# 抄 hotify-bridge/scripts/gitee-upload.sh 同款纪律（跨太平洋 CI 传会 TCP stall 永久挂，本地直传秒级）。
# 传的内容：GitHub Release 上的 6 平台二进制 + checksums.txt（gh release download 拉下来原样传）
#           + 本仓 fpk/hotify-server/hotify-server.fpk（飞牛包）。
# 传到哪：发行仓 HotifyNEXT-Server-Release（国内下载口；源码仓 Gitee 是私有镜像不上 release）。
# 正文：源码仓 changelog/<tag>.md（release-binaries.yml 同源）。
#
# 用法：
#   GITEE_TOKEN=你的私人令牌 bash scripts/gitee-upload.sh [tag]
#   令牌：gitee.com → 头像 → 设置 → 私人令牌 → 生成（勾 projects）。可存 bark/secrets/giteetoken.txt
#   （脚本没读到环境变量时自动从该文件取）。别提交 git/入 chat。
#
# 依赖：curl、git、gh（拉 GitHub 附件）、python（body JSON 转义，避 cp936 inline 中文）；jq 可选（删旧用）。
set -e
cd "$(git rev-parse --show-toplevel)"

TAG="${1:-$(git -C ../HotifyNEXT-Server describe --tags --abbrev=0 2>/dev/null)}"
[ -n "$TAG" ] || { echo "❌ 没指定 tag，源码仓也没 git tag 可用"; exit 1; }

# 令牌：环境变量优先，空则试本地 secrets 文件（不入 chat/日志——只读不 echo）
TOKEN="${GITEE_TOKEN:-$(tr -d '[:space:]' < "$HOME/bark/secrets/giteetoken.txt" 2>/dev/null || true)}"
TOKEN="${TOKEN:-$(tr -d '[:space:]' < "/c/Users/littl/bark/secrets/giteetoken.txt" 2>/dev/null || true)}"
[ -n "$TOKEN" ] || { echo "❌ 无令牌：export GITEE_TOKEN=... 或填 bark/secrets/giteetoken.txt"; exit 1; }

OWNER="sakura-lolipop"; REPO="HotifyNEXT-Server-Release"
API="https://gitee.com/api/v5/repos/$OWNER/$REPO"
GH_REPO="sakura-lolipop/HotifyNEXT-Server"

# 按 tag 取 release id（无 jq 跳过删旧，绝不 grep-first 兜底——bridge 实测踩过误删别的 tag 的 release）
get_rid_by_tag() {
  local resp; resp=$(curl -sSL --max-time 30 "$API/releases?access_token=$TOKEN" 2>/dev/null)
  if command -v jq >/dev/null 2>&1; then
    echo "$resp" | jq -r ".[] | select(.tag_name==\"$TAG\") | .id" | head -1
  else
    echo "⚠️ 无 jq：跳过删旧（grep-first 会误删别的 release）。装 jq 再跑可清旧。" >&2
  fi
}

echo "=== 拉附件：GitHub Release $TAG → dist-gitee/ ==="
DIST="dist-gitee"; mkdir -p "$DIST"
gh release download "$TAG" -R "$GH_REPO" -D "$DIST" -p "hotify-server-*" -p "checksums.txt" --clobber
FPK="fpk/hotify-server/hotify-server.fpk"
[ -f "$FPK" ] || { echo "❌ $FPK 不存在（先按 fpk/README 重打包）"; exit 1; }
ls -la "$DIST" "$FPK"

echo "=== 删旧 release（tag=$TAG，若有）==="
OLD=$(get_rid_by_tag)
if [ -n "$OLD" ]; then
  echo "删旧 release id=$OLD"
  curl -fsSL --max-time 30 -X DELETE "$API/releases/$OLD?access_token=$TOKEN" -o /dev/null 2>/dev/null || echo "  (删除非 2xx，继续)"
  sleep 2   # 给 Gitee 传播时间，免得立刻建撞「该标签已存在发行版」
fi

echo "=== 建新 release（body=源码仓 changelog/$TAG.md，JSON 走文件避 cp936）==="
CHANGELOG="../HotifyNEXT-Server/changelog/$TAG.md"
[ -f "$CHANGELOG" ] || CHANGELOG="/dev/null"
BODY_TMP="$(mktemp --suffix=.json)"
python - "$CHANGELOG" "$TAG" > "$BODY_TMP" <<'PY'
import json, sys
body = open(sys[1], encoding="utf-8").read() if sys[1] != "/dev/null" else f"{sys[2]} 发布说明见 GitHub Releases。"
print(json.dumps({"tag_name": sys[2], "name": f"Hotify Server {sys[2]}", "body": body}, ensure_ascii=False))
PY
RID=""
for attempt in 1 2 3 4; do
  RID=$(curl -fsSL --max-time 30 -X POST "$API/releases?access_token=$TOKEN" -H "Content-Type: application/json" \
    -d @"$BODY_TMP" 2>/dev/null | python -c "import json,sys; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)
  [ -n "$RID" ] && break
  RID=$(get_rid_by_tag)   # 可能前一次已建成 → 按 tag 找复用
  [ -n "$RID" ] && { echo "（release 已存在，复用 id=$RID）"; break; }
  echo "  建 release 第 $attempt 次没拿到 id，重试..."; sleep 2
done
rm -f "$BODY_TMP"
echo "release id=$RID"
[ -n "$RID" ] || { echo "❌ 建 release 多次失败；过会儿重跑本脚本"; exit 1; }

echo "=== 传附件（国内直连：6 二进制 + checksums + fpk）==="
fails=0
for f in "$DIST"/hotify-server-* "$DIST/checksums.txt" "$FPK"; do
  printf '  → %-48s ' "$(basename "$f")"
  if curl -fsSL --max-time 180 --retry 3 --retry-delay 5 -X POST "$API/releases/$RID/attach_files" \
    -F "access_token=$TOKEN" -F "file=@$f" -o /dev/null -w 'http %{http_code}\n' 2>/dev/null; then :
  else echo "❌ 失败"; fails=$((fails+1)); fi
done

echo ""
if [ "$fails" -gt 0 ]; then
  echo "❌ $TAG：$fails 个附件传失败，release 不完整（重跑本脚本会删旧重建补全）"
  exit 1
fi
echo "✅ $TAG 传完：https://gitee.com/$OWNER/$REPO/releases/tag/$TAG"
