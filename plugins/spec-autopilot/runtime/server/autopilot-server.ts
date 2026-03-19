#!/usr/bin/env bun
/// <reference types="bun" />
/// <reference types="node" />
/**
 * autopilot-server.ts — 入口 shim
 * 实际逻辑已拆分到 src/ 模块化目录。
 */

import { startServer } from "./src/bootstrap";

startServer().catch((err) => {
  console.error("  ❌ 服务器启动失败:", err);
  process.exit(1);
});
