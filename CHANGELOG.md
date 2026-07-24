# Changelog

## 2026-07-25 — Reliability checkpoint

### Added

- 8,192-token Ollama context for `qwen2.5vl:7b` vision requests.
- Visible per-file progress: open, read, query, response, plan, move, and result.
- Two-folder output model: `Done` and `Undecided`.
- `-RetryUndecided` mode for reprocessing previously rejected images.
- Defensive state-file loading and flat state-file saving.
- Unique destination naming and rollback logging.

### Issues found and addressed

- **Ollama HTTP 400 responses:** large image requests exceeded the default 4,096-token context. The tool now uses 8,192 tokens.
- **Retry scope error:** an early retry implementation also selected normal source images. `-RetryUndecided` now scans only `Undecided`.
- **State-file nesting:** repeated PowerShell JSON serialization created nested `value` arrays and null hash indexes. State loading now flattens and validates records.
- **Move verification complexity:** a verification/retry layer obscured the simple move operation and did not resolve the observed race. The current implementation uses one direct non-overwriting `Move-Item` call.
- **Concurrent filer processes:** stale dry-run/apply retry processes competed with a new run, causing source-path errors and duplicate suffixes. Those processes were stopped on 2026-07-25.

### Current operating rule

Run only one filer process at a time. Preview a batch, then execute that batch after confirming the proposed destinations.
