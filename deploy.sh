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

# 从 .env 读一个键的值，语义与 docker compose 的 .env 解析对齐：
#   - 不加引号：剥离行内注释（# 前须有空白，compose 的规则），去首尾空白
#   - 单/双引号：取引号内内容，引号后的内容忽略
#   - export KEY=... 形式不支持（与 compose 不同，compose 支持；此处只取裸 KEY=）
# 不做变量插值（$VAR），本项目这两个键的值不含变量引用。
read_env_value() {
    local key="$1" file="$2" val=""
    [ -f "$file" ] || { printf '%s' ""; return 0; }
    val=$(sed -n "s/^[[:space:]]*${key}=//p" "$file" | head -1)
    # 注意：模式只匹配"以引号开头"，不能要求"以引号结尾" —— 否则 KEY="9000"  # 注释
    # 这种带尾部注释的写法会漏进下面的裸值分支，引号不会被剥掉
    case "$val" in
        \"*) val="${val#\"}"; val="${val%%\"*}" ;;
        \'*) val="${val#\'}"; val="${val%%\'*}" ;;
        *)    val=$(printf '%s' "$val" | sed 's/[[:space:]]#.*$//; s/^[[:space:]]*//; s/[[:space:]]*$//') ;;
    esac
    printf '%s' "$val"
}

# 加载 .env 配置（compose 自己也会读 .env，此处读取用于端口检查与提示；
# 已设置的环境变量优先）
if [ -f .env ]; then
    if [ -z "${EVALSCOPE_PROXY:-}" ]; then
        EVALSCOPE_PROXY="$(read_env_value EVALSCOPE_PROXY .env)"
        export EVALSCOPE_PROXY
    fi
    if [ -z "${EVALSCOPE_HOST_PORT:-}" ]; then
        EVALSCOPE_HOST_PORT="$(read_env_value EVALSCOPE_HOST_PORT .env)"
        export EVALSCOPE_HOST_PORT
    fi
    if [ -z "${EVALSCOPE_NO_PROXY:-}" ]; then
        EVALSCOPE_NO_PROXY="$(read_env_value EVALSCOPE_NO_PROXY .env)"
        export EVALSCOPE_NO_PROXY
    fi
fi
HOST_PORT="${EVALSCOPE_HOST_PORT:-80}"

usage() {
    cat <<EOF
用法: $(basename "$0") [方式] <版本号|git-ref>
       $(basename "$0") -h | --help

方式（首参，可省略，默认 pip）:
  pip     从 PyPI 安装指定版本，版本号精确锁定（如 1.12.0）
  source  从 GitHub 源码安装，第2个参数为 git 分支/tag/commit（如 main），默认取最新代码

本项目定位为**轻量文本评测部署**，pip 组件固定为:
  perf,service,ifeval,ifbench,openai_mrcr
组件定义在 docker-compose.yaml 的 EVALSCOPE_PACKAGES，**不接受参数覆盖**。
  - perf          压测 + API 客户端
  - service       Web 可视化
  - ifeval        langdetect + nltk（IFEval 指令遵循基准）
  - ifbench       emoji + syllapy + nltk（IFBench 指令遵循进阶）
  - openai_mrcr   tiktoken（OpenAI MRCR 长上下文基准）

  每次执行都是重新构建镜像 + 重建容器。组件参数不参与本次部署，
  因此同一 ref 的重复执行会命中构建缓存（源码方式首次约 12-20 分钟）。

  图像 / 视频 / 代码执行 / Judge 类基准需要 torch、opencv、Docker Sandbox、
  额外 Judge 服务，会让镜像膨胀到数 GB，本项目刻意不提供。
  如需完整评测环境，见 README「需要完整评测环境？」一节。

流程:
  1. 写入 docker-compose.override.yaml（安装方式、版本/ref、镜像 tag，compose 自动合并）
  2. 重建镜像并替换容器（outputs/ 数据不受影响）
  3. 校验容器内实际安装的版本/commit + 健康检查

可选代理: 在 .env 或环境变量设置 EVALSCOPE_PROXY=http://<host>:<port>，默认不使用代理
          免代理地址用 EVALSCOPE_NO_PROXY=<逗号分隔>，默认 localhost,127.0.0.1
          （供 git/pip/运行时使用，compose 从 .env 或环境变量直接读取）
端口:     容器内固定监听 80；宿主机映射端口默认 80，在 .env 中设置 EVALSCOPE_HOST_PORT 可更改
          目标端口被外部进程占用时会在修改配置前直接报错（切换本项目版本不受影响）
失败回滚: compose 校验或构建失败时自动恢复 docker-compose.override.yaml，
          运行中的旧容器不受影响，不会出现「配置指向新镜像、实际跑旧镜像」

示例:
  $(basename "$0") source main            # 源码安装 main 分支最新代码
  $(basename "$0") source v1.10.0         # 源码安装指定 tag/commit
  $(basename "$0") 1.12.0                 # 方式可省略，默认为 pip
  $(basename "$0") pip 1.12.0             # pip + 显式方式
EOF
}

# git ls-remote（带 20s 超时与 2 次重试，防止网络抖动导致脚本卡死）
# 若配置了 EVALSCOPE_PROXY 则走代理；全部失败时返回非零
git_lsremote() {
    local cmd=(git) i
    if [ -n "${EVALSCOPE_PROXY:-}" ]; then
        cmd=(git -c http.proxy="$EVALSCOPE_PROXY" -c https.proxy="$EVALSCOPE_PROXY")
    fi
    for i in 1 2; do
        timeout 20 "${cmd[@]}" ls-remote "$@" 2>/dev/null && return 0
        sleep 2
    done
    return 1
}

# 将分支/tag/commit 解析为完整 sha；失败输出空（回退直接使用原始 ref）
resolve_ref() {
    local ref="$1" sha="" out=""
    if [[ "$ref" =~ ^[0-9a-f]{7,40}$ ]]; then
        printf '%s' "$ref"
        return 0
    fi
    command -v git >/dev/null 2>&1 || return 0
    out=$(git_lsremote "$REPO_URL" "refs/heads/$ref") || return 0
    sha=$(printf '%s' "$out" | head -1 | awk '{print $1}')
    if [ -z "$sha" ]; then
        out=$(git_lsremote "$REPO_URL" "refs/tags/$ref") || return 0
        sha=$(printf '%s' "$out" | grep -v '\^{}' | head -1 | awk '{print $1}')
    fi
    if [ -z "$sha" ]; then
        out=$(git_lsremote "$REPO_URL" "$ref") || return 0
        sha=$(printf '%s' "$out" | head -1 | awk '{print $1}')
    fi
    printf '%s' "$sha"
}

# 前置端口检查：在修改任何配置之前执行，避免 compose 先停旧容器再因端口绑定失败导致服务中断
# 空闲/被本项目容器占用（切换版本场景）→ 放行；被外部占用 → 报错返回非零
check_port_free() {
    local port="$1" owner="" proj=""
    # 被某个运行中容器发布占用
    if command -v docker >/dev/null 2>&1; then
        owner=$(docker ps --filter "publish=$port" --format '{{.Names}}' 2>/dev/null | head -1) || owner=""
        if [ -n "$owner" ]; then
            proj=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' "$owner" 2>/dev/null) || proj=""
            if [ "$proj" = "${COMPOSE_PROJECT_NAME:-$(basename "$PWD")}" ]; then
                return 0  # 本项目容器，compose 会先停旧再起新
            fi
            echo "[switch] ✗ 端口 $port 已被外部容器 $owner 占用，未做任何更改" >&2
            echo "         更换端口: 在 .env 中设置 EVALSCOPE_HOST_PORT=<其他端口> 后重试" >&2
            return 1
        fi
    fi
    # 被宿主机进程占用
    if command -v ss >/dev/null 2>&1 && ss -Htln "sport = :$port" 2>/dev/null | grep -q .; then
        echo "[switch] ✗ 端口 $port 已被宿主机进程占用，未做任何更改" >&2
        echo "         更换端口: 在 .env 中设置 EVALSCOPE_HOST_PORT=<其他端口> 后重试" >&2
        return 1
    fi
    return 0
}

case "${1:-}" in
    -h|--help|help) usage; exit 0 ;;
    pip|source) METHOD="$1"; shift ;;
    "") usage >&2; exit 1 ;;
    *) METHOD="pip" ;;
esac

# 上面的 case 已把方式参数 shift 掉，因此此处必须正好剩 1 个（版本号|git-ref）
if [ $# -ne 1 ]; then
    echo "[switch] ✗ 只接受 2 个参数: [方式] <版本号|git-ref>" >&2
    echo "         组件固定在 docker-compose.yaml 的 EVALSCOPE_PACKAGES，不接受参数覆盖" >&2
    usage >&2
    exit 1
fi

if [ "$METHOD" = "pip" ]; then
    V="${1#v}"
    TAG="$V"
    echo "[switch] 方式: pip（PyPI 安装，版本锁定）"
    echo "[switch] 目标版本: $V"
else
    V="$1"
    RESOLVED="$(resolve_ref "$V")"
    if [ -n "$RESOLVED" ]; then
        REF_VALUE="$RESOLVED"
        TAG="source-${RESOLVED:0:12}"
        echo "[switch] 方式: source（GitHub 源码安装）"
        echo "[switch] 目标 ref: $V -> $RESOLVED"
    else
        REF_VALUE="$V"
        TAG="source-${V//\//-}"
        echo "[switch] 方式: source（GitHub 源码安装）"
        echo "[switch] 目标 ref: $V（未能解析为 sha，若远端未变可能命中构建缓存）"
    fi
fi
echo "[switch] 镜像 tag: evalscope:$TAG"
echo "[switch] 宿主机端口: $HOST_PORT"
[ -n "${EVALSCOPE_PROXY:-}" ] && echo "[switch] 代理: $EVALSCOPE_PROXY" || true

# 修改配置前先检查目标端口：外部占用直接报错（配置与运行中的服务均不受影响）
check_port_free "$HOST_PORT"

# 改写 override 之前先备份：compose config 校验或构建失败时回滚，
# 避免出现「override 指向新 tag、实际运行的却是旧镜像」的不一致状态
BACKUP="$(mktemp)"
if [ -f "$OVERRIDE" ]; then cp "$OVERRIDE" "$BACKUP"; else : > "$BACKUP"; fi
rollback_override() {
    cp "$BACKUP" "$OVERRIDE"
    rm -f "$BACKUP"
}

# 生成部署状态覆盖文件：compose 会自动与 docker-compose.yaml 合并
# 只写安装方式与版本/ref；EVALSCOPE_PACKAGES 故意不写 —— 组件固定在
# docker-compose.yaml 单一配置点，override 不参与，保证组件无法被部署参数影响
# 当前方式用不到的参数写空串，不留看起来仍在使用的值
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
if ! COMPOSE_CONFIG="$(docker compose config 2>&1)"; then
    rollback_override
    echo "[switch] ✗ compose 配置校验失败，已回滚 $OVERRIDE，未做任何更改" >&2
    printf '%s\n' "$COMPOSE_CONFIG" | tail -5 >&2
    exit 1
fi
printf '%s\n' "$COMPOSE_CONFIG" | grep -E 'INSTALL_METHOD:|EVALSCOPE_VERSION:|EVALSCOPE_REF:|EVALSCOPE_PACKAGES:|image:'
echo "[switch] compose 配置校验通过"

if ! docker compose up -d --build; then
    rollback_override
    echo "[switch] ✗ 构建/启动失败，已回滚 $OVERRIDE" >&2
    echo "         运行中的旧容器未受影响，服务照常；修掉问题后重新执行本脚本即可" >&2
    exit 1
fi
rm -f "$BACKUP"

# 校验容器内实际安装结果
if [ "$METHOD" = "pip" ]; then
    ACTUAL=$(docker compose exec -T evalscope pip show evalscope 2>/dev/null | awk '/^Version/{print $2}') || ACTUAL=""
    if [ "$ACTUAL" = "$V" ]; then
        echo "[switch] ✓ 完成，容器内 evalscope = $ACTUAL"
    else
        echo "[switch] ✗ 版本不符: 预期 $V, 实际 ${ACTUAL:-未安装}" >&2
        exit 1
    fi
else
    ACTUAL_SHA=$(docker compose exec -T evalscope git -C /opt/evalscope rev-parse HEAD 2>/dev/null) || ACTUAL_SHA=""
    if [ -n "$RESOLVED" ]; then
        if [ "$ACTUAL_SHA" = "$RESOLVED" ]; then
            echo "[switch] ✓ 完成，容器内源码 commit = $ACTUAL_SHA"
        else
            echo "[switch] ✗ commit 不符: 预期 $RESOLVED, 实际 ${ACTUAL_SHA:-未知}" >&2
            exit 1
        fi
    else
        if [ -n "$ACTUAL_SHA" ] && docker compose exec -T evalscope evalscope --version >/dev/null 2>&1; then
            echo "[switch] ✓ 完成，容器内源码 commit = $ACTUAL_SHA（ref 未解析，仅校验可运行）"
        else
            echo "[switch] ✗ 校验失败: 容器内 evalscope 不可用" >&2
            exit 1
        fi
    fi
fi

# 健康检查：等待服务就绪并确认端口可达
if command -v curl >/dev/null 2>&1; then
    healthy=""
    for _ in $(seq 1 15); do
        if curl -sf -o /dev/null --connect-timeout 2 "http://localhost:$HOST_PORT/health"; then
            healthy=1
            break
        fi
        sleep 2
    done
    if [ -z "$healthy" ]; then
        echo "[switch] ✗ 服务健康检查失败: http://localhost:$HOST_PORT/health" >&2
        exit 1
    fi
    echo "[switch] ✓ 服务就绪: http://localhost:$HOST_PORT/dashboard"
else
    echo "[switch] ⚠ 宿主机未找到 curl，已跳过健康检查（部署已执行，但服务可用性未验证）" >&2
fi
