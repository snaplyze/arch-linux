# Agent setup: finite plan and checkpoint

Scope: autonomous-agent configuration only, in the physical checkout on main.
This is operational setup evidence, not another normative contract or product roadmap.
Rules come only from [AGENTS.md](../AGENTS.md). No Git staging, commits or external publication.

| ID | Dependency | Acceptance | Status |
| --- | --- | --- | --- |
| AS-1 | none | Client/version, clean main/index, instruction sources | PASS |
| AS-2 | AS-1 | Policy v6 with owner correction; preserved project constraints and managed orchestration block | PASS |
| AS-3 | AS-1 | Native project permissions accepted; role/model/routing settings preserved | PASS |
| AS-4 | AS-2, AS-3 | Native instruction loading, effective permissions, bounded spawn and smoke | PASS |
| AS-5 | AS-4 | Source suite, scenario review, unchanged index, idempotence | PASS |

Автоматическое резервирование конфигураций и агентских инструкций, исходные копии
перед обычными правками и отдельная система восстановления настроек — **отменено владельцем**
(2026-10-02). Это не незавершенные пункты приемки.

Observed client: Codex 0.160.0 local app-server, session metadata source=vscode,
originator=codex-tui. Both use native AGENTS.md/project-config loading; this does not
prove a separate Claude, Gemini or Copilot client is in use. Existing CLAUDE.md is
unchanged; its manual-read adapter is not a verified native import. No nested agent
instructions or project config existed at baseline.

Project `.codex/config.toml` sets approval_policy=never and sandbox_mode=danger-full-access.
Project worker/tester preserve the installed models, effort, descriptions and duties,
omitting sandbox_mode to inherit the parent. Reviewer/explorer/researcher remain unchanged.
Live session overrides and managed requirements take precedence; do not bypass them.

Checkpoint: AS-1 through AS-5 complete for configuration scope. Coordinator wrote
all setup files; one read-only reviewer finished with no material findings. No
product roadmap work, staging, commits, push, release or deployment was performed.
Setup Goal is complete. This correction does not restart agent setup or product work. A fresh client session is needed for persistent
settings; the current session was not reconfigured by these files.

Historical setup acceptance (2026-10-02, Codex 0.160.0, before the owner correction):

- PASS: TOML parsing; `codex --strict-config doctor --json` overallStatus=ok.
- PASS: native app-server `config/read` with cwd and includeLayers; both permission
  origins are the enabled project layer, without config or sandbox CLI overrides.
  All other effective config fields equal the pre-setup result. Existing project
  trust was already trusted; no global trust or managed policy was changed.
- PASS: fresh ephemeral `thread/start`, no permission overrides, reports
  approvalPolicy=never and sandbox=dangerFullAccess.
- PASS: `codex debug prompt-input` contains the entire 28016-byte AGENTS.md exactly
  once, including the verbatim policy v6 and managed block provided by the owner.
  No ancestor/nested overrides were found; context limit was not increased.
  `--strict-config` is unsupported for debug (diagnostic command limitation); the
  successful debug check uses no config overrides, and strict acceptance is separate.
- PASS: owned temporary files inside and outside the project, `/usr/bin/true`,
  public HTTPS 200 from developers.openai.com; temporary smoke files were removed.
- PASS: native reviewer spawn, isolated brief, completed read-only review; rollout
  confirms Sol 6.1/medium, never/danger-full-access and the correct physical cwd.
  Reviewer saw policy v6 before explicit reading. The spawn alone cannot separate
  inherited context from native loading; prompt-input independently verifies loading.
- PASS: worker/tester TOML preserves every installed field except sandbox_mode,
  omitted for parent inheritance. A fresh worker/tester spawn was NOT_TESTED; only
  reviewer was spawned. Global reviewer/explorer/researcher defaults are unchanged.
  A live parent override can supersede their read-only sandbox defaults: the
  observed reviewer retained read-only duties while its runtime had Full Access.
- PASS: `bash tests/source-tests.sh`, exit 0, all required source tests passed,
  including `REPOSITORY_CHECKS_RESULT schema=1 namespace_fixtures=full scenarios=10
  signer=passed release_closures=14+18 deferred=none`. This is source/fixture
  acceptance; package builds, real installation/QEMU, production and release
  acceptance were NOT_TESTED and are outside this setup.
- PASS: independent scenario review for audit without writes, deletion only after
  preservation checks, non-forced main conflicts, explicit external authority,
  pause and checkpoint recovery. These are contract checks, not a model guarantee.
- PASS: repeated policy normalization was byte-identical and created no new blocks
  or paths; index/HEAD/global settings and pre-existing files except AGENTS.md
  were preserved.

Cleanup (2026-10-02): at the owner's explicit request, setup temporary files,
backup bytes, raw logs and the recovery system were deleted. The retained historical
setup checks above have no external raw evidence after this cleanup.
No setup backup or automatic rollback remains; current agent settings are preserved.

Correction checkpoint (2026-10-02): the owner cancellation is recorded in policy
item 5; obsolete backup/recovery acceptance was removed from AS-1/AS-5. No
settings-recovery helpers remain in the project; the previously deleted external
bundle is absent. Only AGENTS.md and this plan are changed. No active product task
exists; continue only on a new explicit assignment. After context loss, read this
checkpoint and confirm cwd/Git/task state before continuing.

Next step: open a fresh Codex session in this checkout and check its permissions
and loaded AGENTS.md. If a higher-priority restriction or untrusted project layer
appears, stop that dependent action and report it; this setup does not authorize
changing global trust, UI permissions or managed protection. Other client adapters
remain unverified until their actual use is established.

References: [official configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference)
and [official subagent inheritance](https://learn.chatgpt.com/docs/agent-configuration/subagents).
