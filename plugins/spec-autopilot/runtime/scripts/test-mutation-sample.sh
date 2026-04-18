#!/usr/bin/env bash
# test-mutation-sample.sh — shell 层面的轻量变异测试
#
# 设计：对选定的 N 个 runtime 脚本应用固定 mutator，
# 执行对应 test 观察是否能"kill"变异。
#
# 变异规则：
#   M1 `==` → `!=`
#   M2 `>` → `<`
#   M3 `return 0` → `return 1`
#   M4 `exit 0` → `exit 1`
#   M5 `-eq` → `-ne`
#   M6 `"true"` → `"false"`
#
# 输入：
#   --targets <glob>        默认 plugins/spec-autopilot/runtime/scripts/*.sh
#   --sample-size N         默认 5
#   --timeout-per-mutant S  默认 30
#
# 输出：
#   stdout: MUTATION_KILL_RATE=0.XX SURVIVORS=N
#   file:   <cwd>/.mutation-report.json
#
# 安全：
#   - 要求 git working tree 干净，否则 exit 2
#   - 变异前后双重 git diff 校验
#   - 任何异常必须 trap 恢复源文件

set -uo pipefail

# 探测 PROJECT_ROOT 与缓存目录（兼容非 git 场景，回落 cwd）
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
CACHE_DIR="${PROJECT_ROOT}/.cache/spec-autopilot"
mkdir -p "$CACHE_DIR"
REPORT_FILE="$CACHE_DIR/mutation-report.json"

TARGETS_GLOB="plugins/spec-autopilot/runtime/scripts/*.sh"
SAMPLE_SIZE=5
TIMEOUT=30

while [ $# -gt 0 ]; do
  case "$1" in
    --targets)
      TARGETS_GLOB="${2:-}"
      shift 2
      ;;
    --sample-size)
      SAMPLE_SIZE="${2:-5}"
      shift 2
      ;;
    --timeout-per-mutant)
      TIMEOUT="${2:-30}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

# 确认 git 工作区干净
ensure_clean_tree() {
  if [ -z "$(git status --porcelain 2>/dev/null || echo dirty)" ]; then
    return 0
  fi
  echo "ERROR: git working tree must be clean before mutation run" >&2
  exit 2
}

ensure_clean_tree

# 确定性采样：对每个文件计算 cksum，按结果排序后取前 N
select_targets() {
  local glob="$1" n="$2"
  # shellcheck disable=SC2086
  local all=()
  local f
  for f in $glob; do
    [ -f "$f" ] || continue
    all+=("$f")
  done
  if [ "${#all[@]}" -eq 0 ]; then
    return 0
  fi
  local hashed=""
  for f in "${all[@]}"; do
    local h
    h=$(printf '%s' "$f" | cksum | awk '{print $1}')
    hashed="${hashed}${h} ${f}
"
  done
  printf '%s' "$hashed" | sort -n | head -n "$n" | awk '{print $2}'
}

# 在文件内查找首个可变异行，返回 "rule|line_no|pattern"
find_first_mutation() {
  local file="$1"
  local line_no=0
  local line rule=""
  while IFS= read -r line; do
    line_no=$((line_no + 1))
    # 跳过注释行
    case "$line" in
      \#*) continue ;;
    esac
    if [ -z "$rule" ] && printf '%s' "$line" | grep -q '=='; then
      rule="M1"
      echo "$rule|$line_no"
      return 0
    fi
    if [ -z "$rule" ] && printf '%s' "$line" | grep -qE '\[\s+[^]]*>\s'; then
      echo "M2|$line_no"
      return 0
    fi
    if [ -z "$rule" ] && printf '%s' "$line" | grep -qE '^\s*return\s+0\b'; then
      echo "M3|$line_no"
      return 0
    fi
    if [ -z "$rule" ] && printf '%s' "$line" | grep -qE '^\s*exit\s+0\b'; then
      echo "M4|$line_no"
      return 0
    fi
    if [ -z "$rule" ] && printf '%s' "$line" | grep -q '\-eq'; then
      echo "M5|$line_no"
      return 0
    fi
    if [ -z "$rule" ] && printf '%s' "$line" | grep -q '"true"'; then
      echo "M6|$line_no"
      return 0
    fi
  done <"$file"
  echo ""
}

# 应用变异：就地编辑文件，仅改指定行
apply_mutation() {
  local file="$1" rule="$2" line_no="$3"
  local tmp
  tmp=$(mktemp)
  awk -v ln="$line_no" -v rule="$rule" '
    NR == ln {
      if (rule == "M1") { gsub(/==/, "!=") }
      else if (rule == "M2") { gsub(/>/, "<") }
      else if (rule == "M3") { gsub(/return 0/, "return 1") }
      else if (rule == "M4") { gsub(/exit 0/, "exit 1") }
      else if (rule == "M5") { gsub(/-eq/, "-ne") }
      else if (rule == "M6") { gsub(/"true"/, "\"false\"") }
    }
    { print }
  ' "$file" >"$tmp"
  mv "$tmp" "$file"
}

# 恢复文件（通过 git checkout）
restore_file() {
  local file="$1"
  git checkout -- "$file" 2>/dev/null || true
}

# 查找对应 test 文件：runtime/scripts/X.sh → tests/test_X.sh
find_test_file() {
  local target="$1"
  local base
  base=$(basename "$target" .sh)
  # 处理前缀：good_target → test_good_target.sh
  # 去除前导下划线
  base="${base#_}"
  # 注意 runtime/scripts 下的下划线前缀文件
  local candidates=(
    "tests/test_${base}.sh"
    "plugins/spec-autopilot/tests/test_${base}.sh"
  )
  # 将 dash 替换为 underscore
  local b2
  b2=$(printf '%s' "$base" | tr '-' '_')
  candidates+=(
    "tests/test_${b2}.sh"
    "plugins/spec-autopilot/tests/test_${b2}.sh"
  )
  local c
  for c in "${candidates[@]}"; do
    if [ -f "$c" ]; then
      echo "$c"
      return 0
    fi
  done
  echo ""
}

# 运行 test，带超时。返回: killed | survived | timeout | notest
run_test_with_timeout() {
  local test_file="$1" timeout_s="$2"
  if [ -z "$test_file" ]; then
    echo "notest"
    return 0
  fi
  local pid rc=0
  (
    bash "$test_file" >/dev/null 2>&1
  ) &
  pid=$!
  local elapsed=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$elapsed" -ge "$timeout_s" ]; then
      kill -TERM "$pid" 2>/dev/null || true
      sleep 1
      kill -KILL "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      echo "timeout"
      return 0
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  wait "$pid" 2>/dev/null
  rc=$?
  # test 失败（非 0）→ 变异被 kill
  if [ "$rc" -ne 0 ]; then
    echo "killed"
  else
    echo "survived"
  fi
}

# 主循环
REPORT=$(mktemp)
# shellcheck disable=SC2064
trap "rm -f '$REPORT'" EXIT

# 获取目标
TARGETS_RAW=$(select_targets "$TARGETS_GLOB" "$SAMPLE_SIZE")
if [ -z "$TARGETS_RAW" ]; then
  printf '{"targets":[],"overall_kill_rate":0.0,"survivors":[]}\n' >"$REPORT_FILE"
  echo "MUTATION_KILL_RATE=0.00 SURVIVORS=0"
  exit 0
fi

declare -a ALL_TARGETS=()
while IFS= read -r line; do
  [ -z "$line" ] || ALL_TARGETS+=("$line")
done <<<"$TARGETS_RAW"

TOTAL_MUTANTS=0
KILLED_MUTANTS=0
SURVIVORS=()

TARGETS_JSON=""

for target in "${ALL_TARGETS[@]}"; do
  # 前置 diff 校验
  if [ -n "$(git diff --stat -- "$target" 2>/dev/null)" ]; then
    echo "ERROR: unexpected diff on $target before mutation" >&2
    git checkout -- "$target" 2>/dev/null || true
    continue
  fi

  mutation_spec=$(find_first_mutation "$target")
  if [ -z "$mutation_spec" ]; then
    continue
  fi

  rule=$(printf '%s' "$mutation_spec" | cut -d'|' -f1)
  lno=$(printf '%s' "$mutation_spec" | cut -d'|' -f2)

  test_file=$(find_test_file "$target")

  start_ms=$(python3 -c "import time;print(int(time.time()*1000))" 2>/dev/null || echo 0)

  # 应用变异（带 trap 恢复）
  # shellcheck disable=SC2064
  trap "restore_file '$target'" INT TERM
  apply_mutation "$target" "$rule" "$lno"

  status=$(run_test_with_timeout "$test_file" "$TIMEOUT")

  restore_file "$target"
  trap - INT TERM

  # 后置 diff 校验
  if [ -n "$(git diff --stat -- "$target" 2>/dev/null)" ]; then
    echo "WARN: residual diff after restore on $target, forcing checkout" >&2
    git checkout -- "$target" 2>/dev/null || true
  fi

  end_ms=$(python3 -c "import time;print(int(time.time()*1000))" 2>/dev/null || echo 0)
  duration=$((end_ms - start_ms))

  TOTAL_MUTANTS=$((TOTAL_MUTANTS + 1))
  kill_rate=0.0
  case "$status" in
    killed)
      KILLED_MUTANTS=$((KILLED_MUTANTS + 1))
      kill_rate=1.0
      ;;
    survived | notest | timeout)
      SURVIVORS+=("$target")
      ;;
  esac

  entry=$(python3 -c "
import json
print(json.dumps({
  'file': '$target',
  'mutants': [{'rule': '$rule', 'line': $lno, 'status': '$status', 'duration_ms': $duration}],
  'kill_rate': $kill_rate,
  'test_file': '$test_file'
}))
")
  if [ -z "$TARGETS_JSON" ]; then
    TARGETS_JSON="$entry"
  else
    TARGETS_JSON="$TARGETS_JSON,$entry"
  fi
done

# 计算总 kill rate
if [ "$TOTAL_MUTANTS" -gt 0 ]; then
  OVERALL=$(python3 -c "print(round($KILLED_MUTANTS / $TOTAL_MUTANTS, 4))")
else
  OVERALL=0.0
fi

# 生成报告
SURV_JSON=$(python3 -c "
import json
survivors = '''$(printf '%s\n' "${SURVIVORS[@]+"${SURVIVORS[@]}"}")'''.strip().splitlines()
print(json.dumps(survivors))
")

python3 -c "
import json
report = {
  'targets': json.loads('[' + '''$TARGETS_JSON''' + ']'),
  'overall_kill_rate': $OVERALL,
  'survivors': json.loads('''$SURV_JSON'''),
  'total_mutants': $TOTAL_MUTANTS,
  'killed_mutants': $KILLED_MUTANTS
}
with open('$REPORT_FILE','w') as f:
  json.dump(report, f, indent=2)
"

# 最终干净校验
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  # 仅允许缓存目录变化为 untracked
  if git status --porcelain | grep -v '\.cache/spec-autopilot/' | grep -q .; then
    echo "WARN: git tree not clean after run" >&2
  fi
fi

SURV_COUNT="${#SURVIVORS[@]}"
printf 'MUTATION_KILL_RATE=%.2f SURVIVORS=%d\n' "$OVERALL" "$SURV_COUNT"
exit 0
