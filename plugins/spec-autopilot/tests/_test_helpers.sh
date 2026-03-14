#!/usr/bin/env bash
# _test_helpers.sh — Shared assertion functions for spec-autopilot test suite
# Extracted from test-hooks.sh:15-50

PASS=0
FAIL=0

green() { printf "\033[32m%s\033[0m\n" "$1"; }
red()   { printf "\033[31m%s\033[0m\n" "$1"; }

assert_exit() {
  local name="$1" expected="$2" actual="$3"
  if [ "$actual" -eq "$expected" ]; then
    green "  PASS: $name (exit $actual)"
    PASS=$((PASS + 1))
  else
    red "  FAIL: $name (expected exit $expected, got $actual)"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local name="$1" haystack="$2" needle="$3"
  if echo "$haystack" | grep -q "$needle"; then
    green "  PASS: $name (contains '$needle')"
    PASS=$((PASS + 1))
  else
    red "  FAIL: $name (missing '$needle')"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local name="$1" haystack="$2" needle="$3"
  if ! echo "$haystack" | grep -q "$needle"; then
    green "  PASS: $name (correctly missing '$needle')"
    PASS=$((PASS + 1))
  else
    red "  FAIL: $name (unexpectedly contains '$needle')"
    FAIL=$((FAIL + 1))
  fi
}

assert_json_field() {
  local name="$1" json="$2" field="$3" expected="$4"
  local actual
  actual=$(echo "$json" | python3 -c "import json,sys; print(json.load(sys.stdin).get('$field',''))" 2>/dev/null || echo "")
  if [ "$actual" = "$expected" ]; then
    green "  PASS: $name (.$field == '$expected')"
    PASS=$((PASS + 1))
  else
    red "  FAIL: $name (.$field: expected '$expected', got '$actual')"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_exists() {
  local name="$1" filepath="$2"
  if [ -f "$filepath" ]; then
    green "  PASS: $name (file exists)"
    PASS=$((PASS + 1))
  else
    red "  FAIL: $name (file not found: $filepath)"
    FAIL=$((FAIL + 1))
  fi
}
