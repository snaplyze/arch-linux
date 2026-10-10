# Agent setup: finite plan and checkpoint

Scope: autonomous-agent configuration only, in the canonical checkout. This is operational setup
evidence, not another normative contract or product roadmap. Rules come only from
[AGENTS.md](../AGENTS.md). Product audit, import and roadmap work are out of scope.

| ID | Dependency | Acceptance | Status |
| --- | --- | --- | --- |
| AS-1 | none | Clients/versions, Git state, instruction sources and concurrent edits | PASS |
| AS-2 | AS-1 | Exactly one policy v15 block; managed codex-orchestrator block and project invariants preserved | PASS |
| AS-3 | AS-2 | Codex native load (PASS); Claude Code `@AGENTS.md` import (fresh session NOT_TESTED) | PASS (partial) |
| AS-4 | AS-3 | Effective permissions unchanged and accepted; no new blanket permission files | PASS |
| AS-5 | AS-4 | Source/contract/doc checks, idempotence, issue → PR; merge is the owner's decision | PASS (merge pending) |

Clients in use (2026-10-10): Codex CLI 0.161.0 loads root AGENTS.md natively; Claude Code 2.1.296
loads CLAUDE.md, which imports AGENTS.md with `@AGENTS.md` (replacing the earlier manual-read
pointer). No Cursor, Copilot or Gemini configuration exists. Orchestration: codex-orchestrator for
Codex; the user-enabled Claude `orchestration` plugin, whose default routing lives in the owner's
user CLAUDE.md and is not copied here.

Permissions: project `.codex/config.toml` keeps approval_policy=never and
sandbox_mode=danger-full-access; worker/tester roles keep installed models/effort and inherit the
parent sandbox. Claude Code's effective mode is the owner's existing user-level
`bypassPermissions`; no project `.claude/` settings were added. Global settings, trust and managed
policy were not changed.

CI runner mode: `self-hosted` (all 18 jobs already select the owner's Linux labels; runner
`ubuntu-actions-arch-linux` was online). At the owner's request (2026-10-10), the `ci.yml` source job
now runs only for push, dispatch or same-repository pull requests; fork PRs are skipped and
NOT_TESTED. `tests/agent-contract-checks.py` rejects removing or weakening that condition.

Checks (2026-10-10, policy v15):

- PASS: `codex --strict-config doctor --json` overallStatus=ok.
- PASS: `codex debug prompt-input` contains every line of AGENTS.md and one policy block. Before
  this setup AGENTS.md was 35124 bytes, above Codex's 32 KiB project-document limit, so its tail
  was silently truncated. Detail was moved into the owning docs; AGENTS.md is now below the limit.
- PASS: `python3 tests/agent-contract-checks.py`, `python3 tests/docs-checks.py`, `git diff --check`.
- Text review (not a model-behavior proof): audit mode writes no code; consolidating a check
  requires a proven unchanged guarantee; test cleanup keeps behavior; simplification never bypasses
  gates; a missing tool is reported, not imitated.

- PASS: `bash tests/source-tests.sh`, exit 0, ending with `REPOSITORY_CHECKS_RESULT schema=1
  namespace_fixtures=full scenarios=10 signer=passed release_closures=14+18 deferred=none`.
- PASS: re-applying the v15 block is byte-identical; exactly one block remains.
- NOT_TESTED: Claude Code `@AGENTS.md` expansion in a fresh session. The running session had cached
  the earlier CLAUDE.md, and a paid model run only for setup was not used.

Checkpoint: setup files were published through issue #92 and PR #93, merged by the owner's
request. Since REL-INTENT-01 (2026-10-10) a merge no longer starts `release.yml`; a release needs an
explicit dispatch on `main`, and this setup authorizes none. After context loss, confirm cwd, branch, index and PR state first.

Historical: policy v6 setup (2026-10-02, Codex 0.160.0) passed its own checks; at the owner's
request its temporary files, backups and recovery system were deleted and are not restored.
