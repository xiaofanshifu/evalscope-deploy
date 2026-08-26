#!/usr/bin/env bash
# 切换 evalscope 版本：自动同步 docker-compose.yaml 中的版本号并重建容器
# 用法: ./switch-version.sh <版本号>   例如 ./switch-version.sh 1.12.0
set -euo pipefail
cd "$(dirname "$0")"

usage() {
    cat <<EOF
用法: $(basename "$0") <版本号>
       $(basename "$0") -h | --help

切换 evalscope 版本：
  1. 同步修改 docker-compose.yaml 中的 build arg 与镜像 tag 版本号
  2. 重建镜像并替换容器（outputs/ 数据不受影响）
  3. 校验容器内实际安装的 evalscope 版本

示例:
  $(basename "$0") 1.12.0    # 切换到 1.12.0
EOF
}

case "${1:-}" in
    -h|--help|help) usage; exit 0 ;;
    "") usage >&2; exit 1 ;;
esac

if [ $# -ne 1 ]; then
    echo "[switch] ✗ 只接受一个参数: 版本号" >&2
    usage >&2
    exit 1
fi

V="${1#v}"

echo "[switch] 目标版本: $V"

# 同步 build arg 与镜像 tag 两处版本号
sed -i \
    -e "s|^\([[:space:]]*EVALSCOPE_VERSION:\).*|\1 \"$V\"|" \
    -e "s|^\([[:space:]]*image: \).*evalscope.*|\1\"evalscope:$V\"|" \
    docker-compose.yaml

grep -nE 'EVALSCOPE_VERSION:|image:' docker-compose.yaml

docker compose config >/dev/null && echo "[switch] compose 配置校验通过"
docker compose up -d --build

# 确认容器内版本与预期一致
ACTUAL=$(docker exec evalscope pip show evalscope 2>/dev/null | awk '/^Version/{print $2}')
if [ "$ACTUAL" = "$V" ]; then
    echo "[switch] ✓ 完成，容器内 evalscope = $ACTUAL"
else
    echo "[switch] ✗ 版本不符: 预期 $V, 实际 $ACTUAL" >&2
    exit 1
fi

