# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 5.x     | Yes       |
| 4.x     | No        |
| < 4.0   | No        |

## Reporting a Vulnerability

If you discover a security vulnerability, please report it responsibly:

1. **Do NOT** open a public GitHub issue
2. Email the maintainer directly or use [GitHub Security Advisories](https://github.com/lorainwings/claude-autopilot/security/advisories/new)
3. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

We aim to respond within 48 hours and provide a fix within 7 days for critical issues.

## Security Considerations

### Hook Scripts

- All hook scripts run locally in your environment
- Hook decisions are communicated via stdout JSON, not exit codes
- `exit 0` means "hook executed successfully", not "action approved"
- Failed hooks (non-zero exit) indicate a hook crash, not a security decision

### Credentials

- `project_context.test_credentials` in config are for **test/dev environments only**
- Never store production credentials in `autopilot.config.yaml`
- The config file should be in `.gitignore` if it contains sensitive data

### File System Access

- Hook scripts only read/write within the project directory
- Checkpoint files are stored in `openspec/changes/` within the project
- Event logs are written to `logs/events.jsonl`
- GUI server binds to `localhost` only (not exposed externally)

### Network

- WebSocket server (`ws://localhost:8765`) binds to localhost only
- HTTP server (`http://localhost:9527`) serves static files on localhost only
- No data is sent to external servers
