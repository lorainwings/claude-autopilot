# Changelog

All notable changes to daily-report will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [1.2.7](https://github.com/lorainwings/claude-autopilot/compare/daily-report-v1.2.6...daily-report-v1.2.7) (2026-04-03)


### Fixed

* **daily-report:** 修复飞书命令参数错误并重构并发采集架构 ([2a21151](https://github.com/lorainwings/claude-autopilot/commit/2a21151cdcf56e2ff05d6e95a39d369c210ce946))
* **daily-report:** 修复飞书命令参数错误并重构并发采集架构 ([eae0a40](https://github.com/lorainwings/claude-autopilot/commit/eae0a40c0a872c4f589aa773205c74b9a8ecbe89))

## [1.2.6](https://github.com/lorainwings/claude-autopilot/compare/daily-report-v1.2.5...daily-report-v1.2.6) (2026-04-03)


### Fixed

* **daily-report:** 修复飞书群消息获取为0的问题 ([51945fb](https://github.com/lorainwings/claude-autopilot/commit/51945fba35b95dd6a20aa15a371b64d51cbed06c))

## [1.2.5](https://github.com/lorainwings/claude-autopilot/compare/daily-report-v1.2.4...daily-report-v1.2.5) (2026-04-03)


### Fixed

* **daily-report:** 修复初始化流程重复执行和授权超时问题 ([b2ad66b](https://github.com/lorainwings/claude-autopilot/commit/b2ad66b7bb9858ca2524d5485d4bc74c01453697))

## [1.2.4](https://github.com/lorainwings/claude-autopilot/compare/daily-report-v1.2.3...daily-report-v1.2.4) (2026-04-02)


### Fixed

* **daily-report:** 修复线框对齐、浏览器打开、飞书命令、表单收集、数据自检、日报审批等6项问题 ([2e4c199](https://github.com/lorainwings/claude-autopilot/commit/2e4c199e34551e83dbff9d44837ec3711ca542d8))

## [1.2.3](https://github.com/lorainwings/claude-autopilot/compare/daily-report-v1.2.2...daily-report-v1.2.3) (2026-04-01)


### Fixed

* **daily-report:** 移除 README badge 的 x-release-please-version 标记 ([4cc57ac](https://github.com/lorainwings/claude-autopilot/commit/4cc57ac78f1842211461f716dac268f6f06160ca))

## [1.2.2](https://github.com/lorainwings/claude-autopilot/compare/daily-report-v1.2.1...daily-report-v1.2.2) (2026-04-01)


### Fixed

* **daily-report:** 修复 CI 路径过滤和 post-release 文档版本同步 ([a5cc393](https://github.com/lorainwings/claude-autopilot/commit/a5cc3931f75370aa2a771beb166306d00e8fbe58))

## [1.2.1](https://github.com/lorainwings/claude-autopilot/compare/daily-report-v1.2.0...daily-report-v1.2.1) (2026-03-31)


### Fixed

* **daily-report:** 补全工程化链路并改用 AskUserQuestion 收集配置 ([a152510](https://github.com/lorainwings/claude-autopilot/commit/a152510c85f862e120db78fb0c4d7c969f6a74ac))

## [1.2.0](https://github.com/lorainwings/claude-autopilot/compare/daily-report-v1.1.0...daily-report-v1.2.0) (2026-03-31)


### Added

* **daily-report:** 支持自然语言指定日期范围 ([be758df](https://github.com/lorainwings/claude-autopilot/commit/be758df25469cc9c4bc666b45eeffea9bc9cbbe6))


### Fixed

* **daily-report:** 修复 7 项 UX 问题并补全市场文档 ([9ec5e6f](https://github.com/lorainwings/claude-autopilot/commit/9ec5e6f0b05d1ba35c90041f87a96c745031b80a))
* **daily-report:** 重启提示改为醒目双线框展示 ([5b4786c](https://github.com/lorainwings/claude-autopilot/commit/5b4786cb2bb62df9753e11afbc4848929b5823b8))

## [1.1.0](https://github.com/lorainwings/claude-autopilot/compare/daily-report-v1.0.0...daily-report-v1.1.0) (2026-03-31)


### Added

* **daily-report:** add AES password encryption and streamline login flow ([027ab7b](https://github.com/lorainwings/claude-autopilot/commit/027ab7b0e0b03dfca23efc7f9dac8599996ef07b))
* **daily-report:** add daily-report skill plugin — auto-generate work reports from git + lark ([0eccec0](https://github.com/lorainwings/claude-autopilot/commit/0eccec098eb5d107fe6bf26a79de0e468004cf31))
* **daily-report:** auto-login with stored credentials, remove cURL dependency ([4a1bd33](https://github.com/lorainwings/claude-autopilot/commit/4a1bd33a9b3e6fcef4a0b9da940de072f491a56f))


### Fixed

* **daily-report:** correct API endpoints and add full marketplace integration ([a8e4b6c](https://github.com/lorainwings/claude-autopilot/commit/a8e4b6c678d8ff246dc875d4283b84fafa3da317))
* **daily-report:** fix message field path and add pagination rules ([30351de](https://github.com/lorainwings/claude-autopilot/commit/30351de75a04dda060e3248b0e9b207c4af9c3d6))
* **daily-report:** improve auth UX, API config, and auto chat scanning ([7263e61](https://github.com/lorainwings/claude-autopilot/commit/7263e6140a868a2adf4b45c36384934297570aca))

## [Unreleased]

## [1.0.0] - 2026-03-31

### Added

- Initial release: daily-report skill plugin
- Git commit aggregation across multiple repositories
- Lark chat history integration (required, via lark-cli)
- Internal daily report API integration with browser-based setup
- Auto work-hour allocation (8h/day, proportional distribution)
- Batch submission with duplicate date skipping
