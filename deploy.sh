#!/usr/bin/env bash
# deploy.sh - 部署/切换 evalscope：生成部署状态覆盖文件后重建容器
# 用法: ./deploy.sh [方式] <版本号|git-ref>
#   方式: pip（默认，PyPI 指定版本）| source（git 源码，可得最新代码）
#   组件: 固定在 docker-compose.yaml 的 EVALSCOPE_PACKAGES，不通过参数修改
set -euo pipefail
cd "$(dirname "$0")"

REPO_URL="https://github.com/modelscope/evalscope.git"

# 部署状态覆盖文件（compose 自动与 docker-compose.yaml 合并）
OVERRIDE="docker-compose.override.yaml"

log()  { printf '%s %s\n'  "$(date '+%H:%M:%S')" "$*"; }
warn() { printf '%s %s\n'  "$(date '+%H:%M:%S')" "$*" >&2; }

# 宿主机端口与构建代理取 docker compose config 的输出 —— 那是 compose 自己解析完
# .env 后的最终结果，脚本不再自己实现一套 .env 解析规则
CFG="$(docker compose config 2>/dev/null || true)"
BUILD_PROXY="$(printf '%s' "$CFG" | awk '/HTTP_PROXY:/{sub(/^[^:]*: */,""); gsub(/"/,""); print; exit}')"
HOST_PORT="$(printf '%s' "$CFG" | awk '/published:/{sub(/^[^:]*: */,""); gsub(/"/,""); print; exit}')"
HOST_PORT="${HOST_PORT:-80}"

usage() {
    cat <<EOF
用法: $(basename "$0") [方式] <版本号|git-ref>
       $(basename "$0") -h | --help

方式（首参，可省略，默认 pip）:
  pip     从 PyPI 安装指定版本，版本号精确锁定（如 1.12.0）
  source  从 GitHub 源码安装，第2个参数为 git 分支/tag/commit（如 main），默认取最新代码

组件固定为 perf,service,ifeval,ifbench,openai_mrcr,needle_haystack
（定义在 docker-compose.yaml 的 EVALSCOPE_PACKAGES，不接受参数覆盖）

配置构建代理: .env 设 EVALSCOPE_BUILD_PROXY=http://<host>:<port>
              绕过代理: EVALSCOPE_NO_PROXY=<逗号分隔地址>

端口: 容器内固定 80；宿主机端口 .env 设 EVALSCOPE_HOST_PORT（默认 80）

示例:
  $(basename "$0") source main            # 源码安装 main 分支最新代码
  $(basename "$0") source v1.10.0         # 源码安装指定 tag/commit
  $(basename "$0") 1.12.0                 # 方式可省略，默认为 pip
  $(basename "$0") pip 1.12.0             # pip + 显式方式
  EVALSCOPE_BUILD_PROXY=http://192.168.110.99:7890 $(basename "$0") source main
                                          # 临时指定构建代理（优先于 .env）
EOF
}

# hex sha 截 7 位，分支/tag 名不截断（否则 release_v2 会被砍成 release）
sanitize_ref() {
    local r
    r=$(printf '%s' "$1" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9._-' '-' | sed 's/^[^a-z0-9]*//')
    if [[ "$1" =~ ^[0-9a-fA-F]{7,40}$ ]]; then
        r="${r:0:7}"
    fi
    printf '%s' "$r"
}

# 把 ref 解析为 commit sha（作为构建参数让 Docker 按 sha 决定缓存是否失效）；
# 输出为空表示拿不到，由调用方报错退出
resolve_ref() {
    local ref="$1" out=""
    if [[ "$ref" =~ ^[0-9a-f]{7,40}$ ]]; then
        printf '%s' "$ref"
        return 0
    fi
    command -v git >/dev/null 2>&1 || return 1
    if [ -n "$BUILD_PROXY" ]; then
        out=$(git -c http.proxy="$BUILD_PROXY" -c https.proxy="$BUILD_PROXY" \
              ls-remote "$REPO_URL" "refs/heads/$ref" "refs/tags/$ref" "refs/tags/$ref^{}" 2>/dev/null)
    else
        out=$(git ls-remote "$REPO_URL" "refs/heads/$ref" "refs/tags/$ref" "refs/tags/$ref^{}" 2>/dev/null)
    fi
    printf '%s' "$out" | awk '$2 ~ /\^\{\}$/ {p=$1} !/\^\{\}$/ {n=$1} END {print (p?p:n)}'
    return 0    # 必须返回 0：命令替换下非 0 会被 set -e 直接终止
}

case "${1:-}" in
    -h|--help|help) usage; exit 0 ;;
    pip|source) METHOD="$1"; shift ;;
    "") usage >&2; exit 1 ;;
    *) METHOD="pip" ;;
esac

if [ $# -ne 1 ]; then
    warn "[switch] ✗ 只接受 2 个参数: [方式] <版本号|git-ref>"
    warn "         组件固定在 docker-compose.yaml 的 EVALSCOPE_PACKAGES，不接受参数覆盖"
    usage >&2
    exit 1
fi

if [ "$METHOD" = "pip" ]; then
    V="$1"
    TAG="$V"
    log "[switch] 方式: pip（PyPI 安装，版本锁定）"
    log "[switch] 目标版本: $V"
else
    V="$1"
    if ! command -v git >/dev/null 2>&1; then
        warn "[switch] ✗ source 方式需要 git（用于查询 $V 对应的最新 commit），未做任何更改"
        exit 1
    fi
    t0=$(date +%s)
    RESOLVED="$(resolve_ref "$V")"
    log "[done] git ls-remote 解析 ref — 耗时=$(($(date +%s) - t0))s"
    if [ -z "$RESOLVED" ]; then
        # 拿不到 sha 就直接退出，不降级用原始 ref：
        # 降级会让构建参数从 sha 变成 ref，击穿构建缓存触发全量重建，
        # 而重建时容器内的 git clone 面对的是同一个网络，多半再失败一次。
        warn "[switch] ✗ 拿不到 $V 对应的 commit，未做任何更改"
        warn "         GitHub 直连不稳定时会超时，重试可能成功；持续失败则配置构建代理:"
        warn "           EVALSCOPE_BUILD_PROXY=http://<host>:<port> bash deploy.sh source $V"
        warn "         也可能是该 ref 不存在，可先确认:"
        warn "           git ls-remote $REPO_URL | grep $V"
        exit 1
    fi
    REF_VALUE="$RESOLVED"
    TAG="source-$(sanitize_ref "$V")"
    log "[switch] 方式: source（GitHub 源码安装，拉取最新）"
    log "[switch] 目标 ref: $V -> $RESOLVED"
fi
log "[switch] 镜像 tag: evalscope:$TAG"
log "[switch] 宿主机端口: $HOST_PORT"
[ -n "$BUILD_PROXY" ] && log "[switch] 构建代理: $BUILD_PROXY" || true

# 仅 compose 校验 / 构建失败时回滚 override，避免配置与运行镜像不一致
BACKUP="$(mktemp)"
if [ -f "$OVERRIDE" ]; then cp "$OVERRIDE" "$BACKUP"; else : > "$BACKUP"; fi
rollback_override() {
    [ -f "$BACKUP" ] && cp "$BACKUP" "$OVERRIDE"
    rm -f "$BACKUP"
    return 0
}
# 构建期间 Ctrl-C / kill 同样触发回滚（不捕 EXIT：错误路径已显式回滚）
trap 'rollback_override' INT TERM

# 只写安装方式与版本/ref；组件固定在 docker-compose.yaml，不接受部署参数
if [ "$METHOD" = "pip" ]; then
    OVERRIDE_ARGS="        EVALSCOPE_VERSION: \"$V\"
        EVALSCOPE_REF: \"\"  # pip 方式不使用"
else
    OVERRIDE_ARGS="        EVALSCOPE_VERSION: \"\"  # source 方式不使用
        EVALSCOPE_REF: \"$REF_VALUE\""
fi

cat > "$OVERRIDE" <<EOF
# 由 deploy.sh 生成，勿手改
services:
  evalscope:
    build:
      args:
        INSTALL_METHOD: "$METHOD"
$OVERRIDE_ARGS
    image: "evalscope:$TAG"
EOF

# 校验合并后的 compose 配置并打印生效的部署参数（base 默认值 + 本次部署覆盖）
_t0=$(date +%s)
log "[run ] 校验 compose 配置"
log "[cmd ] docker compose config"
if ! COMPOSE_CONFIG="$(docker compose config 2>&1)"; then
    log "[done] 校验 compose 配置 — 失败 耗时=$(($(date +%s) - _t0))s"
    rollback_override
    warn "[switch] ✗ compose 配置校验失败，已回滚 $OVERRIDE，未做任何更改"
    printf '%s\n' "$COMPOSE_CONFIG" | tail -5 >&2
    exit 1
fi
log "[done] 校验 compose 配置 — 退出码=0 耗时=$(($(date +%s) - _t0))s"
printf '%s\n' "$COMPOSE_CONFIG" | grep -E 'INSTALL_METHOD:|EVALSCOPE_VERSION:|EVALSCOPE_REF:|EVALSCOPE_PACKAGES:|image:'
log "[switch] compose 配置校验通过"

_t0=$(date +%s)
log "[run ] 构建镜像"
log "[cmd ] docker compose build"
if ! docker compose build; then
    log "[done] 构建镜像 — 失败 耗时=$(($(date +%s) - _t0))s"
    rollback_override
    warn "[switch] ✗ 构建失败，已回滚 $OVERRIDE"
    warn "         目标镜像 evalscope:$TAG 未生成；旧容器未受影响，服务照常"
    exit 1
fi
log "[done] 构建镜像 — 退出码=0 耗时=$(($(date +%s) - _t0))s"

# 构建与启动分开，以区分「构建失败（回滚）」与「启动失败（不回滚）」
_t0=$(date +%s)
log "[run ] 替换容器"
log "[cmd ] docker compose up -d"
if ! docker compose up -d; then
    log "[done] 替换容器 — 失败 耗时=$(($(date +%s) - _t0))s"
    warn "[switch] ✗ 镜像已构建完成，容器未启动（未回滚 $OVERRIDE）"
    warn "         镜像    evalscope:$TAG"
    if _img="$(docker images "evalscope:$TAG" --format '{{.Size}}   built {{.CreatedSince}}' 2>/dev/null | head -1)" && [ -n "$_img" ]; then
        warn "         状态    $_img"
    fi
    if _rev="$(docker inspect "evalscope:$TAG" --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' 2>/dev/null)"; then
        [ -n "$_rev" ] && warn "         commit  ${_rev:0:12}"
    fi
    if _pkg="$(docker inspect "evalscope:$TAG" --format '{{index .Config.Labels "io.evalscope.packages"}}' 2>/dev/null)"; then
        [ -n "$_pkg" ] && warn "         组件    $_pkg"
    fi
    warn "         最常见原因：宿主机端口 $HOST_PORT 已被占用"
    warn "         处理后执行 docker compose up -d 即可，无需重新构建"
    exit 1
fi
log "[done] 替换容器 — 退出码=0 耗时=$(($(date +%s) - _t0))s"
trap - INT TERM
rm -f "$BACKUP"

# 校验容器内实际安装结果
if [ "$METHOD" = "pip" ]; then
    ACTUAL=$(docker compose exec -T evalscope pip show evalscope 2>/dev/null | awk '/^Version/{print $2}') || ACTUAL=""
    if [ "$ACTUAL" = "$V" ]; then
        log "[switch] ✓ 完成，容器内 evalscope = $ACTUAL"
    else
        # 不回滚：override 与容器已同时指向新镜像，回滚配置无法修正已运行的内容
        warn "[switch] ✗ 版本不符: 预期 $V, 实际 ${ACTUAL:-未安装}"
        warn "         当前状态：容器已用镜像 evalscope:$TAG 启动，但内容不是预期版本"
        warn "         $OVERRIDE 也已指向该镜像。需人工排查镜像内容后重新部署"
        exit 1
    fi
else
    ACTUAL_SHA=$(docker compose exec -T evalscope git -C /opt/evalscope rev-parse HEAD 2>/dev/null) || ACTUAL_SHA=""
    if [ "$ACTUAL_SHA" = "$RESOLVED" ]; then
        log "[switch] ✓ 完成，容器内源码 commit = $ACTUAL_SHA"
    else
        warn "[switch] ✗ commit 不符: 预期 $RESOLVED, 实际 ${ACTUAL_SHA:-未知}"
        warn "         当前状态：容器已用镜像 evalscope:$TAG 启动，但内容不是预期 commit"
        warn "         $OVERRIDE 也已指向该镜像。需人工排查镜像内容后重新部署"
        exit 1
    fi
fi

# 不验证应用就绪：容器起即视为部署完成，可用性由使用者确认
log "[switch] 访问地址: http://localhost:$HOST_PORT/dashboard"
