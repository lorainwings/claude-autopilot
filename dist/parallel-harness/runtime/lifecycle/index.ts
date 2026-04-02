export {
  LifecycleSpecStore,
  PHASE_ORDER,
  type LifecyclePhase,
  type PhaseStatus,
  type PhaseSpec,
  type PhaseArtifact,
  type PhaseGateConfig,
  type PhaseTransitionRecord,
} from "./lifecycle-spec-store";

export {
  StageContractEngine,
  type StageEntryResult,
  type StageExitResult,
  type StageValidationResult,
  type StageFailurePolicy,
  type FailureStrategy,
} from "./stage-contract-engine";
