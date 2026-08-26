# 轻量级原版 evalscope 镜像 - 官方 pip 安装
# 仅用于压测(perf)/评测模型 API + Web 可视化(service)
FROM python:3.10-slim

# evalscope 版本号（切换版本改 docker-compose.yaml 里的 EVALSCOPE_VERSION 即可）
ARG EVALSCOPE_VERSION=1.11.0

WORKDIR /workspace

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1 \
    PIP_DEFAULT_TIMEOUT=300 \
    PYTHONUNBUFFERED=1

# 最小化系统依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# pip 源镜像
RUN pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple

# FAQ 中提到的预装依赖，避免编译失败
RUN pip install python-dotenv

# 安装 perf（压测）+ service（WebUI），锁定版本保证可复现构建
RUN pip install "evalscope[perf,service]==${EVALSCOPE_VERSION}" && \
    evalscope --help >/dev/null 2>&1 || true

# 暴露可视化 Web 服务端口
EXPOSE 9000

# 默认监听 0.0.0.0:9000，输出目录指向 /workspace/outputs
CMD ["evalscope", "service", "--host", "0.0.0.0", "--port", "9000", "--outputs", "/workspace/outputs"]

