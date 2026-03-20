/**
 * runtime/verifiers/index.ts — 验证器模块统一导出
 *
 * 导出内容：
 *   - BaseVerifier 抽象基类及相关类型（VerifierConfig, FileChange）
 *   - 四个具体验证器（Test / Review / Security / Perf）
 *   - ResultSynthesizer 结果综合器
 */

// 基类及类型
export { BaseVerifier } from './base-verifier';
export type { VerifierConfig, FileChange } from './base-verifier';

// 具体验证器
export { TestVerifier } from './test-verifier';
export { ReviewVerifier } from './review-verifier';
export { SecurityVerifier } from './security-verifier';
export { PerfVerifier } from './perf-verifier';

// 结果综合器
export { ResultSynthesizer } from './result-synthesizer';
