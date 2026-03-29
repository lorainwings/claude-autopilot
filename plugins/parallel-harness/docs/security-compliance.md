> **[中文版](security-compliance.zh.md)** | English (default)

# parallel-harness Security and Compliance

> Version: v1.1.3 (GA) | Target Audience: Security Engineers, Compliance Auditors

## Security Architecture Overview

parallel-harness was designed with security as a core consideration from the ground up, implementing multi-layer security controls:

```
RBAC Layer → Policy Engine → Path Sandbox → Tool Governance → Audit Trail
```

## Access Control

### RBAC Role Isolation

- 4 built-in roles with 12 fine-grained permissions
- Principle of least privilege: viewer only has run.view + audit.view
- System and CI type actors have full permissions (limited to automation scenarios only)
- Custom roles are supported to meet organizational needs

### Approval Workflows

- Sensitive operations (model upgrades, sensitive directory writes, autofix pushes) require approval
- Approvals are bound to specific actions, not blanket grants
- Auto-approval rules are supported to reduce manual overhead for low-risk operations
- All approval decisions are recorded in the audit log

## Data Security

### Secret Management

- `ConnectorConfig.secret_ref` uses references rather than plaintext secret storage
- Configuration does not directly contain API keys, tokens, or other sensitive information
- Using environment variables or a secret management service is recommended

### Sensitive File Protection

- The Security Gate automatically detects modifications matching the following sensitive file patterns:
  - `.env`, `credentials`, `secret`, `password`
  - `.pem`, `.key`, `token`, `apikey`
- Matching modifications generate critical-severity findings and block the pipeline

### Path Sandboxing

- Worker execution is constrained by `allowed_paths` and `forbidden_paths`
- Output paths undergo secondary validation via `isPathInSandbox()`
- Out-of-bounds writes trigger an `OwnershipViolation` and block execution

### Data Retention

- Audit logs are retained on the local filesystem by default
- JSON/CSV format export is supported for external audit systems
- The event bus retains the most recent 10,000 events by default

## Policy as Code

### Policy Engine

- All constraints are declaratively defined through the `PolicyEngine`
- 5 condition types are supported (path, budget, risk, model tier, action type)
- 4 enforcement actions (block/warn/approve/log)
- Policy rules support priority ordering

### Security-Related Default Policies

| Rule | Description | Default Action |
|------|-------------|----------------|
| Sensitive directory protection | Matches paths such as config/secrets | block |
| High model tier restriction | tier-3 model usage requires approval | approve |
| Budget exceeded | Single Run exceeds configured budget | block |

## Audit Capabilities

### Audit Event Types

The system records 30+ audit event types, covering:

- **Run lifecycle**: Creation, planning, start, completion, failure, cancellation
- **Task execution**: Dispatch, completion, failure, retry
- **Model decisions**: Routing, escalation, downgrade
- **Policy and approval**: Policy evaluation, violation, approval request, approval decision
- **Ownership**: Check, violation
- **Budget**: Consumption, exceeded
- **PR/CI**: Creation, review, merge

### Audit Record Structure

Each audit event includes:

- `event_id`: Unique event ID
- `type`: Event type
- `timestamp`: ISO-8601 timestamp
- `actor`: Trigger source (ID, type, name, role)
- `run_id / task_id / attempt_id`: Associated identifiers
- `payload`: Event details
- `scope`: Impact scope (organization/project/repository/environment)

### Export and Integration

```typescript
// Export audit logs for a specific Run
const jsonReport = await auditTrail.export("json", { run_id: "run_xxx" });

// Export by time range
const rangeReport = await auditTrail.export("csv", {
  from: "2026-03-01T00:00:00Z",
  to: "2026-03-31T23:59:59Z",
});
```

## Tool Governance

### Tool Allowlist/Denylist

```typescript
const DEFAULT_TOOL_POLICY = {
  allowlist: [],           // Empty = allow all
  denylist: ["TaskStop", "EnterWorktree"],  // Deny dangerous operations
};
```

### Network Governance

- Worker execution environment is controlled via `WorkerExecutionConfig`
- Timeout control: 5 minutes by default
- Heartbeat monitoring: 30-second interval by default

## Compliance Checklist

| Item | Status | Description |
|------|--------|-------------|
| RBAC role isolation | Yes | 4 roles, 12 permissions |
| Approval workflows | Yes | Bound to specific actions |
| Audit trail | Yes | 30+ event types |
| Secret references | Yes | secret_ref, not plaintext |
| Sensitive file detection | Yes | Security Gate |
| Path sandboxing | Yes | Dual validation |
| Policy as code | Yes | PolicyEngine |
| Cost control | Yes | Budget + automatic stop |
| Data export | Yes | JSON/CSV |
| Replay capability | Yes | ReplayEngine |

## Known Limitations

1. **Local persistence**: Currently only file system storage is supported. Connecting to a database is recommended for production environments.
2. **Single-process audit**: The audit buffer resides in a single process. Events that have not been flushed may be lost on process restart.
3. **Static secret references**: secret_ref requires an external secret management service.
4. **Audit data encryption**: Audit logs are currently plaintext JSON. Transport-layer encryption is recommended.
