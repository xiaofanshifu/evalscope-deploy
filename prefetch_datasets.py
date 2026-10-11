import traceback

from evalscope.config import TaskConfig
from evalscope.api.registry import get_benchmark

TARGETS = [
    ('mmlu_pro', 'mmlu_pro'),
    ('mmlu', 'mmlu'),
    ('gpqa_diamond', 'gpqa_diamond'),
    ('bbh', 'bbh'),
    ('musr', 'musr'),
    ('math_500', 'math_500'),
    ('gsm8k', 'gsm8k'),
    ('process_bench', 'process_bench'),
    ('aime26', 'aime26'),
    ('hmmt26', 'hmmt26'),
    ('ifeval', 'ifeval'),
    ('ifbench', 'ifbench'),
    ('truthful_qa', 'truthful_qa'),
    ('ceval', 'ceval'),
    ('cmmlu', 'cmmlu'),
    ('cmath', 'cmath'),
    ('arc_agi_2', 'arc_agi_2'),
    ('longbench_v2', 'longbench_v2'),
    ('openai_mrcr', 'openai_mrcr'),
    ('tool_bench', 'tool_bench'),
    ('general_fc', 'general_fc'),
]

ok = []
fail = []

for label, name in TARGETS:
    try:
        config = TaskConfig(datasets=[name])
        adapter = get_benchmark(name, config=config)
        adapter.load_dataset()
        ok.append(label)
        print(f'[OK]   {label} -> {name}', flush=True)
    except Exception as e:
        fail.append((label, name, str(e)))
        print(f'[FAIL] {label} -> {name}: {e}', flush=True)
        traceback.print_exc()

print('=== SUMMARY ===')
print('OK   :', ', '.join(ok))
print('FAIL :', ', '.join(f'{l}({n})' for l, n, _ in fail))
