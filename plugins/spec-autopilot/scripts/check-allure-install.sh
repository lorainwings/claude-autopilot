#!/usr/bin/env bash
# check-allure-install.sh
# Purpose: Deterministic pre-check for Allure reporting toolchain.
# Returns JSON on stdout with component-level install status.
#
# Usage: bash check-allure-install.sh [project_root]
#
# Components checked:
#   1. Allure CLI (npx allure / allure commandline)
#   2. allure-playwright (npm package in tests/e2e)
#   3. allure-pytest (pip package)
#   4. Allure Gradle Plugin (optional, for JUnit→Allure conversion)
#
# Output: JSON object:
#   {
#     "allure_cli": { "installed": true, "version": "3.3.1", "method": "npx" },
#     "allure_playwright": { "installed": true, "version": "3.5.0" },
#     "allure_pytest": { "installed": true, "version": "2.15.3" },
#     "allure_gradle": { "installed": false, "note": "JUnit XML will be converted" },
#     "all_required_installed": true,
#     "missing": [],
#     "install_commands": []
#   }
#
# Exit: always 0 (informational). Consumers read the JSON to decide.

set -uo pipefail

PROJECT_ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

# Require python3 for JSON output
if ! command -v python3 &>/dev/null; then
  echo '{"error":"python3 not found","all_required_installed":false}'
  exit 0
fi

python3 -c "
import json
import subprocess
import sys
import os
import re

project_root = sys.argv[1]
result = {
    'allure_cli': {'installed': False, 'version': None, 'method': None},
    'allure_playwright': {'installed': False, 'version': None},
    'allure_pytest': {'installed': False, 'version': None},
    'allure_gradle': {'installed': False, 'note': None},
    'all_required_installed': False,
    'missing': [],
    'install_commands': [],
}

# --- 1. Check Allure CLI ---
# Try npx allure first (most common in Node projects)
try:
    out = subprocess.run(
        ['npx', 'allure', '--version'],
        capture_output=True, text=True, timeout=15,
        cwd=project_root
    )
    if out.returncode == 0 and out.stdout.strip():
        result['allure_cli'] = {
            'installed': True,
            'version': out.stdout.strip().split('\n')[0],
            'method': 'npx',
        }
except Exception:
    pass

# Fallback: global allure command
if not result['allure_cli']['installed']:
    try:
        out = subprocess.run(
            ['allure', '--version'],
            capture_output=True, text=True, timeout=10
        )
        if out.returncode == 0 and out.stdout.strip():
            result['allure_cli'] = {
                'installed': True,
                'version': out.stdout.strip().split('\n')[0],
                'method': 'global',
            }
    except FileNotFoundError:
        pass
    except Exception:
        pass

if not result['allure_cli']['installed']:
    result['missing'].append('allure-cli')
    result['install_commands'].append('pnpm add -D allure')

# --- 2. Check allure-playwright ---
# Check in tests/e2e/node_modules or project root node_modules
for pkg_dir in [
    os.path.join(project_root, 'tests', 'e2e'),
    project_root,
]:
    pkg_json = os.path.join(pkg_dir, 'node_modules', 'allure-playwright', 'package.json')
    if os.path.isfile(pkg_json):
        try:
            with open(pkg_json) as f:
                data = json.load(f)
            result['allure_playwright'] = {
                'installed': True,
                'version': data.get('version', 'unknown'),
            }
            break
        except Exception:
            pass

# Also check via package.json devDependencies
if not result['allure_playwright']['installed']:
    for pkg_json_path in [
        os.path.join(project_root, 'tests', 'e2e', 'package.json'),
        os.path.join(project_root, 'package.json'),
    ]:
        if os.path.isfile(pkg_json_path):
            try:
                with open(pkg_json_path) as f:
                    data = json.load(f)
                deps = {**data.get('dependencies', {}), **data.get('devDependencies', {})}
                if 'allure-playwright' in deps:
                    version = deps['allure-playwright'].lstrip('^~>=')
                    result['allure_playwright'] = {
                        'installed': True,
                        'version': version,
                        'note': 'declared in package.json, run pnpm install if missing from node_modules',
                    }
                    break
            except Exception:
                pass

if not result['allure_playwright']['installed']:
    result['missing'].append('allure-playwright')
    result['install_commands'].append('cd tests/e2e && pnpm add -D allure-playwright')

# --- 3. Check allure-pytest ---
try:
    out = subprocess.run(
        ['python3', '-c', 'import allure; print(allure.__version__ if hasattr(allure, \"__version__\") else \"installed\")'],
        capture_output=True, text=True, timeout=10
    )
    if out.returncode == 0:
        result['allure_pytest'] = {
            'installed': True,
            'version': out.stdout.strip() or 'unknown',
        }
except Exception:
    pass

# Also try pip show
if not result['allure_pytest']['installed']:
    try:
        out = subprocess.run(
            ['pip3', 'show', 'allure-pytest'],
            capture_output=True, text=True, timeout=10
        )
        if out.returncode == 0:
            version_match = re.search(r'Version:\s*(\S+)', out.stdout)
            result['allure_pytest'] = {
                'installed': True,
                'version': version_match.group(1) if version_match else 'unknown',
            }
    except Exception:
        pass

if not result['allure_pytest']['installed']:
    result['missing'].append('allure-pytest')
    result['install_commands'].append('pip3 install allure-pytest')

# --- 4. Check Allure Gradle Plugin (optional) ---
build_file = os.path.join(project_root, 'backend', 'build.gradle.kts')
if os.path.isfile(build_file):
    try:
        with open(build_file) as f:
            content = f.read()
        if 'allure' in content.lower():
            result['allure_gradle'] = {
                'installed': True,
                'note': 'Allure plugin found in build.gradle.kts',
            }
        else:
            result['allure_gradle'] = {
                'installed': False,
                'note': 'JUnit XML output will be converted to Allure format via allure-results/',
            }
    except Exception:
        result['allure_gradle'] = {
            'installed': False,
            'note': 'Could not read build.gradle.kts',
        }
else:
    result['allure_gradle'] = {
        'installed': False,
        'note': 'No build.gradle.kts found',
    }

# --- Summary ---
required_components = ['allure_cli', 'allure_playwright', 'allure_pytest']
result['all_required_installed'] = all(
    result[c]['installed'] for c in required_components
)

print(json.dumps(result, indent=2))
" "$PROJECT_ROOT"

exit 0
