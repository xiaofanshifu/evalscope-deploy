# 轻量文本评测镜像 - 支持 pip 官方包 / 源码两种安装方式
# 用途：文本基准评测 + 模型 API 压测 + Web 可视化（不含图像/视频/代码执行）

# 基础镜像抽成 ARG，升级 Python 只改这一处（3.12/3.10-slim 同为 Debian trixie，apt 源一致）
ARG BASE_IMAGE=python:3.12-slim
FROM ${BASE_IMAGE}

# 重新声明，使 BASE_IMAGE 在后续 LABEL 中可用
ARG BASE_IMAGE

# 安装方式：pip（PyPI 安装）| source（git 源码安装），由 deploy.sh 写入 override
ARG INSTALL_METHOD=pip
ARG EVALSCOPE_VERSION=1.12.0
ARG EVALSCOPE_REF=main
# 实际取值由 docker-compose.yaml 的 EVALSCOPE_PACKAGES 提供
ARG EVALSCOPE_PACKAGES=perf,service,ifeval,ifbench,openai_mrcr,needle_haystack

# 仅构建期可见，不写入镜像文件系统与运行时环境，但记录在镜像层历史（docker history 可见）
ARG HTTP_PROXY
ARG HTTPS_PROXY
ARG NO_PROXY

WORKDIR /workspace

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1 \
    PIP_DEFAULT_TIMEOUT=300 \
    PYTHONUNBUFFERED=1

# 必须用 LABEL+ARG：compose 的 build.labels 拿不到 build arg，会插值成空串
LABEL org.opencontainers.image.title="evalscope" \
      org.opencontainers.image.description="EvalScope 部署镜像（压测 perf + Web 可视化 service + 基准评测）" \
      org.opencontainers.image.base.name="${BASE_IMAGE}" \
      org.opencontainers.image.version="${EVALSCOPE_VERSION}" \
      org.opencontainers.image.revision="${EVALSCOPE_REF}" \
      io.evalscope.install.method="${INSTALL_METHOD}" \
      io.evalscope.packages="${EVALSCOPE_PACKAGES}"

# 改写 apt 镜像源（阿里云）——sed -i 替换现有源地址，不新增 sources 文件
RUN sed -i 's/deb.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list.d/debian.sources

# 设置 pip 全局 index（清华）
RUN pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple

# 最小化系统依赖（git/xz 为源码安装所需）
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl ca-certificates git xz-utils \
    && rm -rf /var/lib/apt/lists/*

# FAQ 中提到的预装依赖，避免编译失败
RUN pip install python-dotenv

# pip：PyPI 锁定版本；source：git 源码 + npm 构建前端 dist + editable 安装
# 依赖中仅提供 sdist 的包（如 polygon3）临时引入编译链，装完即清除（同层不增体积）
RUN set -e; \
    apt-get update; \
    apt-get install -y --no-install-recommends build-essential; \
    rm -rf /var/lib/apt/lists/*; \
    if [ "$INSTALL_METHOD" = "source" ]; then \
        ok=0; \
        for i in 1 2 3; do \
            git clone https://github.com/modelscope/evalscope.git /opt/evalscope && ok=1 && break; \
            echo "git clone failed (attempt $i), retrying in 5s..."; \
            rm -rf /opt/evalscope; sleep 5; \
        done; \
        [ "$ok" = "1" ]; \
        git -C /opt/evalscope checkout "${EVALSCOPE_REF}"; \
        curl -fsSL "https://registry.npmmirror.com/-/binary/node/v22.23.3/node-v22.23.3-linux-x64.tar.xz" -o /tmp/node.tar.xz; \
        tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1; \
        rm -f /tmp/node.tar.xz; \
        npm config set registry https://registry.npmmirror.com; \
        cd /opt/evalscope/evalscope/web; \
        npm install; \
        npm run build; \
        rm -rf node_modules; \
        npm cache clean --force; \
        pip install -e "/opt/evalscope[${EVALSCOPE_PACKAGES}]"; \
    else \
        pip install "evalscope[${EVALSCOPE_PACKAGES}]==${EVALSCOPE_VERSION}"; \
    fi; \
    apt-get purge -y build-essential >/dev/null; \
    apt-get autoremove -y >/dev/null; \
    rm -rf /var/lib/apt/lists/*; \
    evalscope --help >/dev/null 2>&1

# 上游未在任何 extra 声明 seqeval，pip 对未知 extra 静默跳过，故显式安装
RUN pip install seqeval

# 暴露可视化 Web 服务端口（容器内固定监听 80，宿主机映射端口由 compose 的 EVALSCOPE_HOST_PORT 配置）
EXPOSE 80

# 默认监听 0.0.0.0:80，输出目录指向 /workspace/outputs
CMD ["evalscope", "service", "--host", "0.0.0.0", "--port", "80", "--outputs", "/workspace/outputs"]
