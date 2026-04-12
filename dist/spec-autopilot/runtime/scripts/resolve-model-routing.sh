#!/usr/bin/env bash
# resolve-model-routing.sh
# 统一模型路由解析器 — 根据 phase / complexity / retry_count / critical 标记
# 解析出应使用的模型档位、具体模型、effort 级别及路由原因。
#
# Usage:
#   resolve-model-routing.sh <project_root> <phase> [complexity] [requirement_type] [retry_count] [critical]
#
# Args:
#   project_root: 项目根目录
#   phase: 阶段编号 (1-7)
#   complexity: 复杂度 (small/medium/large) 默认 medium
#   requirement_type: 需求类型 (feature/bugfix/refactor/chore) 默认 feature
#   retry_count: 当前重试次数 默认 0
#   critical: 是否关键任务 (true/false) 默认 false
#
# Output: JSON on stdout:
# {
#   "selected_tier": "fast|standard|deep",
#   "selected_model": "haiku|sonnet|opus",
#   "selected_effort": "low|medium|high",
#   "routing_reason": "...",
#   "escalated_from": null | "fast|standard",
#   "fallback_applied": false
# }

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

PROJECT_ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
PHASE="${2:-1}"
COMPLEXITY="${3:-medium}"
REQUIREMENT_TYPE="${4:-feature}"
RETRY_COUNT="${5:-0}"
CRITICAL="${6:-false}"

CONFIG_FILE="$PROJECT_ROOT/.claude/autopilot.config.yaml"

# --- 模型解析核心逻辑 (Python3) ---
python3 -c "
import json, sys, os

project_root = sys.argv[1]
phase = int(sys.argv[2])
complexity = sys.argv[3]
requirement_type = sys.argv[4]
retry_count = int(sys.argv[5])
critical = sys.argv[6].lower() == 'true'
config_path = sys.argv[7]

# ── 常量定义 ──

# tier -> model 映射
TIER_MODEL_MAP = {
    'fast': 'haiku',
    'standard': 'sonnet',
    'deep': 'opus',
}

# tier -> effort 映射
TIER_EFFORT_MAP = {
    'fast': 'low',
    'standard': 'medium',
    'deep': 'high',
}

# 默认 phase 路由策略
DEFAULT_PHASE_ROUTING = {
    1: 'deep',      # 需求分析需要深度推理
    2: 'fast',      # OpenSpec 创建是机械性操作
    3: 'fast',      # FF 生成是模板化操作
    4: 'standard',  # 测试设计（SWE-bench Sonnet≈Opus，有 gate 兜底，失败自动升级）
    5: 'deep',      # 代码实施需要最强推理能力
    6: 'fast',      # 报告生成是机械性操作
    7: 'fast',      # 汇总与归档较简单
}

# 升级策略: tier -> 升级目标 tier
ESCALATION_MAP = {
    'fast': 'standard',
    'standard': 'deep',
    'deep': None,  # deep 不再自动升级
}

# 升级触发条件: tier -> 连续失败次数阈值
ESCALATION_THRESHOLD = {
    'fast': 1,      # fast 失败 1 次即升级
    'standard': 2,  # standard 连续失败 2 次升级
    'deep': None,   # deep 不自动升级
}

# 特殊标记: auto 表示继承父会话模型，resolver 不强制指定
TIER_AUTO = 'auto'


def parse_config(config_path):
    \"\"\"解析配置文件中的 model_routing 配置。\"\"\"
    if not os.path.isfile(config_path):
        return None

    # Strategy 1: PyYAML
    try:
        import yaml
        with open(config_path) as f:
            data = yaml.safe_load(f) or {}
        return data.get('model_routing')
    except ImportError:
        pass
    except Exception:
        return None

    # Strategy 2: Regex fallback — 支持两级嵌套
    try:
        import re
        with open(config_path) as f:
            content = f.read()
        if 'model_routing' not in content:
            return None

        # 尝试匹配 model_routing: <value> (顶层字符串)
        m_inline = re.search(r'^model_routing:\s+(\S+)\s*$', content, re.MULTILINE)
        if m_inline:
            return m_inline.group(1).strip().strip('\"').strip(\"'\")

        # 匹配 model_routing: (block)
        mr_match = re.search(r'^model_routing:\s*$', content, re.MULTILINE)
        if not mr_match:
            return None

        # 提取 model_routing block（到下一个顶层 key 或 EOF）
        block_start = mr_match.end()
        next_top = re.search(r'^[a-zA-Z_]\w*:', content[block_start:], re.MULTILINE)
        block = content[block_start:block_start + next_top.start()] if next_top else content[block_start:]

        result = {}
        lines = block.split('\n')
        # 确定 L1 缩进宽度（model_routing 下第一个非空行的缩进）
        l1_indent = None
        for line in lines:
            stripped = line.lstrip()
            if not stripped or stripped.startswith('#'):
                continue
            l1_indent = len(line) - len(stripped)
            break
        if l1_indent is None:
            return None

        # 双层解析状态机
        current_l1_key = None  # 当前 L1 key (如 'phases', 'enabled', ...)
        phases_dict = {}       # phases 下的 L2 解析结果

        i = 0
        while i < len(lines):
            line = lines[i]
            stripped = line.lstrip()
            i += 1
            if not stripped or stripped.startswith('#'):
                continue
            indent = len(line) - len(stripped)

            # 回到 model_routing 外（缩进 <= 0 且非空）
            if indent < l1_indent and stripped:
                break

            if indent == l1_indent:
                # L1 key
                m = re.match(r'([\w_]+):\s*(.*)', stripped)
                if not m:
                    continue
                key = m.group(1)
                val_str = m.group(2).strip()
                current_l1_key = key

                if key == 'phases' and not val_str:
                    # phases: (block) — 继续解析 L2
                    pass
                elif key == 'enabled':
                    result['enabled'] = val_str.lower() == 'true' if val_str else True
                elif val_str:
                    val_clean = val_str.strip('\"').strip(\"'\")
                    if val_clean.lower() == 'true':
                        result[key] = True
                    elif val_clean.lower() == 'false':
                        result[key] = False
                    else:
                        result[key] = val_clean
            elif indent > l1_indent and current_l1_key == 'phases':
                # L2: phases 内部
                m = re.match(r'(phase_\d+):\s*(.*)', stripped)
                if m:
                    phase_key = m.group(1)
                    phase_val_str = m.group(2).strip()
                    if phase_val_str:
                        # phases.phase_N: <scalar>
                        phases_dict[phase_key] = phase_val_str.strip('\"').strip(\"'\")
                    else:
                        # phases.phase_N: (block) — 继续解析 L3
                        phase_obj = {}
                        while i < len(lines):
                            l3_line = lines[i]
                            l3_stripped = l3_line.lstrip()
                            if not l3_stripped or l3_stripped.startswith('#'):
                                i += 1
                                continue
                            l3_indent = len(l3_line) - len(l3_stripped)
                            if l3_indent <= indent:
                                break  # 回到 L2 或更高
                            l3_m = re.match(r'([\w_]+):\s*(.*)', l3_stripped)
                            if l3_m:
                                l3_key = l3_m.group(1)
                                l3_val = l3_m.group(2).strip().strip('\"').strip(\"'\")
                                phase_obj[l3_key] = l3_val
                            i += 1
                        phases_dict[phase_key] = phase_obj
            elif indent > l1_indent and current_l1_key and current_l1_key.startswith('phase_'):
                # 旧格式 flat dict 内不应出现嵌套（忽略）
                pass

        # 如果 phases 子对象有内容，挂载到 result
        if phases_dict:
            result['phases'] = phases_dict

        # 检查是否为旧格式 flat dict (phase_1: heavy, ...)
        # 如果 result 中只有 phase_N 键且值都是字符串，保持旧格式
        return result if result else None
    except Exception:
        pass

    return None


def resolve_tier_from_config(mr_config, phase):
    \"\"\"根据配置解析指定 phase 的 tier。返回 tier 字符串或 TIER_AUTO。\"\"\"
    if mr_config is None:
        return None

    if isinstance(mr_config, str):
        # 顶层字符串
        if mr_config == 'auto':
            return TIER_AUTO
        return mr_config

    if isinstance(mr_config, dict):
        # 检查 enabled 字段
        if mr_config.get('enabled') is False:
            return None

        phase_key = f'phase_{phase}'

        # 新格式: phases 子对象
        phases = mr_config.get('phases', {})
        if isinstance(phases, dict) and phase_key in phases:
            pval = phases[phase_key]
            if isinstance(pval, str):
                if pval == 'auto':
                    return TIER_AUTO
                return pval
            elif isinstance(pval, dict):
                tier = pval.get('tier')
                if tier:
                    if tier == 'auto':
                        return TIER_AUTO
                    return tier
                model = pval.get('model')
                if model:
                    # 反查 tier
                    for t, m in TIER_MODEL_MAP.items():
                        if m == model:
                            return t
                    return 'standard'

        # flat dict: phase_1: <tier>
        if phase_key in mr_config:
            val = mr_config[phase_key]
            if isinstance(val, str):
                if val == 'auto':
                    return TIER_AUTO
                return val

        # 回退到 default_subagent_model
        default_model = mr_config.get('default_subagent_model')
        if default_model:
            for t, m in TIER_MODEL_MAP.items():
                if m == default_model or t == default_model:
                    return t

    return None


def resolve(phase, complexity, requirement_type, retry_count, critical, config_path):
    \"\"\"主解析逻辑。\"\"\"
    # ── 环境变量覆盖（最高优先级，用于实验/调试）──
    env_model = os.environ.get(f'AUTOPILOT_PHASE{phase}_MODEL')
    env_effort = os.environ.get(f'AUTOPILOT_PHASE{phase}_EFFORT')
    if env_model:
        # 从 model 反查 tier
        env_tier = 'standard'
        for t, m in TIER_MODEL_MAP.items():
            if m == env_model or t == env_model:
                env_tier = t
                env_model = TIER_MODEL_MAP.get(t, env_model)
                break
        return {
            'selected_tier': env_tier,
            'selected_model': env_model,
            'selected_effort': env_effort or TIER_EFFORT_MAP.get(env_tier, 'medium'),
            'routing_reason': f'环境变量 AUTOPILOT_PHASE{phase}_MODEL={env_model} 覆盖',
            'escalated_from': None,
            'fallback_applied': False,
            'fallback_model': 'sonnet',
        }

    mr_config = parse_config(config_path)
    result = {
        'selected_tier': None,
        'selected_model': None,
        'selected_effort': None,
        'routing_reason': '',
        'escalated_from': None,
        'fallback_applied': False,
        'fallback_model': None,
    }

    # 解析 fallback_model（供 dispatch 运行时 fallback 使用）
    fallback_model = None
    if mr_config and isinstance(mr_config, dict):
        fallback_model = mr_config.get('fallback_model')
    # 始终输出 fallback_model，即使未配置也输出默认值 sonnet
    result['fallback_model'] = fallback_model or 'sonnet'

    # 第一步：从配置解析 tier
    config_tier = resolve_tier_from_config(mr_config, phase)

    # 第二步：auto = 继承父会话模型，resolver 不覆盖
    if config_tier == TIER_AUTO:
        result['selected_tier'] = 'auto'
        result['selected_model'] = 'auto'
        result['selected_effort'] = env_effort or 'medium'
        reason = f'config phase_{phase} 指定 auto, 继承父会话模型'
        if env_effort:
            reason += f', 环境变量 AUTOPILOT_PHASE{phase}_EFFORT={env_effort} 覆盖 effort'
        result['routing_reason'] = reason
        return result

    # 第三步：确定 base_tier
    if config_tier and config_tier in TIER_MODEL_MAP:
        base_tier = config_tier
        result['routing_reason'] = f'config phase_{phase} 指定 tier={config_tier}'
    elif config_tier:
        # 配置显式指定了 tier 但不在合法值中 → 保留无效值，后续触发 fallback
        base_tier = config_tier
        result['routing_reason'] = f'config phase_{phase} 指定 tier={config_tier} (无效)'
    else:
        base_tier = DEFAULT_PHASE_ROUTING.get(phase, 'standard')
        result['routing_reason'] = f'默认 phase {phase} 路由: {base_tier}'

    # 第四步：复杂度调整（仅在默认路由时生效）
    if not config_tier and complexity == 'large' and base_tier == 'fast':
        base_tier = 'standard'
        result['routing_reason'] += f', 复杂度={complexity} 升级至 standard'
    elif not config_tier and complexity == 'small' and base_tier == 'standard':
        base_tier = 'fast'
        result['routing_reason'] += f', 复杂度={complexity} 降级至 fast'

    # 第五步：关键任务升级
    if critical and base_tier != 'deep':
        base_tier = 'deep'
        result['routing_reason'] += ', critical=true 升级至 deep'

    # 第六步：重试升级 (escalation)
    escalated_from = None
    if retry_count > 0:
        current_tier = base_tier
        threshold = ESCALATION_THRESHOLD.get(current_tier)
        if threshold is not None and retry_count >= threshold:
            next_tier = ESCALATION_MAP.get(current_tier)
            if next_tier:
                escalated_from = current_tier
                base_tier = next_tier
                result['routing_reason'] += (
                    f', retry={retry_count} >= 阈值 {threshold}, '
                    f'从 {current_tier} 升级至 {next_tier}'
                )
                # 二级升级检查
                if retry_count >= threshold + 2 and base_tier != 'deep':
                    next_next = ESCALATION_MAP.get(base_tier)
                    if next_next:
                        base_tier = next_next
                        result['routing_reason'] += f', 持续失败再升至 {next_next}'

    # 第七步：配置中的 escalate_on_failure_to 覆盖
    if retry_count > 0 and mr_config and isinstance(mr_config, dict):
        phases = mr_config.get('phases', {})
        phase_key = f'phase_{phase}'
        if isinstance(phases, dict) and phase_key in phases:
            pval = phases[phase_key]
            if isinstance(pval, dict):
                esc_target = pval.get('escalate_on_failure_to')
                if esc_target:
                    esc_tier = esc_target
                    if esc_tier in TIER_MODEL_MAP:
                        escalated_from = escalated_from or base_tier
                        base_tier = esc_tier
                        result['routing_reason'] += (
                            f', escalate_on_failure_to={esc_target} 覆盖至 {esc_tier}'
                        )

    # 第八步：组装结果
    result['selected_tier'] = base_tier
    selected_model = TIER_MODEL_MAP.get(base_tier)
    result['selected_effort'] = TIER_EFFORT_MAP.get(base_tier, 'medium')
    result['escalated_from'] = escalated_from

    # 第九步：fallback — 当 base_tier 不在 TIER_MODEL_MAP 中时回退
    if selected_model is None:
        if fallback_model:
            # fallback_model 可以是 model 名或 tier 名
            if fallback_model in TIER_MODEL_MAP:
                # fallback_model 是 tier 名
                result['selected_tier'] = fallback_model
                selected_model = TIER_MODEL_MAP[fallback_model]
                result['selected_effort'] = TIER_EFFORT_MAP[fallback_model]
            elif fallback_model in TIER_MODEL_MAP.values():
                # fallback_model 是 model 名
                selected_model = fallback_model
                for t, m in TIER_MODEL_MAP.items():
                    if m == fallback_model:
                        result['selected_tier'] = t
                        result['selected_effort'] = TIER_EFFORT_MAP[t]
                        break
            else:
                selected_model = 'sonnet'
                result['selected_tier'] = 'standard'
                result['selected_effort'] = 'medium'
            result['fallback_applied'] = True
            result['routing_reason'] += f', tier 无效, fallback 至 {selected_model}'
        else:
            # 无 fallback_model 配置，硬回退到 sonnet
            selected_model = 'sonnet'
            result['selected_tier'] = 'standard'
            result['selected_effort'] = 'medium'
            result['fallback_applied'] = True
            result['routing_reason'] += ', tier 无效, 硬回退至 sonnet'

    result['selected_model'] = selected_model

    # 第十步：配置中的 phase 级 effort 覆盖
    if mr_config and isinstance(mr_config, dict):
        phases = mr_config.get('phases', {})
        phase_key = f'phase_{phase}'
        if isinstance(phases, dict) and phase_key in phases:
            pval = phases[phase_key]
            if isinstance(pval, dict) and 'effort' in pval:
                result['selected_effort'] = pval['effort']

    # 第十一步：配置中的 phase 级 model 覆盖（优先级最高，仅首次尝试）
    if mr_config and isinstance(mr_config, dict):
        phases = mr_config.get('phases', {})
        phase_key = f'phase_{phase}'
        if isinstance(phases, dict) and phase_key in phases:
            pval = phases[phase_key]
            if isinstance(pval, dict) and 'model' in pval and retry_count == 0:
                result['selected_model'] = pval['model']

    # 第十二步：环境变量 EFFORT 独立覆盖（最高优先级）
    # 允许单独设置 AUTOPILOT_PHASE{N}_EFFORT 而不设置 MODEL
    if env_effort:
        result['selected_effort'] = env_effort
        result['routing_reason'] += f', 环境变量 AUTOPILOT_PHASE{phase}_EFFORT={env_effort} 覆盖 effort'

    return result


result = resolve(phase, complexity, requirement_type, retry_count, critical, config_path)
print(json.dumps(result, ensure_ascii=False))
" "$PROJECT_ROOT" "$PHASE" "$COMPLEXITY" "$REQUIREMENT_TYPE" "$RETRY_COUNT" "$CRITICAL" "$CONFIG_FILE"

exit $?
