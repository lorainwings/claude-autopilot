#!/usr/bin/env python3
"""_phase_graph.py — 唯一权威的 phase 推断库

所有需要 phase 推断的脚本（scan-checkpoints-on-start, save-state-before-compact,
recovery-decision, _common.sh）统一调用此库，确保 gap-aware 语义一致。

用法（CLI）：
    python3 _phase_graph.py get_phase_sequence <mode>
    python3 _phase_graph.py get_last_valid <phase_results_dir> [mode]
    python3 _phase_graph.py get_next_phase <last_valid> [mode]
    python3 _phase_graph.py get_gap_phases <phase_results_dir> [mode]
    python3 _phase_graph.py scan_checkpoints <phase_results_dir> [mode]

用法（Python import）：
    from _phase_graph import get_phase_sequence, get_last_valid_phase, ...
"""

import json
import os
import sys
import glob


# ── Phase 序列定义 ──────────────────────────────────────────

PHASE_SEQUENCES = {
    'full':    [1, 2, 3, 4, 5, 6, 7],
    'lite':    [1, 5, 6, 7],
    'minimal': [1, 5, 7],
}

PHASE_LABELS = {
    0: 'Environment Setup',
    1: 'Requirements',
    2: 'OpenSpec',
    3: 'Fast-Forward',
    4: 'Test Design',
    5: 'Implementation',
    6: 'Test Report',
    7: 'Archive',
}


def get_phase_sequence(mode: str) -> list:
    """返回 mode-aware phase 序列"""
    return list(PHASE_SEQUENCES.get(mode, PHASE_SEQUENCES['full']))


def _find_best_checkpoint(phase_results_dir: str, phase_num: int) -> dict:
    """查找指定 phase 的最佳 checkpoint 文件，返回 {file, status, data} 或 None。
    排除 .tmp / -progress.json / -interim.json。"""
    pattern = os.path.join(phase_results_dir, f'phase-{phase_num}-*.json')
    files = sorted(glob.glob(pattern), key=lambda f: os.path.getmtime(f), reverse=True)
    files = [f for f in files if not f.endswith('.tmp')
             and not f.endswith('-progress.json')
             and not f.endswith('-interim.json')]
    if not files:
        return None
    try:
        with open(files[0]) as fh:
            data = json.load(fh)
        return {
            'file': os.path.basename(files[0]),
            'status': data.get('status', 'unknown'),
            'data': data,
        }
    except (json.JSONDecodeError, OSError):
        return {'file': os.path.basename(files[0]), 'status': 'error', 'data': None}


def scan_checkpoints(phase_results_dir: str, mode: str = 'full') -> list:
    """扫描 checkpoints，返回 [{phase, file, status}]（所有 phase，含 missing）"""
    phases = get_phase_sequence(mode)
    results = []
    for p in phases:
        cp = _find_best_checkpoint(phase_results_dir, p)
        if cp:
            results.append({'phase': p, 'file': cp['file'], 'status': cp['status']})
        else:
            results.append({'phase': p, 'file': None, 'status': 'missing'})
    return results


def get_last_valid_phase(phase_results_dir: str, mode: str = 'full') -> int:
    """返回最后一个连续有效 phase（停于第一个 gap）。

    语义：从 phase 序列第一个开始，遇到非 ok/warning 的 phase 立即 break。
    这与 _common.sh::get_last_valid_phase() 和 recovery-decision.sh 的 gap-aware 逻辑一致。
    """
    phases = get_phase_sequence(mode)
    last_valid = 0
    for p in phases:
        cp = _find_best_checkpoint(phase_results_dir, p)
        if cp and cp['status'] in ('ok', 'warning'):
            last_valid = p
        else:
            if last_valid > 0:
                break  # gap：之前有有效 phase，当前无效 → 停止
            # 如果 last_valid==0 且当前 phase 缺失，继续（可能还没开始）
            # 但第一个 phase 就 missing 的话，last_valid 保持 0
            break
    return last_valid


def get_next_phase(last_valid: int, mode: str = 'full') -> int:
    """返回 last_valid 之后的下一个 phase（基于 mode-aware graph），或 None 表示全部完成"""
    phases = get_phase_sequence(mode)
    if last_valid == 0:
        return phases[0] if phases else None
    found = False
    for p in phases:
        if found:
            return p
        if p == last_valid:
            found = True
    return None  # all done


def get_gap_phases(phase_results_dir: str, mode: str = 'full') -> list:
    """返回第一个有效 phase 之后的所有 gap phase（missing/failed/error）"""
    phases = get_phase_sequence(mode)
    gaps = []
    first_valid_seen = False
    for p in phases:
        cp = _find_best_checkpoint(phase_results_dir, p)
        if cp and cp['status'] in ('ok', 'warning'):
            if not first_valid_seen:
                first_valid_seen = True
            # 有效 phase 出现在 gap 之后：不推进 last_valid，但也不再加 gap
        else:
            if first_valid_seen:
                gaps.append(p)
    return gaps


def first_incomplete_phase(phase_results_dir: str, mode: str = 'full') -> int:
    """返回第一个非 ok/warning 的 phase（恢复起点）。所有完成时返回 None。"""
    phases = get_phase_sequence(mode)
    for p in phases:
        cp = _find_best_checkpoint(phase_results_dir, p)
        if not cp or cp['status'] not in ('ok', 'warning'):
            return p
    return None  # all done


# ── CLI 入口 ─────────────────────────────────────────────────

def _cli():
    if len(sys.argv) < 2:
        print("Usage: python3 _phase_graph.py <command> [args...]", file=sys.stderr)
        sys.exit(1)

    cmd = sys.argv[1]

    if cmd == 'get_phase_sequence':
        mode = sys.argv[2] if len(sys.argv) > 2 else 'full'
        print(json.dumps(get_phase_sequence(mode)))

    elif cmd == 'get_last_valid':
        phase_results_dir = sys.argv[2]
        mode = sys.argv[3] if len(sys.argv) > 3 else 'full'
        print(get_last_valid_phase(phase_results_dir, mode))

    elif cmd == 'get_next_phase':
        last_valid = int(sys.argv[2])
        mode = sys.argv[3] if len(sys.argv) > 3 else 'full'
        result = get_next_phase(last_valid, mode)
        print(result if result is not None else 'done')

    elif cmd == 'get_gap_phases':
        phase_results_dir = sys.argv[2]
        mode = sys.argv[3] if len(sys.argv) > 3 else 'full'
        print(json.dumps(get_gap_phases(phase_results_dir, mode)))

    elif cmd == 'scan_checkpoints':
        phase_results_dir = sys.argv[2]
        mode = sys.argv[3] if len(sys.argv) > 3 else 'full'
        print(json.dumps(scan_checkpoints(phase_results_dir, mode)))

    elif cmd == 'first_incomplete':
        phase_results_dir = sys.argv[2]
        mode = sys.argv[3] if len(sys.argv) > 3 else 'full'
        result = first_incomplete_phase(phase_results_dir, mode)
        print(result if result is not None else 'done')

    elif cmd == '--test':
        _run_self_tests()

    else:
        print(f"Unknown command: {cmd}", file=sys.stderr)
        sys.exit(1)


def _run_self_tests():
    """内置自测"""
    import tempfile
    passed = 0
    failed = 0

    def assert_eq(label, actual, expected):
        nonlocal passed, failed
        if actual == expected:
            passed += 1
            print(f"  PASS: {label}")
        else:
            failed += 1
            print(f"  FAIL: {label}: expected {expected!r}, got {actual!r}")

    # Test 1: phase sequences
    assert_eq("full sequence", get_phase_sequence('full'), [1, 2, 3, 4, 5, 6, 7])
    assert_eq("lite sequence", get_phase_sequence('lite'), [1, 5, 6, 7])
    assert_eq("minimal sequence", get_phase_sequence('minimal'), [1, 5, 7])
    assert_eq("unknown defaults to full", get_phase_sequence('unknown'), [1, 2, 3, 4, 5, 6, 7])

    # Test 2: gap-aware last_valid
    with tempfile.TemporaryDirectory() as tmpdir:
        # P1=ok, P2=ok, P3=missing → last_valid=2
        for p, st in [(1, 'ok'), (2, 'ok')]:
            with open(os.path.join(tmpdir, f'phase-{p}-test.json'), 'w') as f:
                json.dump({'status': st, 'summary': 'test'}, f)
        assert_eq("gap-aware: P1=ok P2=ok P3=missing → last_valid=2",
                   get_last_valid_phase(tmpdir, 'full'), 2)

    with tempfile.TemporaryDirectory() as tmpdir:
        # P1=ok, P2=failed, P3=ok → last_valid=1 (stops at gap)
        for p, st in [(1, 'ok'), (2, 'failed'), (3, 'ok')]:
            with open(os.path.join(tmpdir, f'phase-{p}-test.json'), 'w') as f:
                json.dump({'status': st, 'summary': 'test'}, f)
        assert_eq("gap-aware: P1=ok P2=failed P3=ok → last_valid=1",
                   get_last_valid_phase(tmpdir, 'full'), 1)

    with tempfile.TemporaryDirectory() as tmpdir:
        # all missing → last_valid=0
        assert_eq("all missing → last_valid=0",
                   get_last_valid_phase(tmpdir, 'full'), 0)

    # Test 3: next_phase
    assert_eq("next after 2 (full) → 3", get_next_phase(2, 'full'), 3)
    assert_eq("next after 7 (full) → None", get_next_phase(7, 'full'), None)
    assert_eq("next after 0 (full) → 1", get_next_phase(0, 'full'), 1)
    assert_eq("next after 1 (lite) → 5", get_next_phase(1, 'lite'), 5)
    assert_eq("next after 5 (minimal) → 7", get_next_phase(5, 'minimal'), 7)

    # Test 4: gap_phases
    with tempfile.TemporaryDirectory() as tmpdir:
        for p, st in [(1, 'ok'), (2, 'ok'), (4, 'ok')]:
            with open(os.path.join(tmpdir, f'phase-{p}-test.json'), 'w') as f:
                json.dump({'status': st, 'summary': 'test'}, f)
        gaps = get_gap_phases(tmpdir, 'full')
        assert_eq("gap_phases: P1=ok P2=ok P3=missing P4=ok P5-P7=missing → gaps=[3,5,6,7]",
                   gaps, [3, 5, 6, 7])

    # Test 5: first_incomplete
    with tempfile.TemporaryDirectory() as tmpdir:
        for p, st in [(1, 'ok'), (2, 'ok')]:
            with open(os.path.join(tmpdir, f'phase-{p}-test.json'), 'w') as f:
                json.dump({'status': st, 'summary': 'test'}, f)
        assert_eq("first_incomplete: P1=ok P2=ok → 3",
                   first_incomplete_phase(tmpdir, 'full'), 3)

    with tempfile.TemporaryDirectory() as tmpdir:
        for p in [1, 2, 3, 4, 5, 6, 7]:
            with open(os.path.join(tmpdir, f'phase-{p}-test.json'), 'w') as f:
                json.dump({'status': 'ok', 'summary': 'test'}, f)
        assert_eq("first_incomplete: all ok → None",
                   first_incomplete_phase(tmpdir, 'full'), None)

    # Test 6: mode-aware — lite mode skips P2-P4
    with tempfile.TemporaryDirectory() as tmpdir:
        for p, st in [(1, 'ok'), (5, 'ok')]:
            with open(os.path.join(tmpdir, f'phase-{p}-test.json'), 'w') as f:
                json.dump({'status': st, 'summary': 'test'}, f)
        assert_eq("lite: P1=ok P5=ok → last_valid=5",
                   get_last_valid_phase(tmpdir, 'lite'), 5)
        assert_eq("lite: P1=ok P5=ok → next=6",
                   get_next_phase(5, 'lite'), 6)

    print(f"\n结果: {passed} passed, {failed} failed")
    sys.exit(1 if failed > 0 else 0)


if __name__ == '__main__':
    _cli()
