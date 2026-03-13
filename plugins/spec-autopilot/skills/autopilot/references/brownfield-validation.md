# Brownfield 验证协议（存量代码漂移检测）

> 由 autopilot-gate SKILL.md 引用。通过 `config.brownfield_validation.enabled` 控制（v4.0 起默认 `true`（greenfield 项目由 Phase 0 自动关闭））。

在存量项目中，新功能开发可能与现有代码产生漂移。本协议检测设计-测试-实现三者之间的一致性。

## 适用场景

- 在已有大型代码库中添加新功能（brownfield project）
- 重构或修改现有功能
- 不适用于全新项目（greenfield project）

## 三向一致性检查

### 1. 设计-测试对齐（Phase 4 → Phase 5 门禁）

```
检查项:
- [ ] design spec 中的每个 API 端点是否有对应的测试用例
- [ ] design spec 中的每个数据模型是否有字段验证测试
- [ ] design spec 中标注的错误场景是否有对应的异常测试
- [ ] 测试文件的目录结构是否与 design spec 的模块结构对应
```

执行方式:
1. 读取 `design.md` 中的功能点列表
2. 读取 Phase 4 生成的测试文件列表
3. 建立映射关系，标记未覆盖的功能点

### 2. 测试-实现就绪检查（Phase 5 实施前）

```
检查项:
- [ ] 测试中引用的 import 路径是否与项目结构一致
- [ ] 测试中使用的 fixture/mock 是否已有基础设施支持
- [ ] 测试命令（config.test_suites）是否可执行（dry-run 已在 Phase 4 验证）
```

执行方式:
1. 扫描测试文件中的 import 语句
2. 检查被导入模块的目标路径是否存在（允许不存在，标记为"待实现"）
3. 检查测试工具依赖是否已安装

### 3. 实现-设计一致性（Phase 5 → Phase 6 门禁）

```
检查项:
- [ ] 实现的 API 端点签名是否与 design spec 一致
- [ ] 实现的数据模型字段是否与 design spec 一致
- [ ] 是否有 design spec 中未提及的额外实现（scope creep）
- [ ] 现有代码的公共 API 是否被意外修改（breaking change 检测）
```

执行方式:
1. 对比 design spec 中的接口定义与实际代码
2. 检查 git diff 中修改的文件是否都在 tasks.md 范围内
3. 检查是否有未在 design spec 中描述的新增公共方法

## 配置

```yaml
brownfield_validation:
  enabled: true               # v4.0 起默认开启，greenfield 项目由 Phase 0 自动关闭
  strict_mode: false          # true: 不一致直接 block; false: 仅 warning
  ignore_patterns:            # 忽略的文件模式
    - "*.test.*"
    - "*.spec.*"
    - "__mocks__/**"
```

## 集成方式

在 autopilot-gate 的 8 步检查清单中，当 `brownfield_validation.enabled === true` 时：

- **Phase 4→5 切换**: 额外执行"设计-测试对齐"检查
- **Phase 5 启动**: 额外执行"测试-实现就绪"检查
- **Phase 5→6 切换**: 额外执行"实现-设计一致性"检查

`strict_mode` 控制不一致时的行为:
- `false` (默认): 记录为 warning，展示给用户但不阻断
- `true`: 任何不一致直接 block，要求修复后重试
