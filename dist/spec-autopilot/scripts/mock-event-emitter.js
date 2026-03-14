#!/usr/bin/env node
/**
 * mock-event-emitter.js
 * 模拟事件发射器，用于测试 GUI 组件
 *
 * 用法: node scripts/mock-event-emitter.js [--project-root <path>]
 */

const fs = require("fs");
const path = require("path");

const args = process.argv.slice(2);
let projectRoot = process.cwd();

for (let i = 0; i < args.length; i++) {
  if (args[i] === "--project-root" && args[i + 1]) {
    projectRoot = path.resolve(args[++i]);
  }
}

const logsDir = path.join(projectRoot, "logs");
const eventsFile = path.join(logsDir, "events.jsonl");
const sequenceFile = path.join(logsDir, ".event_sequence");

// 确保目录存在
if (!fs.existsSync(logsDir)) {
  fs.mkdirSync(logsDir, { recursive: true });
}

let sequence = 0;
if (fs.existsSync(sequenceFile)) {
  sequence = parseInt(fs.readFileSync(sequenceFile, "utf-8").trim()) || 0;
}

function emitEvent(event) {
  sequence++;
  const fullEvent = {
    ...event,
    sequence,
    timestamp: new Date().toISOString(),
    change_name: "mock-feature",
    session_id: "mock-session-001",
  };

  fs.appendFileSync(eventsFile, JSON.stringify(fullEvent) + "\n");
  fs.writeFileSync(sequenceFile, String(sequence));
  console.log(`[${sequence}] ${event.type} | Phase ${event.phase}`);
}

console.log("🎭 Mock Event Emitter 启动");
console.log(`   输出: ${eventsFile}\n`);

// Phase 0: Environment Setup
setTimeout(() => {
  emitEvent({
    type: "phase_start",
    phase: 0,
    mode: "full",
    phase_label: "Environment Setup",
    total_phases: 8,
    payload: {},
  });
}, 1000);

setTimeout(() => {
  emitEvent({
    type: "phase_end",
    phase: 0,
    mode: "full",
    phase_label: "Environment Setup",
    total_phases: 8,
    payload: { status: "ok", duration_ms: 2000 },
  });
}, 3000);

// Phase 5: 模拟 3 个并发任务
const tasks = [
  { name: "frontend-auth", index: 1 },
  { name: "backend-api", index: 2 },
  { name: "database-schema", index: 3 },
];

setTimeout(() => {
  emitEvent({
    type: "phase_start",
    phase: 5,
    mode: "full",
    phase_label: "Implementation",
    total_phases: 8,
    payload: {},
  });

  // 启动所有任务
  tasks.forEach((task) => {
    emitEvent({
      type: "task_progress",
      phase: 5,
      mode: "full",
      phase_label: "Implementation",
      total_phases: 8,
      payload: {
        task_name: task.name,
        task_index: task.index,
        task_total: 3,
        status: "running",
        tdd_step: "red",
      },
    });
  });
}, 5000);

// TDD 步骤模拟
setTimeout(() => {
  emitEvent({
    type: "task_progress",
    phase: 5,
    mode: "full",
    phase_label: "Implementation",
    total_phases: 8,
    payload: {
      task_name: "frontend-auth",
      task_index: 1,
      task_total: 3,
      status: "running",
      tdd_step: "green",
    },
  });
}, 7000);

setTimeout(() => {
  emitEvent({
    type: "task_progress",
    phase: 5,
    mode: "full",
    phase_label: "Implementation",
    total_phases: 8,
    payload: {
      task_name: "frontend-auth",
      task_index: 1,
      task_total: 3,
      status: "passed",
      tdd_step: "refactor",
    },
  });
}, 9000);

// 模拟一个失败任务
setTimeout(() => {
  emitEvent({
    type: "task_progress",
    phase: 5,
    mode: "full",
    phase_label: "Implementation",
    total_phases: 8,
    payload: {
      task_name: "backend-api",
      task_index: 2,
      task_total: 3,
      status: "failed",
      retry_count: 1,
    },
  });
}, 10000);

// Gate Block 事件
setTimeout(() => {
  emitEvent({
    type: "gate_block",
    phase: 6,
    mode: "full",
    phase_label: "Testing",
    total_phases: 8,
    payload: {
      gate_score: "5/8",
      status: "blocked",
      error_message: "Test coverage below threshold (65% < 80%)",
    },
  });
  console.log("\n🚫 Gate Block 已触发 — 请在 GUI 中测试决策按钮\n");
}, 15000);

console.log("⏱️  事件时间线:");
console.log("   1s  - Phase 0 开始");
console.log("   3s  - Phase 0 结束");
console.log("   5s  - Phase 5 开始 + 3 个并发任务启动");
console.log("   7s  - frontend-auth 进入 GREEN");
console.log("   9s  - frontend-auth 完成");
console.log("   10s - backend-api 失败");
console.log("   15s - Gate Block 触发\n");
