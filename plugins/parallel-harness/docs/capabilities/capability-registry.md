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

## Reserved Interface Capabilities

### 7. worker-dispatch
- **Purpose**: Dispatch task contracts to Claude Code sub-agents
- **Status**: Interface defined, implementation pending

### 8. merge-guard
- **Purpose**: Check for out-of-bounds access and conflicts before merging
- **Status**: Basic checks implemented via validateOwnership in ownership-planner

### 9. verify-test
- **Purpose**: Independently check test coverage and pass status
- **Status**: VerifierOutput schema defined

### 10. verify-review
- **Purpose**: Independently review implementation-to-goal alignment
- **Status**: VerifierOutput schema defined

### 11. verify-security
- **Purpose**: Scan for security patterns and configuration risks
- **Status**: VerifierOutput schema defined

### 12. pr-review
- **Purpose**: Automated PR review with task history integration
- **Status**: Architecture reserved

### 13. ci-analyze
- **Purpose**: CI failure analysis with automated fix attempts
- **Status**: Architecture reserved
