#!/usr/bin/env bash
# test-health-score.sh — 测试套件静态健康度评分
#
# 指标：
#   assertion_density   每文件 PASS 断言数 / SLoC
#   weak_ratio          仅 exit-code 断言文件数 / 总文件数
#   duplicate_ratio     跨文件 case 名 ≥ 2 次重复 / 总 case 数
#   age_distribution    按 git log 首次出现时间 bucket
#   kill_rate           （若 .mutation-report.json 存在则读入）
#
# 输入：
#   --tests-dir <path>       默认 plugins/spec-autopilot/tests
#   --mutation-report <path> 默认 .mutation-report.json
#   --threshold <number>     overall 阈值（命中则输出 HEALTH_BELOW_THRESHOLD=1）
#
# 输出：
#   stdout: HEALTH_SCORE=0-100 (+ HEALTH_BELOW_THRESHOLD=1 可选)
#   file:   <cwd>/.test-health-report.json
#
# 退出码：始终 0（评分工具不阻断）

set -uo pipefail

# 探测 PROJECT_ROOT 与缓存目录（兼容非 git 场景，回落 cwd）
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
CACHE_DIR="${PROJECT_ROOT}/.cache/spec-autopilot"
mkdir -p "$CACHE_DIR"
HEALTH_REPORT_FILE="$CACHE_DIR/test-health-report.json"

TESTS_DIR="plugins/spec-autopilot/tests"
MUTATION_REPORT="$CACHE_DIR/mutation-report.json"
THRESHOLD=60

while [ $# -gt 0 ]; do
  case "$1" in
    --tests-dir)
      TESTS_DIR="${2:-}"
      shift 2
      ;;
    --mutation-report)
      MUTATION_REPORT="${2:-}"
      shift 2
      ;;
    --threshold)
      THRESHOLD="${2:-60}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

write_empty_report() {
  local msg="$1"
  cat >"$HEALTH_REPORT_FILE" <<EOF
{
  "overall_score": 0,
  "metrics": {
    "assertion_density": 0,
    "weak_ratio": 0,
    "duplicate_ratio": 0,
    "age_distribution": {},
    "kill_rate": null
  },
  "files": [],
  "error": "$msg"
}
EOF
  echo "WARN: $msg" >&2
  echo "HEALTH_SCORE=0"
}

if [ ! -d "$TESTS_DIR" ]; then
  write_empty_report "tests directory empty or missing"
  exit 0
fi

# 收集 test 文件（maxdepth 3）
FILES_TMP=$(mktemp)
# shellcheck disable=SC2064
trap "rm -f '$FILES_TMP'" EXIT
find "$TESTS_DIR" -maxdepth 3 -type f -name 'test_*.sh' 2>/dev/null | sort >"$FILES_TMP"

if [ ! -s "$FILES_TMP" ]; then
  write_empty_report "tests directory empty or no test_*.sh files"
  exit 0
fi

# 把 kill_rate 导出给 python
export TEST_HEALTH_MUTATION_REPORT="$MUTATION_REPORT"
export TEST_HEALTH_FILES_LIST="$FILES_TMP"
export TEST_HEALTH_THRESHOLD="$THRESHOLD"
export TEST_HEALTH_REPORT_FILE="$HEALTH_REPORT_FILE"

python3 <<'PYEOF'
import json
import os
import re
import subprocess
import sys
import time

files_list = os.environ["TEST_HEALTH_FILES_LIST"]
mutation_report = os.environ.get("TEST_HEALTH_MUTATION_REPORT", ".mutation-report.json")
threshold = float(os.environ.get("TEST_HEALTH_THRESHOLD", "60"))
report_file = os.environ.get("TEST_HEALTH_REPORT_FILE", ".test-health-report.json")

with open(files_list) as f:
    files = [line.strip() for line in f if line.strip()]

total_files = len(files)

# 读入 mutation kill_rate
kill_rate = None
if os.path.isfile(mutation_report):
    try:
        with open(mutation_report) as fh:
            d = json.load(fh)
        kr = d.get("overall_kill_rate")
        if kr is not None:
            kill_rate = float(kr)
    except Exception:
        kill_rate = None

total_assertions = 0
total_sloc = 0
weak_files = 0
case_names = {}
file_details = []
age_buckets = {"<30d": 0, "30-180d": 0, ">180d": 0, "unknown": 0}

now = int(time.time())

def first_commit_age_days(path):
    try:
        out = subprocess.check_output(
            ["git", "log", "--diff-filter=A", "--follow", "--format=%at", "--", path],
            stderr=subprocess.DEVNULL,
        ).decode().strip().splitlines()
        if not out:
            return None
        ts = int(out[-1])
        return (now - ts) // 86400
    except Exception:
        return None

weak_patterns = [re.compile(r"\bexit\s+\d")]
strong_patterns = [
    re.compile(r"assert_"),
    re.compile(r"\bif\s+\["),
    re.compile(r"\bcase\s+"),
    re.compile(r"grep\s"),
    re.compile(r"\[\s+.*\]"),
]

for path in files:
    try:
        with open(path, "r", errors="replace") as fh:
            lines = fh.readlines()
    except Exception:
        continue

    sloc = 0
    assertions = 0
    strong_hits = 0
    weak_hits = 0

    for line in lines:
        s = line.strip()
        if not s:
            continue
        # case 名称采集（注释里的 # Case: xxx）
        m = re.match(r"#\s*Case:\s*(\S+)", line)
        if m:
            case_names.setdefault(m.group(1), []).append(path)
        if s.startswith("#"):
            continue
        sloc += 1
        if re.search(r"assert_", s) or re.search(r"\bif\s+\[", s):
            assertions += 1
        for p in strong_patterns:
            if p.search(s):
                strong_hits += 1
                break
        for p in weak_patterns:
            if p.search(s):
                weak_hits += 1
                break

    total_assertions += assertions
    total_sloc += sloc

    is_weak = (strong_hits == 0 and weak_hits > 0) or assertions == 0
    if is_weak:
        weak_files += 1

    age = first_commit_age_days(path)
    if age is None:
        age_buckets["unknown"] += 1
    elif age < 30:
        age_buckets["<30d"] += 1
    elif age <= 180:
        age_buckets["30-180d"] += 1
    else:
        age_buckets[">180d"] += 1

    density = (assertions / sloc) if sloc > 0 else 0.0
    file_details.append({
        "file": path,
        "sloc": sloc,
        "assertions": assertions,
        "density": round(density, 3),
        "is_weak": is_weak,
        "age_days": age,
    })

# 重复 case 统计
all_cases = sum(len(v) for v in case_names.values())
dup_cases = sum(len(v) for v in case_names.values() if len(v) >= 2)

assertion_density = round(total_assertions / total_sloc, 3) if total_sloc > 0 else 0.0
weak_ratio = round(weak_files / total_files, 3) if total_files > 0 else 0.0
duplicate_ratio = round(dup_cases / all_cases, 3) if all_cases > 0 else 0.0

# 加权
if kill_rate is None:
    w_ad, w_wr, w_dr, w_kr = 0.43, 0.36, 0.21, 0.0
else:
    w_ad, w_wr, w_dr, w_kr = 0.30, 0.25, 0.15, 0.30

ad_score = min(100.0, (assertion_density / 2.0) * 100.0)
wr_score = (1 - weak_ratio) * 100.0
dr_score = (1 - duplicate_ratio) * 100.0
kr_score = (kill_rate if kill_rate is not None else 0.0) * 100.0

overall = round(w_ad * ad_score + w_wr * wr_score + w_dr * dr_score + w_kr * kr_score, 1)

top_weak = sorted(file_details, key=lambda x: (x["density"], -x["sloc"]))[:10]

report = {
    "overall_score": overall,
    "metrics": {
        "assertion_density": assertion_density,
        "weak_ratio": weak_ratio,
        "duplicate_ratio": duplicate_ratio,
        "age_distribution": age_buckets,
        "kill_rate": kill_rate,
    },
    "files_total": total_files,
    "top_weak": top_weak,
}

with open(report_file, "w") as fh:
    json.dump(report, fh, indent=2)

print(f"HEALTH_SCORE={overall}")
if overall < threshold:
    print("HEALTH_BELOW_THRESHOLD=1")
PYEOF

exit 0
