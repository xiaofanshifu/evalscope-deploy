# EvalScope 轻量评测部署

## 定位

本项目用于**文本大模型的轻量级评测与性能压测**，基于 Docker 封装，提供开箱即用的 EvalScope Web 服务。

**支持**：

- **118 个**纯文本基准评测（知识 / 推理 / 数学 / 指令遵循 / 中文 / 长上下文 / 工具调用 / NER / 医疗等）
- 模型 API 性能压测
- Web 可视化任务管理与报告

**不支持**（刻意不提供，为了保持轻量）：

- 图像 / 视频 / 多模态评测（需要 torch/opencv，体积问题）
- 代码执行类基准（需 Docker Sandbox）
- Judge 模型类基准（需额外 Judge 服务）

这些能力需要 torch / opencv / Docker / 额外服务，会让镜像膨胀到数 GB，与本项目定位冲突。详见「不可用数据集」。

## 环境要求

- Docker Engine + Compose v2 插件（`docker compose version` 可验证）
- 宿主机安装 `git` 更佳（用于将分支/tag 解析为 commit sha 以精确刷新构建缓存）；未安装也能运行，会降级为直接使用原始 ref
- 首次构建需要访问 GitHub（source 模式）、PyPI 清华镜像、npm npmmirror 镜像

## 快速开始

```bash
bash deploy.sh source main
```

访问 `http://<host>:<port>/dashboard`（端口见「端口配置」）。

```bash
bash deploy.sh -h          # 帮助
bash deploy.sh source main # 源码最新版
bash deploy.sh 1.12.0      # pip 版
```

## 组件说明

pip 组件**固定**为 5 个，定义在 `docker-compose.yaml` 的 `EVALSCOPE_PACKAGES`，**不接受参数覆盖**：

| extra | 依赖 | 作用 |
|---|---|---|
| `perf` | fastapi / uvicorn / transformers 等 | 压测 + API 客户端 |
| `service` | flask / plotly / fastapi 等 | Web 可视化 |
| `ifeval` | langdetect + nltk | IFEval 指令遵循基准 |
| `ifbench` | emoji + syllapy + nltk | IFBench 指令遵循进阶基准 |
| `openai_mrcr` | tiktoken | OpenAI MRCR 长上下文基准 |

均为轻量包，无 torch / opencv 等重型依赖，镜像体积在百 MB 级。

> `all` 不是「全部」：上游 `pyproject.toml` 里 `all` 只等于 7 个 extra（含 torch、diffusers、opencv、langchain），会拉数 GB 依赖。本项目不使用它。

## 可用数据集（118 项）

全部**零运行时依赖**：无需 Judge、Sandbox、user_model 或任何外部服务。

### 推荐清单（21 项）

横向对比通用选型，覆盖 7 个维度、全部确定性打分：

```text
mmlu_pro,mmlu,gpqa_diamond,bbh,musr,math_500,gsm8k,process_bench,aime26,hmmt26,ifeval,ifbench,truthful_qa,ceval,cmmlu,cmath,arc_agi_2,longbench_v2,openai_mrcr,tool_bench,general_fc
```

| 能力 | 数据集 | 样本量 |
|---|---|---|
| 通用知识 | `mmlu_pro` | 12,032 |
| 通用知识 | `mmlu` | 14,042 |
| 高难知识 | `gpqa_diamond` | 198 |
| 逻辑推理 | `bbh` | 6,511 |
| 多步推理 | `musr` | 756 |
| 抽象推理 | `arc_agi_2` | 120 |
| 基础数学 | `gsm8k` | 1,319 |
| 竞赛数学 | `math_500` | 500 |
| 推理过程 | `process_bench` | 3,400 |
| 数学（竞赛） | `aime26` | 30 |
| 数学（竞赛） | `hmmt26` | 33 |
| 指令遵循 | `ifeval` | 541 |
| 指令遵循进阶 | `ifbench` | 300 |
| 真实性 | `truthful_qa` | 817 |
| 中文知识 | `ceval` | 1,346 |
| 中文多学科 | `cmmlu` | 11,582 |
| 中文数学 | `cmath` | 1,098 |
| 长文理解 | `longbench_v2` | 503 |
| 长文检索 | `openai_mrcr` | 2,400 |
| 工具调用 | `tool_bench` | 2,369 |
| 工具调用 | `general_fc` | 2,000 |

全量约 **60,000 请求/模型**。筛选阶段每项 `limit=500` 约 8,000 请求。

### 完整清单（按能力分类）

**知识 / 推理**

```text
mmlu                    14042    mmlu_pro               12032
mmlu_redux               5700    gpqa_diamond            198
super_gpqa             26529    hle                    2500
agieval                  8269    hellaswag              10042
hellaswag_hi            10042    commonsense_qa          1221
bbh                      6511    musr                     756
logi_qa                   651    drop                    9536
race                     4934    arc                     3548
arc_agi_2                 120    winogrande              1267
piqa                     1838    siqa                    1954
qasc                      926    sciq                    1000
trivia_qa                7993    kina                     899
coin_flip                3333    zebralogicbench         1000
arxivrollbench           3254    plawbench                280
```

**数学**

```text
math_500                 500    competition_math        5000
gsm8k                    1319    process_bench           3400
amc                       134    minerva_math             272
imo_answerbench           400    aime24                    30
aime25                     30    aime26                    30
hmmt25                     30    hmmt26                    33
hmmt_nov25                 30    docmath                  800
```

**指令遵循 / Agent 类（规则打分）**

```text
ifeval                    541    ifbench                  300
cl_bench                 1899    tool_bench              2369
general_fc               2000
perspective_gap_prompt_writing  220
perspective_gap_role_assignment  220
```

**长上下文 / 多轮**

```text
longbench_v2              503    openai_mrcr             2400
aa_lcr                     100    frames                   824
locomo                    1986    longmemeval              500
one_million_bench          400
```

**中文**

```text
ceval                    1346    cmmlu                  11582
cmath                    1098    iquiz                    120
maritime_bench           1888
```

**幻觉 / 真实性 / 医疗**

```text
truthful_qa               817    halueval              30000
pubmedqa                 1000    med_mcqa               4183
health_bench             3671    biomix_qa               306
mri_mcqa                  563
```

**NER（命名实体识别，约 25 项）**

```text
conll2003  3453    conllpp  3453    cross_ner  2506    broad_twitter_corpus  2000
wnut2017   1287    mit_restaurant 1521 mit_movie_trivia 1953 ncbi 940
ontonotes5 8262    tweebank_ner 1201 tweet_ner_7 3383    genia_ner 1854
harvey_ner 1303    jnlpba   3856    jnlpba_rare  465     fin_ner 305
bc2gm      5000    bc4chemd 26364   bc5cdr     4797    multi_nerd 167993
anat_em    3830
```

**多语言（可选）**

```text
arc_indic   12647   mgsm    2750    poly_math  9000    sanskriti  21726
indic_boolq 35970   indic_param 13207  milu     79608   mmmlu     196588
triviaqa_indic 197384   gsm8k_indic  27670
```

**自定义数据集（需自行提供数据）**

```text
data_collection   general_mcq   general_qa
```

### 不可用数据集

| 类别 | 数据集 | 缺什么 |
|---|---|---|
| 需额外 extra | `multi_if` `olympiad_bench` `needle_haystack` `arena_hard` `general_arena` `wmt24pp` `refcoco` `swe_bench_lite` `swe_bench_verified` `swe_bench_verified_mini` | 对应 pip extra |
| 需 Sandbox | `humaneval` `humaneval_plus` `live_code_bench` `mbpp` `mbpp_plus` `bigcodebench` `bigcodebench_hard` `multiple_humaneval` `multiple_mbpp` `scicode` | Docker |
| 需 Judge | `mt_bench` `simple_qa` `chinese_simpleqa` `alpaca_eval` `eq_bench` `drivel_writing` | Judge 服务 |
| 非文本 | `seed_tts_eval` | 音频模型 |

## 评测协议建议

### 通用设置

```
Temperature    0
Top P          1
Max Tokens     16384（长上下文批次用 8192）
重复次数       1
```

`Temperature=0` 时不要开重复次数——重复多次结果几乎一致，只浪费请求量。仅在用 `Temperature=1` 测采样稳定性时才对小数据集重复 3 次。

### 分批执行

一个数据集初始化失败会导致**整批终止**，建议分 3 批：

| 批次 | 数据集 | 批大小 | 超时 |
|---|---|---:|---:|
| 1 核心 | `mmlu_pro` `mmlu` `gpqa_diamond` `bbh` `musr` `math_500` `gsm8k` `process_bench` `aime26` `hmmt26` `ifeval` `ifbench` `truthful_qa` `ceval` `cmmlu` `cmath` `arc_agi_2` | 8 | 600 |
| 2 长上下文 | `longbench_v2` `openai_mrcr` | 1 | 1800 |
| 3 工具调用 | `tool_bench` `general_fc` | 4 | 600 |

### few-shot 配置

```json
{
  "mmlu_pro": {"few_shot_num": 5},
  "mmlu": {"few_shot_num": 5},
  "gpqa_diamond": {"few_shot_num": 0},
  "bbh": {"few_shot_num": 3},
  "musr": {"few_shot_num": 0},
  "math_500": {"few_shot_num": 0},
  "gsm8k": {"few_shot_num": 4},
  "process_bench": {"few_shot_num": 0},
  "aime26": {"few_shot_num": 0},
  "hmmt26": {"few_shot_num": 0},
  "ifeval": {"few_shot_num": 0},
  "ifbench": {"few_shot_num": 0},
  "truthful_qa": {"few_shot_num": 0},
  "ceval": {"few_shot_num": 5},
  "cmmlu": {"few_shot_num": 0},
  "cmath": {"few_shot_num": 0},
  "arc_agi_2": {"few_shot_num": 0},
  "longbench_v2": {"few_shot_num": 0},
  "openai_mrcr": {"few_shot_num": 0},
  "tool_bench": {"few_shot_num": 0},
  "general_fc": {"few_shot_num": 0}
}
```

> 上面是推荐清单的配置。若改用完整清单里的其他数据集，参考 `/benchmarks` 页面展示的默认 `few_shot_num`。

### 横向对比要求

所有被测模型必须保持一致：

- `few_shot_num` 按上表固定
- `Temperature=0`、`Top P=1`、`Max Tokens` 统一
- chat template 用各自模型默认，不做修改
- 答案解析用 EvalScope 默认，不做修改
- 记录 EvalScope commit SHA（`deploy.sh` 会把 `main` 解析成完整 SHA 并写入镜像 tag），不要用 `main` 字样

**推理模型建议双轨制**：统一模式（全部关闭思考）用于公平横比，最佳模式（各自推荐思考等级）用于部署选型。两套结果分开报告，不要混在一张表里。

**量化版对比**：同族 full vs quant 用同一协议，重点看各子集分数变化、答案格式成功率、截断率、输出长度变化。

## 需要完整评测环境？

图像、视频、代码执行、Judge 类基准需要 torch、opencv、Docker Sandbox、额外 Judge 服务，会让镜像膨胀到数 GB。

**建议在独立机器上直接安装 EvalScope，不要用容器**：

```bash
# 裸机 / 虚拟机（系统自带 Docker）
pip install "evalscope[all,ifeval,sandbox,openai_mrcr]"
evalscope service --host 0.0.0.0 --port 9000 --outputs ./outputs
```

裸机部署的好处：系统 Docker 直接可用，Sandbox 无需挂 socket 或另起远程 sandbox 服务，省掉容器方案里最麻烦的一环。

`all` 会拉入 torch / torchvision / diffusers / opencv / sentence-transformers / langchain / OpenCompass / VLMEvalKit 等，镜像或环境数 GB 级，**只适合一次性搭建的完整环境**，不适合日常轻量评测。

## 实现原理

所有切换本质都是**重新构建 Docker 镜像**，构建时按参数执行 pip 安装。

基础镜像为 `python:3.12-slim`，定义在 `Dockerfile` 顶部的 `ARG BASE_IMAGE`。

```
bash deploy.sh [方式] <版本号|git-ref>
    ↓
前置端口检查（外部占用则在修改配置前直接报错，服务不受影响）
    ↓
写入 docker-compose.override.yaml（安装方式、版本/ref、镜像 tag）
    ↓
docker compose up -d --build
    ↓
Dockerfile 按 INSTALL_METHOD 执行:
  pip    → pip install "evalscope[perf,service,ifeval,ifbench,openai_mrcr]==<版本号>"
  source → git clone + checkout <ref> + npm 构建前端 dist + pip install -e
    ↓
校验容器内版本 / commit + 健康检查（/health）
```

### 两种安装方式

| 方式 | 命令 | 版本含义 | 特点 |
|------|------|----------|------|
| **pip**（默认） | `pip install evalscope==<版本号>` | PyPI 上的固定版本快照 | 稳定、可复现 |
| **source** | `git clone` + `pip install -e .` | git 分支/tag/commit | 使用最新代码 |

source 模式会先用 `git ls-remote` 将 ref 解析为远端最新 commit sha 并写入构建参数——sha 变化会自动打破 Docker 构建缓存，保证拿到最新代码。

### 关键配置文件

| 文件 | 职责 |
|---|---|
| `deploy.sh` | 主脚本：解析参数、端口检查、写入 override、重建容器、校验结果 |
| `Dockerfile` | 通过 `ARG INSTALL_METHOD / EVALSCOPE_VERSION / EVALSCOPE_REF / EVALSCOPE_PACKAGES` 接收构建参数 |
| `docker-compose.yaml` | 稳定配置（端口、代理、卷、组件、restart）；`deploy.sh` **不修改此文件** |
| `docker-compose.override.yaml` | `deploy.sh` 每次部署整体重写的部署状态（安装方式、版本/ref、镜像 tag），已入 `.gitignore` |
| `.env` | 可选，配置代理与宿主机端口，已入 `.gitignore` |

### 镜像加速配置

构建内配置了三处镜像源以加速：

| 类型 | 镜像源 | 配置位置 |
|------|--------|----------|
| **apt 系统源** | 阿里云 | Dockerfile 中 `sed -i 's/deb.debian.org/mirrors.aliyun.com/g'` |
| **pip 源** | 清华 | Dockerfile 中 `pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple` |
| **npm / Node 源** | npmmirror | Dockerfile 中 npm registry 设置 + Node 二进制下载地址 |

依赖中存在仅提供 sdist 的包（如 polygon3），构建时会临时安装编译链、安装完成即清除，不增加镜像体积。

## 端口配置

容器内**固定监听 80**；宿主机映射端口默认 **80**，通过 `.env` 配置：

```bash
# .env —— 例：本环境固定为 9000
EVALSCOPE_HOST_PORT=9000
```

配置后访问 `http://localhost:9000/dashboard`；不配置则 `http://localhost/dashboard`。

端口占用处理规则：

| 占用者 | 行为 |
|--------|------|
| 本项目容器（升级/降级切换） | 正常放行，compose 自动先停旧容器再起新容器 |
| 外部 docker 容器 | **在修改配置前直接报错退出**，配置与运行中的服务均不受影响 |
| 宿主机进程 | 同上报错退出 |

即：端口被外部占用时绝不自动换端口，也绝不先停服务再失败。

服务为纯 HTTP，无 TLS。如需 HTTPS 请自行在前置反代（nginx/caddy）与证书。

## 可选代理

默认**不使用代理**。需要时在项目目录创建 `.env`：

```bash
echo 'EVALSCOPE_PROXY=http://192.168.110.99:7890' > .env
```

或临时指定（优先级高于 `.env`）：

```bash
EVALSCOPE_PROXY=http://192.168.110.99:7890 bash deploy.sh source main
```

代理作用于构建（git clone / pip / apt / npm）与运行时（拉取数据集）。评测过程中 NLTK 等资源也走该代理下载。

免代理地址用 `EVALSCOPE_NO_PROXY`（逗号分隔），默认 `localhost,127.0.0.1`：

```bash
# .env 里可写三个键
EVALSCOPE_HOST_PORT=9000
EVALSCOPE_PROXY=http://192.168.110.99:7890
EVALSCOPE_NO_PROXY=localhost,127.0.0.1,192.168.110.220
```

`.env` 的取值规则与 docker compose 一致：可加行内注释（`#` 前留一个空格）、单/双引号、去首尾空白。不支持 `export KEY=...` 写法。

GitHub 直连不稳定时脚本会优雅降级（`git ls-remote` 带 20s 超时与重试，不会卡死）。此情形下建议配置代理。

## 验证与运维

```bash
# 查看安装结果
docker compose exec -T evalscope pip show evalscope                    # pip 方式
docker compose exec -T evalscope git -C /opt/evalscope log -1           # source 方式

# 查看运行状态
docker compose ps
docker image ls | grep evalscope

# 生效的部署参数
docker compose config | grep -E 'INSTALL_METHOD:|EVALSCOPE_VERSION:|EVALSCOPE_REF:|EVALSCOPE_PACKAGES:|image:'
```

**警告**：不要使用 `docker compose down -v`，`-v` 会连缓存卷一起删除。

脚本每次执行后会自动校验版本/commit 与 `/health`，任一失败即报错退出。

注意：source 模式下 `pip show evalscope` 显示 `0.0.0.dev0` 属正常（开发版），以 git commit 为准。

### 镜像标识

```
evalscope:<版本号>              # pip 方式
evalscope:source-<commit前12位>  # source 方式
```

tag 记录在 `docker-compose.override.yaml` 的 `image:` 字段中。同一 ref 的重复执行会命中构建缓存。

镜像还带 OCI LABEL（`org.opencontainers.image.version` / `.revision` / `io.evalscope.packages` 等），可用 `docker image inspect` 读取。

### 构建预期

| 场景 | 耗时参考 |
|------|----------|
| 首次 source 构建（含 clone + npm + pip） | 约 4-5 分钟 |
| 已缓存的常规切换 | 约 1 分钟内 |
| 首次 pip 构建 | 约 1-2 分钟 |

组件固定为轻量集，不含 torch 等重型依赖。历史数据中 `all` 那套约需 15-25 分钟、镜像 4GB，本项目不使用该组合。

构建失败时**运行中的旧容器不受影响**，且 `deploy.sh` 会自动回滚 `docker-compose.override.yaml`，不会出现「配置指向新镜像、实际跑旧镜像」。

## 常用命令

```bash
# 部署/切换
bash deploy.sh source main
bash deploy.sh 1.12.0

# 启动/停止
docker compose up -d
docker compose down

# 校验
docker compose exec -T evalscope pip show evalscope
curl http://localhost:9000/health

# 查看生效配置
docker compose config | grep -E 'EVALSCOPE_PACKAGES|image:'
```

## 数据持久化

- `./outputs/` 挂载到容器内，评测结果不会因切换方式/版本丢失
- 缓存使用 Docker named volume，避免重复下载

## 常见问题

**Q: 提交任务报 `xxx not found. Please run pip install 'evalscope[yyy]'`？**

说明该数据集需要本项目未安装的 extra。见「不可用数据集」表格——图像/视频/代码/Judge 类请用裸机部署。

**Q: 一个数据集失败，整批都没结果？**

EvalScope 会先把所有 benchmark 构建完再开始推理，任一适配器初始化抛错就整体终止。建议分批提交，或先用 `limit=2` 冒烟。

**Q: `general_fc` / `tool_bench` 在自动补全里看不到？**

它们属于 agent 分类，UI 补全只列 text + multimodal，但输入框是自由文本，手动填入即可。建议先 `limit=2` 验证通路。

**Q: NER 类数据集（conll2003、wnut2017 等）能跑吗？**

能，纯规则打分无外部依赖。只有当你的业务涉及实体抽取时才需要跑，否则对通用文本模型对比意义不大。

**Q: `ifeval` 首次运行较慢？**

需要下载 NLTK 数据（`punkt_tab`），走配置的代理。属于正常现象，结果会缓存。
