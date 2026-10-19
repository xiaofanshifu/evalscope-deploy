#!/usr/bin/env bash
# 一键预下载 evalscope 评测数据集
# 用法: ./run_prefetch.sh
# 可选: CONTAINER=xxx ./run_prefetch.sh  # 手动指定容器名
#       SERVICE=xxx   ./run_prefetch.sh  # 指定 compose 服务名(默认 evalscope)

set -euo pipefail

WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${WORK_DIR}"

SERVICE="${SERVICE:-evalscope}"
SCRIPT="prefetch_datasets.py"
LOG="${WORK_DIR}/prefetch.log"

# 动态解析容器名，避免硬编码；容器名随 compose 项目名变化时仍可用
if [ -z "${CONTAINER:-}" ]; then
  CONTAINER="$(docker compose ps --format '{{.Name}}' "${SERVICE}" 2>/dev/null | head -n 1 || true)"
fi

if [ -z "${CONTAINER:-}" ]; then
  echo "[ERROR] 未能解析到服务 '${SERVICE}' 对应的容器。" >&2
  echo "        请确认已在本目录执行: docker compose ps" >&2
  echo "        或手动指定: CONTAINER=<容器名> $0" >&2
  exit 1
fi

if [ "$(docker inspect -f '{{.State.Running}}' "${CONTAINER}" 2>/dev/null || true)" != "true" ]; then
  echo "[ERROR] 容器 ${CONTAINER} 未运行，请先执行: docker compose up -d" >&2
  exit 1
fi

echo "[INFO] 目标容器: ${CONTAINER}"

docker cp "${WORK_DIR}/${SCRIPT}" "${CONTAINER}:/tmp/${SCRIPT}"

docker exec "${CONTAINER}" python "/tmp/${SCRIPT}" 2>&1 | tee "${LOG}"

echo ""
echo "[INFO] 日志已保存到 ${LOG}"
