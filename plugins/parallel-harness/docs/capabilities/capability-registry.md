> **[中文版](capability-registry.zh.md)** | English (default)

# parallel-harness Capability Registry

> Design origin: superpowers capability cataloging + low-friction capability entry points

Each capability includes: name, intent, required_context, worker_policy, verifier_policy.

## Implemented Capabilities

### 1. task-graph-build
- **Purpose**: Build a task DAG from user intent
- **Intent**: Decompose complex requirements into parallelizable task nodes
- **Required context**: User input, project module list
- **Worker policy**: Planner role, tier-3 model
- **Verifier policy**: review-verifier checks graph validity

### 2. complexity-score
- **Purpose**: Assess task complexity
- **Intent**: Determine model tier, context budget, and retry strategy
- **Required context**: Task description, target domain, file estimate
- **Worker policy**: Local computation, no model required
- **Verifier policy**: No independent verification needed

### 3. ownership-plan
- **Purpose**: Assign file ownership for parallel tasks
- **Intent**: Prevent write conflicts during parallel execution
- **Required context**: Task graph, file paths
- **Worker policy**: Local computation
- **Verifier policy**: merge-guard validation

### 4. context-pack
- **Purpose**: Package minimal context for workers
- **Intent**: Reduce irrelevant information and control token costs
- **Required context**: Task node, related files
- **Worker policy**: Local computation + automatic summarization
- **Verifier policy**: Budget check

### 5. model-route
- **Purpose**: Automatically select the model tier for a task
- **Intent**: Balance quality and cost
- **Required context**: Complexity, risk, budget, retry history
- **Worker policy**: Local computation
- **Verifier policy**: Cost tracking

### 6. schedule
- **Purpose**: Convert a task graph into executable batches
- **Intent**: Maximize parallelism while respecting dependencies
- **Required context**: Task graph, scheduling configuration
- **Worker policy**: Local computation
- **Verifier policy**: DAG consistency check

## Extended Capabilities

### 7. worker-dispatch [GA]
- **Purpose**: Dispatch task contracts to Claude Code sub-agents
- **Status**: Fully implemented — WorkerExecutionController with retry, downgrade, git-diff ownership enforcement

### 8. merge-guard [GA]
- **Purpose**: Check for out-of-bounds access and conflicts before merging
- **Status**: Fully implemented — 4-layer checking (ownership / policy / interface / conflict)

### 9. verify-test [GA]
- **Purpose**: Independently check test coverage and pass status
- **Status**: Fully implemented — Gate evaluator with `bun test` / `pytest` execution

### 10. verify-review [GA]
- **Purpose**: Independently review implementation-to-goal alignment
- **Status**: Fully implemented — Gate evaluator with AI-based review

### 11. verify-security [GA]
- **Purpose**: Scan for security patterns and configuration risks
- **Status**: Fully implemented — Gate evaluator with pattern matching + bandit/semgrep

### 12. pr-review [Beta]
- **Purpose**: Automated PR review with task history integration
- **Status**: Implemented — GitHubPRProvider with real git pipeline (branch → commit → push → PR)

### 13. ci-analyze [Beta]
- **Purpose**: CI failure analysis with automated fix attempts
- **Status**: Implemented — CIProvider with GitHub Actions log parsing and failure categorization
