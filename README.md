# 一、[EvalScope](https://github.com/modelscope/evalscope) 轻量评测部署

## 1.1 定位

本项目用于**文本大模型的轻量级评测与性能压测**，基于 Docker 封装，提供开箱即用的 [EvalScope](https://github.com/modelscope/evalscope) 服务。

**支持**：纯文本基准评测（知识 / 推理 / 数学 / 指令遵循 / 中文 / 长上下文 / 工具调用 / NER / 医疗等）、模型 API 性能压测、Web 可视化任务管理与报告。

**不支持**：图像 / 视频 / 多模态（需 torch/opencv）、代码执行类基准（需 Docker Sandbox）、Judge 模型类基准（需额外 Judge 服务）。这些能力会让镜像膨胀到数 GB，与轻量定位冲突；完整环境见 4.2。

## 1.2 环境要求

- Docker Engine + Compose v2 插件（`docker compose version` 可验证）
- `source` 方式需要宿主机安装 `git`（用于查询 ref 对应的最新 commit）
- 首次构建需要访问 GitHub（source 模式）、PyPI 清华镜像、npm npmmirror 镜像

# 二、部署

## 2.1 快速开始

端口和代理都可跳过，默认端口 80。配置写在项目根目录 `.env`，三个键均可选：

```bash
# .env
# 宿主机端口，默认 80；容器内固定 80
EVALSCOPE_HOST_PORT=9000
# 仅构建用（git/pip/apt/npm），运行时直连
EVALSCOPE_BUILD_PROXY=http://192.168.110.99:7890
# 不走代理的地址
EVALSCOPE_NO_PROXY=localhost,127.0.0.1
```

命令行临时代理优先于 `.env`，GitHub 直连不稳定，建议配置：

```bash
./deploy.sh -h
EVALSCOPE_BUILD_PROXY=http://192.168.110.99:7890 ./deploy.sh source main
./deploy.sh 1.12.0      # pip 版
```

执行流程：写入 override → 校验 compose 配置 → 构建镜像 → 替换容器 → **校验容器内实际版本/commit**。构建完成后也可执行 `docker compose up -d` 启动服务。构建反复失败时，可先执行 `docker builder prune --all --force` 清理构建缓存。

## 2.2 组件说明

pip 组件**固定**为 6 个，定义在 `docker-compose.yaml` 的 `EVALSCOPE_PACKAGES`：

| extra | 依赖 | 作用 |
|---|---|---|
| `perf` | fastapi / uvicorn / transformers 等 | 压测 + API 客户端 |
| `service` | flask / plotly / fastapi 等 | Web 可视化 |
| `ifeval` | langdetect + nltk | IFEval 指令遵循基准 |
| `ifbench` | emoji + syllapy + nltk | IFBench 指令遵循进阶基准 |
| `openai_mrcr` | tiktoken | OpenAI MRCR 长上下文基准 |
| `needle_haystack` | matplotlib + seaborn | 大海捞针基准，精确指定上下文长度的数据集 |

> 注意：`all` 不是「全部」。上游 `pyproject.toml` 里 `all` 只等于 7 个 extra（含 torch、diffusers、opencv、langchain），会拉数 GB 依赖。

# 三、使用

## 3.1 可用数据集

除需 LLM Judge 的基准外，其余均零运行时依赖：无需 Sandbox、user_model 或任何外部服务。

### 3.1.1 推荐清单

横向对比通用选型，覆盖 7 个维度、全部确定性打分；样本量见 3.1.2。可直接复制到 `--datasets`：

```text
gsm8k cmath truthful_qa ifeval mmlu ceval cmmlu bbh mmlu_pro general_fc ifbench math_500 tool_bench musr process_bench gpqa_diamond openai_mrcr longbench_v2 aime26 hmmt26 arc_agi_2
```

### 3.1.2 完整清单（按能力分类）

| 能力 | 数据集 | 样本量 | 数据集 | 样本量 |
|---|---|---:|---|---:|
| **知识 / 推理** | `mmlu` | 14042 | `mmlu_pro` | 12032 |
|  | `mmlu_redux` | 5700 | `gpqa_diamond` | 198 |
|  | `super_gpqa` | 26529 | `agieval` | 8269 |
|  | `hellaswag` | 10042 | `hellaswag_hi` | 10042 |
|  | `commonsense_qa` | 1221 | `bbh` | 6511 |
|  | `musr` | 756 | `logi_qa` | 651 |
|  | `drop` | 9536 | `race` | 4934 |
|  | `arc` | 3548 | `arc_agi_2` | 120 |
|  | `winogrande` | 1267 | `piqa` | 1838 |
|  | `siqa` | 1954 | `qasc` | 926 |
|  | `sciq` | 1000 | `trivia_qa` | 7993 |
|  | `kina` | 899 | `coin_flip` | 3333 |
|  | `zebralogicbench` | 1000 | `arxivrollbench` | 3254 |
| **数学** | `math_500` | 500 | `competition_math` | 5000 |
|  | `gsm8k` | 1319 | `process_bench` | 3400 |
|  | `amc` | 134 | `aime24` | 30 |
|  | `aime25` | 30 | `aime26` | 30 |
|  | `hmmt25` | 30 | `hmmt26` | 33 |
|  | `hmmt_nov25` | 30 | | |
| **代码生成** | `humaneval` | 164 | `humaneval_plus` | 164 |
|  | `scicode` | 65 | `eq_bench` | 171 |
| **指令遵循 / Agent（规则打分）** | `ifeval` | 541 | `ifbench` | 300 |
|  | `tool_bench` | 2369 | `general_fc` | 2000 |
| **长上下文 / 多轮** | `longbench_v2` | 503 | `openai_mrcr` | 2400 |
|  | `locomo` | 1986 | `needle_haystack` | 按 context_lengths × depth 生成 |
| **中文** | `ceval` | 1346 | `cmmlu` | 11582 |
|  | `cmath` | 1098 | `iquiz` | 120 |
|  | `maritime_bench` | 1888 | | |
| **幻觉 / 真实性 / 医疗** | `truthful_qa` | 817 | `halueval` | 30000 |
|  | `pubmedqa` | 1000 | `med_mcqa` | 4183 |
|  | `biomix_qa` | 306 | `mri_mcqa` | 563 |
| **NER（命名实体识别，21 项）** | `conll2003` | 3453 | `conllpp` | 3453 |
|  | `cross_ner` | 2506 | `broad_twitter_corpus` | 2000 |
|  | `wnut2017` | 1287 | `mit_restaurant` | 1521 |
|  | `mit_movie_trivia` | 1953 | `ncbi` | 940 |
|  | `ontonotes5` | 8262 | `tweebank_ner` | 1201 |
|  | `tweet_ner_7` | 3383 | `genia_ner` | 1854 |
|  | `harvey_ner` | 1303 | `jnlpba` | 3856 |
|  | `jnlpba_rare` | 465 | `fin_ner` | 305 |
|  | `bc2gm` | 5000 | `bc4chemd` | 26364 |
|  | `bc5cdr` | 4797 | `multi_nerd` | 167993 |
|  | `anat_em` | 3830 | | |
| **多语言（可选）** | `arc_indic` | 12647 | `mgsm` | 2750 |
|  | `poly_math` | 9000 | `sanskriti` | 21726 |
|  | `indic_boolq` | 35970 | `indic_param` | 13207 |
|  | `milu` | 79608 | `mmmlu` | 196588 |
|  | `triviaqa_indic` | 197384 | `gsm8k_indic` | 27670 |
| **自定义（需自行提供数据）** | `data_collection` / `general_mcq` / `general_qa` | 需自备 | | |

> 代码生成类基准**不在沙箱中**执行模型生成的代码，注意隔离。

## 3.2 评估命令（CLI）

最小命令只需 `--model`、`--api-url`、`--datasets` 三个参数；完整模板：

```bash
EVALSCOPE_LANGUAGE=zh \
evalscope eval \
  --model Qwen3.8-27B \
  --model-id Qwen3.8-27B-demo \
  --api-url http://192.168.110.224:8000/v1 \
  --api-key EMPTY \
  --eval-type openai_api \
  --datasets gsm8k cmath truthful_qa ifeval mmlu ceval cmmlu bbh mmlu_pro general_fc ifbench math_500 tool_bench musr process_bench gpqa_diamond openai_mrcr longbench_v2 aime26 hmmt26 arc_agi_2 \
  --limit 50 \
  --repeats 2 \
  --eval-batch-size 10 \
  --generation-config '{"temperature":0.8,"top_p":0.95,"max_tokens":16384,"timeout":1800,"retries":5,"retry_interval":10,"stream":true,"seed":42,"reasoning_effort":"high"}' \
  --work-dir /workspace/outputs/qwen38_common_demo \
  --no-timestamp \
  --enable-progress-tracker \
  --ignore-errors \
  --seed 42
```

| 参数 | 作用 |
|---|---|
| `--model-id` / `--api-key` | 报告展示的模型名；API 密钥，本地服务通常传 `EMPTY` |
| `--eval-type` | 评测类型，可省略，显式指定更清晰 |
| `--limit` / `--repeats` | 每个 subset 取前 N 条（`0.1` 表示 10%）；每个样本重复推理次数 |
| `--eval-batch-size` / `--generation-config` | API 模式并发请求数；采样、超时、重试、流式、reasoning 参数 |
| `--work-dir` / `--no-timestamp` | 固定输出目录，方便脚本管理 |
| `--enable-progress-tracker` / `--ignore-errors` | 写入 `progress.json` 供 Web 查进度；单条样本失败不终止整个任务 |
| `--seed` / `--use-cache` | 随机种子，默认 42；复用旧目录 predictions / reviews，继续跑剩余数据集 |

> `Temperature=0` 时不要开重复次数——重复多次结果几乎一致，只浪费请求量。仅在用 `Temperature≠0` 测采样稳定性时才对小数据集重复。

## 3.3 评测协议建议

### 3.3.1 长上下文

三个可用基准：

| 数据集 | 语料 | 长度可控 |
|---|---|---|
| `longbench_v2` | 真实长文档 | ❌ adapter 无上限参数，子集名不代表长度，危险样本藏在 `short` 子集 |
| `openai_mrcr` | 真实多轮对话 | ❌ 只能按固定 8 档筛选；下载需整仓拉取（GB 级） |
| `needle_haystack` | 合成（自拼散文 + 插 needle） | ✅ 唯一能精确指定 |

`needle_haystack` 配置示例（`min=max=L, num_intervals=1` 即恰好 L；`num_intervals` 走等差插值，只能取等差序列）：

```json
"dataset_args": {"needle_haystack": {"subset_list": ["english"], "extra_params": {
  "context_lengths_min": 200000, "context_lengths_max": 300000, "context_lengths_num_intervals": 3,
  "document_depth_percent_min": 0, "document_depth_percent_max": 100, "document_depth_percent_intervals": 10,
  "tokenizer_path": "<被测模型自己的 tokenizer id>", "show_score": true
}}}
```

### 3.3.2 1M 上下文实测

`Qwen3.8-27B`（vLLM）实测：`max_model_len=1,010,000`，输入 `999,597` tokens，50% 深度单针检索正确，`acc=100%`，耗时 `797.7s`。以下命令在 `/data/evalscope` 下执行：

```bash
docker compose exec -T evalscope evalscope eval \
  --model Qwen3.8-27B \
  --api-url http://192.168.110.232:8000/v1 \
  --eval-type openai_api \
  --datasets needle_haystack \
  --dataset-args '{"needle_haystack":{"subset_list":["english"],"extra_params":{"retrieval_question":"What is the secret passcode? Answer with the passcode only.","needles":["BLUE-FALCON-7391"],"context_lengths_min":990000,"context_lengths_max":990000,"context_lengths_num_intervals":1,"document_depth_percent_min":50,"document_depth_percent_max":50,"document_depth_percent_intervals":1,"show_score":true,"tokenizer_path":"Qwen/Qwen3-0.6B"}}}' \
  --judge '{"strategy":"rule"}' \
  --generation-config '{"max_tokens":128,"temperature":0,"timeout":1800,"extra_body":{"chat_template_kwargs":{"enable_thinking":false}}}' \
  --eval-batch-size 1 \
  --work-dir /workspace/outputs/needle_1m_manual \
  --no-timestamp
```

只测 1M 接收能力和延迟：

```bash
docker compose exec -T evalscope evalscope perf \
  --model Qwen3.8-27B \
  --api openai \
  --url http://192.168.110.232:8000/v1/chat/completions \
  --tokenizer-path Qwen/Qwen3-0.6B \
  --dataset random \
  --min-prompt-length 999000 \
  --max-prompt-length 999002 \
  --max-tokens 128 \
  -n 1 \
  --parallel 1 \
  --outputs-dir /workspace/outputs/perf_1m_manual \
  --no-timestamp
```

结果在 `outputs/needle_1m_manual/`、`outputs/perf_1m_manual/`；报告看 `reports/report.html`，明细看 `reviews/*.jsonl`。扫深度/长度时改 `document_depth_percent_*` 或 `context_lengths_*` 即可。

### 3.3.3 分批执行

一个数据集初始化失败会导致**整批终止**，建议分 3 批：

| 批次 | 数据集 | 批大小 | 超时 |
|---|---|---:|---:|
| 1 核心 | `mmlu_pro` `mmlu` `gpqa_diamond` `bbh` `musr` `math_500` `gsm8k` `process_bench` `aime26` `hmmt26` `ifeval` `ifbench` `truthful_qa` `ceval` `cmmlu` `cmath` `arc_agi_2` | 8 | 600 |
| 2 长上下文 | `longbench_v2` `openai_mrcr` | 1 | 1800 |
| 3 工具调用 | `tool_bench` `general_fc` | 4 | 600 |

长上下文批次再加三条：`eval_batch_size=1`（并发会叠加 KV cache 占用压垮 vLLM）；`generation_config.retries` 设 0 或 1（默认 5 次重试，服务端一崩就是雪崩式重试）；`ignore_errors: true`（单样本超限不中断整批）。

跑完读 `outputs/<task_id>/logs/eval_log.log` 判断还能不能再加一档：HTTP 400 是 prompt 超限，降一档；超时是能塞进去但太慢；Connection refused 说明引擎真的挂了，上一档就是你的真实上限。

### 3.3.4 few-shot 配置

| `few_shot_num` | 数据集 |
|---:|---|
| 5 | `mmlu_pro`、`mmlu`、`ceval` |
| 4 | `gsm8k` |
| 3 | `bbh` |
| 0 | 其余推荐数据集（其他数据集参考 `/benchmarks` 默认值） |

### 3.3.5 横向对比要求

所有被测模型必须保持一致：

- `few_shot_num` 按上表固定
- `Temperature=0`、`Top P=1`、`Max Tokens` 统一
- chat template 用各自模型默认，不做修改
- 答案解析用 EvalScope 默认，不做修改
- 记录 EvalScope commit SHA（`deploy.sh` 会把 `main` 解析成完整 SHA 并写入镜像 tag），不要用 `main` 字样

## 3.4 性能压测（perf）

在项目根目录执行；按实际替换模型和 URL。

**冒烟**

```bash
docker compose exec -T evalscope evalscope perf \
  --model Qwen3.8-27B --url http://192.168.110.232:8000/v1/chat/completions --api openai \
  --dataset openqa --parallel 1 --number 2 \
  --max-tokens 128 --stream --outputs-dir outputs
```

**并发梯度**

```bash
docker compose exec -T evalscope evalscope perf \
  --model Qwen3.8-27B --url http://192.168.110.232:8000/v1/chat/completions --api openai \
  --dataset openqa --parallel 1 4 8 16 --number 20 80 160 320 \
  --warmup-num 0.1 --max-tokens 512 --stream \
  --outputs-dir outputs --name qwen_openqa_sweep
```

`--parallel` 与 `--number` 列表长度一致、一一对应；`--number` 是每档总请求数，建议至少为并发的 10 倍；`--warmup-num` 不计入指标。

**固定长度输入**

```bash
docker compose exec -T evalscope evalscope perf \
  --model Qwen3.8-27B --url http://192.168.110.232:8000/v1/chat/completions --api openai \
  --dataset random --tokenizer-path /path/to/Qwen3.8-27B \
  --min-prompt-length 1024 --max-prompt-length 1024 \
  --max-tokens 128 --parallel 20 --number 200 \
  --warmup-num 0.1 --stream --outputs-dir outputs
```

`random` 需要与服务端匹配的 tokenizer；`min=max` 即固定输入长度。

**固定速率**

```bash
docker compose exec -T evalscope evalscope perf \
  --model Qwen3.8-27B --url http://192.168.110.232:8000/v1/chat/completions --api openai \
  --dataset openqa --open-loop --rate 5 10 20 \
  --number 500 1000 2000 --max-tokens 512 --stream \
  --outputs-dir outputs --name qwen_openloop_sweep
```

`--open-loop` 下忽略 `--parallel`；`--rate` 与 `--number` 列表长度一致。

**其他场景**

在上面的 `--api openai` 命令上替换参数即可：

| 场景 | 参数 |
|---|---|
| 固定 prompt | `--prompt '详细解释 Kubernetes Scheduler 的工作原理'`（覆盖 `--dataset`） |
| Responses API | `--url .../v1/responses --api openai_responses` |
| 多轮对话 | `--dataset random_multi_turn --multi-turn --min-turns 1 --max-turns 4` |
| Embedding | `--url .../v1/embeddings --dataset random_embedding --api openai_embedding` |
| Rerank | `--url .../v1/reranks --dataset random_rerank --api openai_rerank` |
| 流量回放 | `--dataset workload_trace --dataset-path trace.jsonl --open-loop` |

**结果**

`outputs/<timestamp>/<name-or-model>/performance_summary.txt`、`perf_report.html`；重点看请求/输出吞吐、TTFT、TPOT、p99、成功率。

## 3.5 数据持久化

- `./outputs/` 挂载到容器内，评测结果不会因切换方式/版本丢失
- 缓存使用 Docker named volume，避免重复下载
- **警告**：不要使用 `docker compose down -v`，`-v` 会连缓存卷一起删除

# 四、参考

## 4.1 不可用数据集

| 类别 | 数据集 | 缺什么 |
|---|---|---|
| 需额外 extra | `multi_if` `refcoco` | 对应 pip extra（`multi_if` 缺 `pythainlp`；`refcoco` 缺 `pycocoevalcap`） |
| 需 Judge | `mt_bench` `simple_qa` `chinese_simpleqa` `alpaca_eval` `drivel_writing` `hle` `plawbench` `minerva_math` `imo_answerbench` `docmath` `cl_bench` `aa_lcr` `frames` `longmemeval` `one_million_bench` `health_bench` `arena_hard` `general_arena` | Judge 服务（后两项的 pip 依赖镜像已内置，卡点是要算 win_rate 必须有 Judge） |
| 需 Sandbox | `live_code_bench` `mbpp` `mbpp_plus` `bigcodebench` `bigcodebench_hard` `multiple_humaneval` `multiple_mbpp` | Docker |
| 需 GitHub 源码包 | `perspective_gap_prompt_writing` `perspective_gap_role_assignment` | 打分依赖装自个人仓库 `WhymustIhaveaname/PerspectiveGap`，非 PyPI 包，会给构建引入 GitHub 依赖 |
| 非文本 | `seed_tts_eval` | 音频模型 |

`olympiad_bench` 可用——它要的 `latex2sympy2_extended` 是上游核心依赖，镜像已内置。

> 装 extra 时注意：数据集名 ≠ pip extra 名，**照抄数据集名会 pip 报错**。`swe_bench_lite` / `swe_bench_verified` / `swe_bench_verified_mini` 对应 extra `swe_bench`，`wmt24pp` 对应 extra `wmt`。

## 4.2 需要完整评测环境？

图像、视频、代码执行、Judge 类基准需要 torch、opencv、Docker Sandbox、额外 Judge 服务，镜像会膨胀到数 GB。建议在独立服务器直接安装，不用容器：

```bash
# 裸机 / 虚拟机（系统安装 Docker，即有 sandbox）
pip install "evalscope[all,ifeval,ifbench,sandbox,openai_mrcr,needle_haystack]"
evalscope service --host 0.0.0.0 --port 9000 --outputs ./outputs
```

裸机系统 Docker 可直接用作 Sandbox，无需挂 socket 或另起远程服务；`all` 会拉入 torch / torchvision / diffusers / opencv / sentence-transformers / langchain / OpenCompass / VLMEvalKit 等，环境数 GB 级，适合一次性搭建完整环境。
