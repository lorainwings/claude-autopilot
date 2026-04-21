# Testing Anti-Patterns Guide

## Contents

- [Anti-Pattern 1: Testing Mock Behavior](#anti-pattern-1-testing-mock-behavior)
- [Anti-Pattern 2: Test-Only Methods in Production](#anti-pattern-2-test-only-methods-in-production)
- [Anti-Pattern 3: Mocking Without Understanding](#anti-pattern-3-mocking-without-understanding)
- [Anti-Pattern 4: Incomplete Mocks](#anti-pattern-4-incomplete-mocks)
- [Anti-Pattern 5: Integration Tests as Afterthought](#anti-pattern-5-integration-tests-as-afterthought)
- [Gate Function 检查表（TDD 子 Agent 自查）](#gate-function-检查表tdd-子-agent-自查)
- [注入时机](#注入时机)

> 本文档定义 5 种常见测试反模式及其 Gate Function 检查表。
> 在 TDD RED step 的子 Agent prompt 中注入，帮助避免常见陷阱。
> 来源: Superpowers testing-anti-patterns.md，适配 autopilot Phase 体系。

---

## Anti-Pattern 1: Testing Mock Behavior

**问题**: 测试验证的是 mock 的行为，而非真实代码的行为。

**Bad** (测试 mock):
```python
# ❌ 这个测试只证明了 mock 按预期返回值
def test_get_user(mock_db):
    mock_db.find_one.return_value = {"name": "Alice"}
    result = get_user(mock_db, 1)
    assert result["name"] == "Alice"  # 只是验证了 mock
```

**Good** (测试真实组件):
```python
# ✅ 使用真实数据库或 test double
def test_get_user(test_db):
    test_db.users.insert_one({"_id": 1, "name": "Alice"})
    result = get_user(test_db, 1)
    assert result["name"] == "Alice"  # 验证了真实查询逻辑
```

**Gate Function**: 检查测试中 mock.return_value 设置后是否仅断言了相同的返回值。

---

## Anti-Pattern 2: Test-Only Methods in Production

**问题**: 在生产类中添加仅供测试使用的方法或属性。

**Bad** (生产代码包含测试方法):
```java
// ❌ 生产类中的测试辅助方法
public class UserService {
    public User getUser(int id) { ... }

    // 仅测试使用
    public void _testResetCache() { this.cache.clear(); }
    public Map<Integer, User> _getInternalCache() { return this.cache; }
}
```

**Good** (测试辅助在测试目录):
```java
// ✅ 测试工具类在 test 目录
// src/test/java/helpers/UserServiceTestHelper.java
public class UserServiceTestHelper {
    public static void resetCache(UserService service) {
        // 使用反射或 package-private 访问
        Field cache = UserService.class.getDeclaredField("cache");
        cache.setAccessible(true);
        ((Map) cache.get(service)).clear();
    }
}
```

**Gate Function**: 搜索生产代码中包含 `_test`, `forTesting`, `@VisibleForTesting` 的方法。

---

## Anti-Pattern 3: Mocking Without Understanding

**问题**: 不理解依赖链就 mock，导致测试脱离现实。

**Bad** (盲目 mock):
```typescript
// ❌ Mock 了整个模块而不理解其行为
jest.mock('../services/payment');
test('process order', () => {
    (processPayment as jest.Mock).mockResolvedValue({ success: true });
    // 测试永远通过，即使 processPayment 接口变了
});
```

**Good** (理解后选择性 mock):
```typescript
// ✅ 只 mock 外部 I/O，保留业务逻辑
test('process order', () => {
    // 只 mock HTTP 层，保留 payment service 的验证逻辑
    nock('https://api.stripe.com')
        .post('/v1/charges')
        .reply(200, { id: 'ch_123', status: 'succeeded' });

    const result = await processPayment({ amount: 100, currency: 'USD' });
    expect(result.chargeId).toBe('ch_123');
});
```

**Gate Function**: Mock setup 行数 > 测试逻辑行数 → 建议使用集成测试。

---

## Anti-Pattern 4: Incomplete Mocks

**问题**: Mock 对象缺少真实 API 的字段或行为，导致测试通过但生产失败。

**Bad** (不完整的 mock):
```python
# ❌ Mock 只有部分字段
mock_response = {"status": 200, "data": {"id": 1}}
# 真实响应还有 headers, cookies, timestamp 等
# 代码访问 response.headers 时会 KeyError
```

**Good** (镜像真实 API):
```python
# ✅ 使用 factory 生成完整的 mock response
def make_api_response(data, status=200):
    return {
        "status": status,
        "data": data,
        "headers": {"content-type": "application/json"},
        "timestamp": "2024-01-01T00:00:00Z",
        "request_id": "test-req-001"
    }

mock_response = make_api_response({"id": 1})
```

**Gate Function**: 比对 mock 对象的 key 集合与真实 API 的 schema 定义。

---

## Anti-Pattern 5: Integration Tests as Afterthought

**问题**: 先写完所有单元测试后才补集成测试，导致集成测试质量低下或直接跳过。

**Bad** (后补集成测试):
```
Phase 4: 写了 50 个单元测试
Phase 5: 实现全部功能
Phase 6: "集成测试太晚了，来不及了" → 跳过
```

**Good** (TDD 周期内完成):
```
TDD RED:   写 1 个集成测试（验证端到端流程）
TDD GREEN: 实现功能让集成测试通过
TDD RED:   写 N 个单元测试（覆盖边界情况）
TDD GREEN: 确保所有测试通过
```

**Gate Function**: 检查测试金字塔中 integration 占比是否 > 0。

---

## Gate Function 检查表（TDD 子 Agent 自查）

在每个 TDD RED step 完成后，子 Agent 必须自查：

```
- [ ] 测试验证的是真实行为，不是 mock 行为
- [ ] 生产代码中没有添加测试专用方法
- [ ] Mock 仅用于外部 I/O（网络、数据库、文件系统）
- [ ] Mock 对象镜像了真实 API 的完整结构
- [ ] 测试独立运行（不依赖其他测试的执行顺序）
- [ ] 测试有清晰的 Arrange-Act-Assert 结构
- [ ] 每个测试只验证一件事
```

## 注入时机

| 阶段 | 注入方式 |
|------|---------|
| TDD RED (串行) | 子 Agent prompt 注入完整反模式指南 |
| TDD RED (并行) | 域 Agent prompt 注入精简版 Gate Function 检查表 |
| Phase 4 (非 TDD) | 不注入（Phase 4 有自己的 test standards 模板） |
