# Changelog

All notable changes to daily-report will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

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
