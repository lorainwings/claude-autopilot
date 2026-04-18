# Mutation Fixtures

变异测试独立 fixture，供 `test_mutation_sample.sh` 与 `test_health_score.sh` 使用。

这些 fixture 以可控方式模拟 runtime/scripts 与 tests 的关系，避免对真实脚本执行副作用。

## 布局

- `runtime_good/` — 目标脚本配有可 kill 变异的对应测试
- `runtime_bad/` — 目标脚本无对应测试（全部 survive）
- `runtime_mix/` — 混合场景（部分 killed，部分 survived）
- `health_strong/` — 健康度评分：断言密度高、无弱断言
- `health_weak/` — 仅 exit-code 断言
- `health_dup/` — 跨文件重复 case 名
- `health_empty/` — 空 tests 目录
