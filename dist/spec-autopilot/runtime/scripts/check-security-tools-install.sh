#!/usr/bin/env bash
# check-security-tools-install.sh
# Pre-check for security scanning toolchain. Returns JSON on stdout.
# Usage: bash check-security-tools-install.sh [project_root]
# Checks: npm_audit, gitleaks, semgrep, trivy, owasp_dc
# Exit: always 0 (informational). Consumers read the JSON to decide.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_common.sh"

PROJECT_ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

# Require python3 for JSON output
if ! command -v python3 &>/dev/null; then
  echo '{"error":"python3 not found","all_basic_installed":false}'
  exit 0
fi

python3 -c "
import json, subprocess, sys, os, re

project_root = sys.argv[1]
result = {
    'npm_audit':  {'installed': False, 'method': None, 'version': None},
    'gitleaks':   {'installed': False, 'version': None},
    'semgrep':    {'installed': False, 'version': None},
    'trivy':      {'installed': False, 'version': None},
    'owasp_dc':   {'installed': False, 'recommended': False},
    'all_basic_installed': False,
    'missing': [],
    'install_commands': [],
    'recommended_scans': [],
}

def run_cmd(cmd, timeout=10):
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        if out.returncode == 0 and (out.stdout.strip() or out.stderr.strip()):
            return True, (out.stdout.strip() or out.stderr.strip())
    except (FileNotFoundError, subprocess.TimeoutExpired, OSError):
        pass
    return False, None

def extract_version(text):
    if not text:
        return None
    m = re.search(r'(\d+\.\d+[\.\d]*)', text)
    return m.group(1) if m else text.split('\n')[0].strip()

# --- 1. Check npm_audit (pnpm preferred, npm fallback) ---
ok, out = run_cmd(['pnpm', '--version'])
if ok:
    result['npm_audit'] = {
        'installed': True,
        'method': 'pnpm',
        'version': extract_version(out),
    }
else:
    ok, out = run_cmd(['npm', '--version'])
    if ok:
        result['npm_audit'] = {
            'installed': True,
            'method': 'npm',
            'version': extract_version(out),
        }

if result['npm_audit']['installed']:
    result['recommended_scans'].append('npm_audit')
else:
    result['missing'].append('npm_audit')
    result['install_commands'].append('brew install pnpm')

# --- 2. Check gitleaks ---
ok, out = run_cmd(['gitleaks', 'version'])
if ok:
    result['gitleaks'] = {
        'installed': True,
        'version': extract_version(out),
    }
else:
    result['missing'].append('gitleaks')
    result['install_commands'].append('brew install gitleaks')

# --- 3. Check semgrep ---
ok, out = run_cmd(['semgrep', '--version'], timeout=15)
if ok:
    result['semgrep'] = {
        'installed': True,
        'version': extract_version(out),
    }
else:
    result['missing'].append('semgrep')
    result['install_commands'].append('pip3 install semgrep')

# --- 4. Check trivy ---
ok, out = run_cmd(['trivy', '--version'])
if ok:
    result['trivy'] = {
        'installed': True,
        'version': extract_version(out),
    }
else:
    result['missing'].append('trivy')
    result['install_commands'].append('brew install trivy')

# --- 5. Check OWASP Dependency-Check (conditional) ---
backend_gradle = os.path.join(project_root, 'backend', 'build.gradle')
backend_gradle_kts = os.path.join(project_root, 'backend', 'build.gradle.kts')
has_gradle = os.path.isfile(backend_gradle) or os.path.isfile(backend_gradle_kts)

if has_gradle:
    result['owasp_dc']['recommended'] = True
    # Check if dependency-check CLI is available
    ok, out = run_cmd(['dependency-check', '--version'], timeout=15)
    if ok:
        result['owasp_dc'] = {
            'installed': True,
            'recommended': True,
            'version': extract_version(out),
        }
    else:
        # Check if Gradle plugin is configured
        for gf in [backend_gradle_kts, backend_gradle]:
            if os.path.isfile(gf):
                try:
                    with open(gf) as f:
                        content = f.read()
                    if 'dependency-check' in content.lower() or 'owasp' in content.lower():
                        result['owasp_dc'] = {
                            'installed': True,
                            'recommended': True,
                            'note': 'OWASP plugin found in Gradle build file',
                        }
                        break
                except Exception:
                    pass
        if not result['owasp_dc'].get('installed'):
            result['install_commands'].append('brew install dependency-check')

# --- Summary ---
basic_tools = ['npm_audit', 'gitleaks', 'semgrep', 'trivy']
result['all_basic_installed'] = all(
    result[t]['installed'] for t in basic_tools
)

print(json.dumps(result, indent=2))
" "$PROJECT_ROOT"

exit 0
