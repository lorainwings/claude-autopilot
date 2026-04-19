# Changelog

All notable changes to parallel-harness will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.9.0](https://github.com/lorainwings/claude-autopilot/compare/parallel-harness-v1.8.2...parallel-harness-v1.9.0) (2026-04-19)


### Added

* **spec-autopilot:** Phase 1 三路调研独立 agent 配置（auto_scan/research/web_search） ([487858c](https://github.com/lorainwings/claude-autopilot/commit/487858c01612a888049dd300838319fc3f4a8657))

## [1.8.2](https://github.com/lorainwings/claude-autopilot/compare/parallel-harness-v1.8.1...parallel-harness-v1.8.2) (2026-04-18)


### Changed

* **repo:** 治理仓库根目录污染、拆分 CLAUDE.md、修复乱码与冗余清理 ([74d3972](https://github.com/lorainwings/claude-autopilot/commit/74d3972c1c26e29a1d90c0886ec1b5231cb9a789))

## [1.8.1](https://github.com/lorainwings/claude-autopilot/compare/parallel-harness-v1.8.0...parallel-harness-v1.8.1) (2026-04-15)


### Fixed

* **parallel-harness:** correct $schema URL in statusline config installer ([c6ecc70](https://github.com/lorainwings/claude-autopilot/commit/c6ecc700372d15bf4359b2345bd9c04fb1da54a2))

## [1.8.0](https://github.com/lorainwings/claude-autopilot/compare/parallel-harness-v1.7.0...parallel-harness-v1.8.0) (2026-04-14)


### Added

* **parallel-harness,spec-autopilot:** 优化持久化目录结构 + Phase 6 Allure 服务前移 ([a35fa54](https://github.com/lorainwings/claude-autopilot/commit/a35fa544b4956643c3f588b0736fc5db2a070ea3))


### Fixed

* **spec-autopilot,parallel-harness:** 修复 5 项插件污染与配置问题 ([9e696c2](https://github.com/lorainwings/claude-autopilot/commit/9e696c2d05e0410c4d4f84a272696a5331eb25f2))

## [1.7.0](https://github.com/lorainwings/claude-autopilot/compare/parallel-harness-v1.6.1...parallel-harness-v1.7.0) (2026-04-12)


### Added

* **parallel-harness:** 8 workstream 全量修复 + codex 审查 13 项问题闭环 ([a926a12](https://github.com/lorainwings/claude-autopilot/commit/a926a1298fd19b3923858097876ea9294ba9c356))
* **parallel-harness:** add skill lifecycle runtime with registry, observability and phase inference ([8a39f01](https://github.com/lorainwings/claude-autopilot/commit/8a39f01c235ed70bc7cb1aa7eb8eb46301531716))
* **parallel-harness:** P0 增强蓝图 6 项实施 — 295 pass / 649 expect ([68a9d47](https://github.com/lorainwings/claude-autopilot/commit/68a9d472de30c9e2c6cdf87c58fec0393426537c))
* **parallel-harness:** P0/P1/P2 增强蓝图全量实施 — 415 pass / 866 expect ([67348be](https://github.com/lorainwings/claude-autopilot/commit/67348be4a3af51d4665db81f3a5a9efeabf06deb))
* **parallel-harness:** P2 增强全量实施 — 480 pass / 987 expect ([af8c18d](https://github.com/lorainwings/claude-autopilot/commit/af8c18d087f3e9eb2a2ddf06639d7a5cd65660dd))
* **parallel-harness:** 全量修复 10 个能力域 — 运行时正确性/所有权隔离/上下文/Gate/报告 ([31b1ad3](https://github.com/lorainwings/claude-autopilot/commit/31b1ad330dee6616e0186ef6bd2e3ac78c88bd2f))
* **parallel-harness:** 增加 skill 可观测性、hooks 机制与终态迁移防御 ([0785917](https://github.com/lorainwings/claude-autopilot/commit/078591714090861d32c5a62e4c3c5f114a0a71a9))
* **parallel-harness:** 增加 skill 可观测性、hooks 机制与终态迁移防御 ([67b3e1b](https://github.com/lorainwings/claude-autopilot/commit/67b3e1b8c2cde41d2a8b0af7968a0911ca85a751))


### Fixed

* add .parallel-harness marker dir in auto-install tests ([455230c](https://github.com/lorainwings/claude-autopilot/commit/455230c8c6f666986c6f0d15b766da98ed7f62a9))
* **ci:** CI pipeline overhaul — 分离构建与测试，消除 pre-commit 副作用 ([3759d03](https://github.com/lorainwings/claude-autopilot/commit/3759d03f2aa819b02fd68dc7428706e33135ccd8))
* **ci:** 抽取共享 lint 脚本消除本地/CI lint 漂移 ([ab03dac](https://github.com/lorainwings/claude-autopilot/commit/ab03dacbd7c3846c6747103716b8095f4e265615))
* **ci:** 统一 CI/release/lint 全流程一致性 ([9495d5e](https://github.com/lorainwings/claude-autopilot/commit/9495d5e1bff5563d39fc1c37c85fa3d545cb1ba8))
* codex 3 项缺陷修复 — dashboard 凭证泄露 + PR 精确暂存 + git diff untracked 盲区 ([ca858f4](https://github.com/lorainwings/claude-autopilot/commit/ca858f4a2f2226ab790c9e82893250d24423bca2))
* codex 5 项缺陷修复 — git-diff 精确差分 + PR fail-fast + dashboard 鉴权 + action 映射 + retryTask 桥接 ([29a3bfb](https://github.com/lorainwings/claude-autopilot/commit/29a3bfb3b5c999fc45e9d4513fbea55231b5899c))
* **hook:** pre-commit 测试仅对 spec-autopilot 变更触发，避免 parallel-harness 文档提交误跑测试套件 ([ee1fc3a](https://github.com/lorainwings/claude-autopilot/commit/ee1fc3a3e914d008ef938b1a3bd6848debf900a9))
* **parallel-harness:** approveAndResume 路径复用全集终态判定 ([f8b9798](https://github.com/lorainwings/claude-autopilot/commit/f8b9798702fd23fe9220aa496e30588b70618c5f))
* **parallel-harness:** plugin.json schema 合规性修复 ([1084796](https://github.com/lorainwings/claude-autopilot/commit/108479669a59616ecdd170b73e4cd5386696f946))
* **parallel-harness:** stabilize worktree lifecycle ([f7040a9](https://github.com/lorainwings/claude-autopilot/commit/f7040a967f927cda48f9616d0189524df0a5e6ac))
* **parallel-harness:** 为所有 SKILL.md 添加官方规范要求的 YAML frontmatter ([b08e3f6](https://github.com/lorainwings/claude-autopilot/commit/b08e3f6351995061bd2e1115181bddc31f17613a))
* **parallel-harness:** 主链闭环返修 — 10 项 review 问题全部修复 ([39710b0](https://github.com/lorainwings/claude-autopilot/commit/39710b0cc65d4eabff6a16831941924cb2539eb1))
* **parallel-harness:** 修复 statusLine bridge 在上游变更时未重新生成的问题 ([b7c572f](https://github.com/lorainwings/claude-autopilot/commit/b7c572f24411ab06da687aae7cdbb7bb2413ee38))
* **parallel-harness:** 重写 SKILL.md 为可执行协议，修复 skill 无法触发的问题 ([6bc0274](https://github.com/lorainwings/claude-autopilot/commit/6bc02740a3d3d9029799c16cf774c7e43eb05db0))
* **parallel-harness:** 重写 SKILL.md 为可执行协议，修复 skill 无法触发的问题 ([0c8bcc0](https://github.com/lorainwings/claude-autopilot/commit/0c8bcc016ebf224b5b28d1566766bb7d5ffb29ab))
* prevent statusline auto-install from polluting unrelated projects ([68d219d](https://github.com/lorainwings/claude-autopilot/commit/68d219d5915bfddf07be8b643f0c5939bd953b09))
* prevent statusline auto-install from polluting unrelated projects ([621b4a2](https://github.com/lorainwings/claude-autopilot/commit/621b4a21176815c682e846de19c8399ecad3611e))
* SKILL 协议成为运行时权威约束 — 完整闭环修复 ([639a9ba](https://github.com/lorainwings/claude-autopilot/commit/639a9bab44cf36a98f2fd446657760680315ac55))

## [1.6.1](https://github.com/lorainwings/claude-autopilot/compare/parallel-harness-v1.6.0...parallel-harness-v1.6.1) (2026-04-12)


### Fixed

* add .parallel-harness marker dir in auto-install tests ([455230c](https://github.com/lorainwings/claude-autopilot/commit/455230c8c6f666986c6f0d15b766da98ed7f62a9))
* prevent statusline auto-install from polluting unrelated projects ([68d219d](https://github.com/lorainwings/claude-autopilot/commit/68d219d5915bfddf07be8b643f0c5939bd953b09))
* prevent statusline auto-install from polluting unrelated projects ([621b4a2](https://github.com/lorainwings/claude-autopilot/commit/621b4a21176815c682e846de19c8399ecad3611e))

## [1.6.0](https://github.com/lorainwings/claude-autopilot/compare/parallel-harness-v1.5.2...parallel-harness-v1.6.0) (2026-04-11)


### Added

* **parallel-harness:** 增加 skill 可观测性、hooks 机制与终态迁移防御 ([0785917](https://github.com/lorainwings/claude-autopilot/commit/078591714090861d32c5a62e4c3c5f114a0a71a9))
* **parallel-harness:** 增加 skill 可观测性、hooks 机制与终态迁移防御 ([67b3e1b](https://github.com/lorainwings/claude-autopilot/commit/67b3e1b8c2cde41d2a8b0af7968a0911ca85a751))


### Fixed

* **parallel-harness:** 修复 statusLine bridge 在上游变更时未重新生成的问题 ([b7c572f](https://github.com/lorainwings/claude-autopilot/commit/b7c572f24411ab06da687aae7cdbb7bb2413ee38))

## [1.5.2](https://github.com/lorainwings/claude-autopilot/compare/parallel-harness-v1.5.1...parallel-harness-v1.5.2) (2026-04-10)


### Fixed

* SKILL 协议成为运行时权威约束 — 完整闭环修复 ([639a9ba](https://github.com/lorainwings/claude-autopilot/commit/639a9bab44cf36a98f2fd446657760680315ac55))

## [1.5.1](https://github.com/lorainwings/claude-autopilot/compare/parallel-harness-v1.5.0...parallel-harness-v1.5.1) (2026-04-09)


### Fixed

* **parallel-harness:** 重写 SKILL.md 为可执行协议，修复 skill 无法触发的问题 ([6bc0274](https://github.com/lorainwings/claude-autopilot/commit/6bc02740a3d3d9029799c16cf774c7e43eb05db0))
* **parallel-harness:** 重写 SKILL.md 为可执行协议，修复 skill 无法触发的问题 ([0c8bcc0](https://github.com/lorainwings/claude-autopilot/commit/0c8bcc016ebf224b5b28d1566766bb7d5ffb29ab))

## [1.5.0](https://github.com/lorainwings/claude-autopilot/compare/parallel-harness-v1.4.1...parallel-harness-v1.5.0) (2026-04-09)


### Added

* **parallel-harness:** add skill lifecycle runtime with registry, observability and phase inference ([8a39f01](https://github.com/lorainwings/claude-autopilot/commit/8a39f01c235ed70bc7cb1aa7eb8eb46301531716))

## [1.4.1](https://github.com/lorainwings/claude-autopilot/compare/parallel-harness-v1.4.0...parallel-harness-v1.4.1) (2026-04-09)


### Fixed

* **parallel-harness:** 为所有 SKILL.md 添加官方规范要求的 YAML frontmatter ([b08e3f6](https://github.com/lorainwings/claude-autopilot/commit/b08e3f6351995061bd2e1115181bddc31f17613a))

## [1.4.0](https://github.com/lorainwings/claude-autopilot/compare/parallel-harness-v1.3.2...parallel-harness-v1.4.0) (2026-04-09)


### Added

* **parallel-harness:** 8 workstream 全量修复 + codex 审查 13 项问题闭环 ([a926a12](https://github.com/lorainwings/claude-autopilot/commit/a926a1298fd19b3923858097876ea9294ba9c356))
* **parallel-harness:** P0 增强蓝图 6 项实施 — 295 pass / 649 expect ([68a9d47](https://github.com/lorainwings/claude-autopilot/commit/68a9d472de30c9e2c6cdf87c58fec0393426537c))
* **parallel-harness:** P0/P1/P2 增强蓝图全量实施 — 415 pass / 866 expect ([67348be](https://github.com/lorainwings/claude-autopilot/commit/67348be4a3af51d4665db81f3a5a9efeabf06deb))
* **parallel-harness:** P2 增强全量实施 — 480 pass / 987 expect ([af8c18d](https://github.com/lorainwings/claude-autopilot/commit/af8c18d087f3e9eb2a2ddf06639d7a5cd65660dd))
* **parallel-harness:** 全量修复 10 个能力域 — 运行时正确性/所有权隔离/上下文/Gate/报告 ([31b1ad3](https://github.com/lorainwings/claude-autopilot/commit/31b1ad330dee6616e0186ef6bd2e3ac78c88bd2f))


### Fixed

* **ci:** CI pipeline overhaul — 分离构建与测试，消除 pre-commit 副作用 ([3759d03](https://github.com/lorainwings/claude-autopilot/commit/3759d03f2aa819b02fd68dc7428706e33135ccd8))
* **ci:** 抽取共享 lint 脚本消除本地/CI lint 漂移 ([ab03dac](https://github.com/lorainwings/claude-autopilot/commit/ab03dacbd7c3846c6747103716b8095f4e265615))
* **ci:** 统一 CI/release/lint 全流程一致性 ([9495d5e](https://github.com/lorainwings/claude-autopilot/commit/9495d5e1bff5563d39fc1c37c85fa3d545cb1ba8))
* codex 3 项缺陷修复 — dashboard 凭证泄露 + PR 精确暂存 + git diff untracked 盲区 ([ca858f4](https://github.com/lorainwings/claude-autopilot/commit/ca858f4a2f2226ab790c9e82893250d24423bca2))
* codex 5 项缺陷修复 — git-diff 精确差分 + PR fail-fast + dashboard 鉴权 + action 映射 + retryTask 桥接 ([29a3bfb](https://github.com/lorainwings/claude-autopilot/commit/29a3bfb3b5c999fc45e9d4513fbea55231b5899c))
* **hook:** pre-commit 测试仅对 spec-autopilot 变更触发，避免 parallel-harness 文档提交误跑测试套件 ([ee1fc3a](https://github.com/lorainwings/claude-autopilot/commit/ee1fc3a3e914d008ef938b1a3bd6848debf900a9))
* **parallel-harness:** approveAndResume 路径复用全集终态判定 ([f8b9798](https://github.com/lorainwings/claude-autopilot/commit/f8b9798702fd23fe9220aa496e30588b70618c5f))
* **parallel-harness:** plugin.json schema 合规性修复 ([1084796](https://github.com/lorainwings/claude-autopilot/commit/108479669a59616ecdd170b73e4cd5386696f946))
* **parallel-harness:** stabilize worktree lifecycle ([f7040a9](https://github.com/lorainwings/claude-autopilot/commit/f7040a967f927cda48f9616d0189524df0a5e6ac))
* **parallel-harness:** 主链闭环返修 — 10 项 review 问题全部修复 ([39710b0](https://github.com/lorainwings/claude-autopilot/commit/39710b0cc65d4eabff6a16831941924cb2539eb1))

## [1.3.2](https://github.com/lorainwings/claude-autopilot/compare/parallel-harness-v1.3.1...parallel-harness-v1.3.2) (2026-04-09)


### Fixed

* **ci:** CI pipeline overhaul — 分离构建与测试，消除 pre-commit 副作用 ([3759d03](https://github.com/lorainwings/claude-autopilot/commit/3759d03f2aa819b02fd68dc7428706e33135ccd8))

## [1.3.1](https://github.com/lorainwings/claude-autopilot/compare/parallel-harness-v1.3.0...parallel-harness-v1.3.1) (2026-04-04)


### Fixed

* **parallel-harness:** stabilize worktree lifecycle ([f7040a9](https://github.com/lorainwings/claude-autopilot/commit/f7040a967f927cda48f9616d0189524df0a5e6ac))

## [1.3.0](https://github.com/lorainwings/claude-autopilot/compare/parallel-harness-v1.2.0...parallel-harness-v1.3.0) (2026-04-03)


### Added

* **parallel-harness:** 8 workstream 全量修复 + codex 审查 13 项问题闭环 ([a926a12](https://github.com/lorainwings/claude-autopilot/commit/a926a1298fd19b3923858097876ea9294ba9c356))
* **parallel-harness:** P0 增强蓝图 6 项实施 — 295 pass / 649 expect ([68a9d47](https://github.com/lorainwings/claude-autopilot/commit/68a9d472de30c9e2c6cdf87c58fec0393426537c))
* **parallel-harness:** P0/P1/P2 增强蓝图全量实施 — 415 pass / 866 expect ([67348be](https://github.com/lorainwings/claude-autopilot/commit/67348be4a3af51d4665db81f3a5a9efeabf06deb))
* **parallel-harness:** P2 增强全量实施 — 480 pass / 987 expect ([af8c18d](https://github.com/lorainwings/claude-autopilot/commit/af8c18d087f3e9eb2a2ddf06639d7a5cd65660dd))


### Fixed

* **parallel-harness:** approveAndResume 路径复用全集终态判定 ([f8b9798](https://github.com/lorainwings/claude-autopilot/commit/f8b9798702fd23fe9220aa496e30588b70618c5f))

## [1.2.0](https://github.com/lorainwings/claude-autopilot/compare/parallel-harness-v1.1.3...parallel-harness-v1.2.0) (2026-03-30)


### Added

* **parallel-harness:** 全量修复 10 个能力域 — 运行时正确性/所有权隔离/上下文/Gate/报告 ([31b1ad3](https://github.com/lorainwings/claude-autopilot/commit/31b1ad330dee6616e0186ef6bd2e3ac78c88bd2f))


### Fixed

* **parallel-harness:** 主链闭环返修 — 10 项 review 问题全部修复 ([39710b0](https://github.com/lorainwings/claude-autopilot/commit/39710b0cc65d4eabff6a16831941924cb2539eb1))

## [1.1.3](https://github.com/lorainwings/claude-autopilot/compare/parallel-harness-v1.1.2...parallel-harness-v1.1.3) (2026-03-29)


### Fixed

* **ci:** 抽取共享 lint 脚本消除本地/CI lint 漂移 ([ab03dac](https://github.com/lorainwings/claude-autopilot/commit/ab03dacbd7c3846c6747103716b8095f4e265615))
* **ci:** 统一 CI/release/lint 全流程一致性 ([9495d5e](https://github.com/lorainwings/claude-autopilot/commit/9495d5e1bff5563d39fc1c37c85fa3d545cb1ba8))

## [1.1.2](https://github.com/lorainwings/claude-autopilot/compare/parallel-harness-v1.1.1...parallel-harness-v1.1.2) (2026-03-28)


### Fixed

* codex 3 项缺陷修复 — dashboard 凭证泄露 + PR 精确暂存 + git diff untracked 盲区 ([ca858f4](https://github.com/lorainwings/claude-autopilot/commit/ca858f4a2f2226ab790c9e82893250d24423bca2))
* codex 5 项缺陷修复 — git-diff 精确差分 + PR fail-fast + dashboard 鉴权 + action 映射 + retryTask 桥接 ([29a3bfb](https://github.com/lorainwings/claude-autopilot/commit/29a3bfb3b5c999fc45e9d4513fbea55231b5899c))
* **hook:** pre-commit 测试仅对 spec-autopilot 变更触发，避免 parallel-harness 文档提交误跑测试套件 ([ee1fc3a](https://github.com/lorainwings/claude-autopilot/commit/ee1fc3a3e914d008ef938b1a3bd6848debf900a9))

## [1.1.1](https://github.com/lorainwings/claude-autopilot/compare/parallel-harness-v1.1.0...parallel-harness-v1.1.1) (2026-03-26)


### Fixed

* **parallel-harness:** plugin.json schema 合规性修复 ([1084796](https://github.com/lorainwings/claude-autopilot/commit/108479669a59616ecdd170b73e4cd5386696f946))

## [1.1.0](https://github.com/lorainwings/claude-autopilot/compare/parallel-harness-v1.0.4...parallel-harness-v1.1.0) (2026-03-26)


### Added

* 🎸 add parallel-harness plugin ([5461cd4](https://github.com/lorainwings/claude-autopilot/commit/5461cd44c1cd321ac9835ee101e39020c6c69455))
* parallel-harness 全面接入插件市场 — gitignore + rebase + dist + CI + Makefile ([ce2f3ea](https://github.com/lorainwings/claude-autopilot/commit/ce2f3ea6faf459fe122ced1a2da74536274db8bb))


### Fixed

* codex 审核 2 项缺陷修复 — general 域路径推断 + 回归测试补齐 ([7871ef1](https://github.com/lorainwings/claude-autopilot/commit/7871ef1a96b4951cf4d4315d6a25c559340838d9))
* codex 审核 2 项缺陷修复 — 审批恢复真正解阻 + 泛化意图越界修复 ([4838258](https://github.com/lorainwings/claude-autopilot/commit/4838258ccec7fd469a2f49589deccc08c10edf35))
* codex 审核 4 项缺陷修复 — 市场索引 + CI 护栏 + 发版纪律 + 文档口径 ([b811bbc](https://github.com/lorainwings/claude-autopilot/commit/b811bbc57dbb93cd9e9ec409ec6d8dea4c1229c7))
* codex 审核 5 项缺陷修复 — task 审批 checkpoint + CP 读模型接通 + 泛化意图 + worker 字段 + RBAC cancel ([3bf6342](https://github.com/lorainwings/claude-autopilot/commit/3bf63422a69c2776d2c0efd728a8fc529c7f33d7))
* codex 审核 8 项缺陷修复 — fail-closed gate + 持久化 durable + RBAC 执法 + PR/CI 闭环 ([d75b01a](https://github.com/lorainwings/claude-autopilot/commit/d75b01a86381a03eb2ffbac9c8a2734827d7f224))
* GUI typecheck 修复 + parallel-harness CHANGELOG 补充 ([84d36bd](https://github.com/lorainwings/claude-autopilot/commit/84d36bd530840e013f3bdf09461a060c54a6f403))
* parallel-harness plugin.json manifest 格式修复 — Claude Code 插件安装兼容 ([24e8320](https://github.com/lorainwings/claude-autopilot/commit/24e8320044222fb7faa4d3c55c11965958ea6bae))
* parallel-harness 版本 bump 1.0.1 → 1.0.2 — 一次性同步所有版本位置 + dist ([878c98c](https://github.com/lorainwings/claude-autopilot/commit/878c98c565492ecd88faed2647b7f87e79b48cdb))
* parallel-harness 版本 bump 1.0.2 → 1.0.3 + dist 重建 ([dd35fbc](https://github.com/lorainwings/claude-autopilot/commit/dd35fbc8c5f9893ed3d48c2557abb9aedeae08d5))
* parallel-harness 版本 bump 1.0.3 → 1.0.4 ([137a577](https://github.com/lorainwings/claude-autopilot/commit/137a577a6c7f724ac65b7e15793537c5fe7cdd72))
* parallel-harness 版本同步 plugin.json/marketplace + dist 重建 ([5240491](https://github.com/lorainwings/claude-autopilot/commit/5240491a741b98bf1b314e8f8bc7725841d48f28))
* plugin.json manifest 格式修复 — author 改为对象 + dependencies 改为数组 ([cf6dc2a](https://github.com/lorainwings/claude-autopilot/commit/cf6dc2ae133ef29b80747b8930ff7f4182206ded))
* release-discipline CI 死循环修复 + parallel-harness 版本同步 ([c52b4dc](https://github.com/lorainwings/claude-autopilot/commit/c52b4dc191ac10e3e09d0d7b0cb7df844ea8e673))
* ruff format _phase_graph.py + 补提未跟踪文件 ([3590554](https://github.com/lorainwings/claude-autopilot/commit/35905549d23bcd5da032f8cdb174b50c34c935a8))
* 评估报告 11 项问题全量修复 — P0 执行可信度 + P1 治理闭环 + P2 文档对齐 ([7fff378](https://github.com/lorainwings/claude-autopilot/commit/7fff378fc8fd929ba87a9acb8d7b7bcc21c680cb))

## [Unreleased]

## [1.0.4] - 2026-03-25

### Added
- 中文产品概览文档 (product-overview.zh.md)

### Fixed
- package.json 版本与 plugin.json 同步到 1.0.4

## [1.0.3] - 2026-03-24

### Added
- Full bilingual documentation (12 English + 12 Chinese docs)
- Orchestrator runtime enhanced error handling and recovery
- Gate system improvements for parallel verification
- Worker runtime retry and degradation enhancements
- PR provider integration improvements
- Task graph builder dependency validation
- Session persistence checkpoint recovery
- Control plane dashboard updates

### Fixed
- Version metadata sync across all plugin files
- Dist build alignment with source changes

## [1.0.0] - 2025-03-23

### Added
- **Task Graph Orchestration**: DAG-based task decomposition with dependency tracking and cycle detection
- **Parallel Worker Dispatch**: Multi-agent concurrent execution with file ownership isolation
- **Cost-Aware Model Routing**: 3-tier automatic model selection (tier-1/tier-2/tier-3) with escalation and downgrade policies
- **9-Gate Quality System**: test, lint_type, review, security, performance, coverage, policy, documentation, release_readiness
- **RBAC Governance**: 4 built-in roles (admin/developer/reviewer/viewer), 12 fine-grained permissions
- **Policy-as-Code Engine**: Declarative policy rules with path boundaries, budget limits, model tier caps
- **Audit Trail**: Full event-level audit with timeline replay, JSON/CSV export
- **PR/CI Integration**: GitHub PR creation, review comments, CI failure analysis via gh CLI
- **Session Persistence**: Memory/File dual-adapter with checkpoint recovery
- **Merge Guard**: 4-layer checking (ownership, conflicts, policy, contracts)
- **EventBus Observability**: 38 event types with pub/sub and wildcard subscriptions
- **Control Plane API**: HTTP API (port 9800) with embedded dashboard
- **4 Skills**: /harness (main), /harness-plan, /harness-dispatch, /harness-verify
- **Comprehensive Test Suite**: 295 tests, 649 assertions, 0 failures
- **12 Documentation Files**: Architecture, operator guide, admin guide, policy guide, integration guide, troubleshooting, FAQ, security, marketplace readiness, release checklist, capabilities, examples
