# Incremental Tree-sitter provisioning plan

Status: implemented. See `docs/install-audit.md` for commands, backend capability
findings, migration behavior, limitations, and root/non-root validation results.
The sections below retain the design and acceptance criteria used for the work.

## Problem and evidence

`config/nvim/lua/plugins/treesitter.lua` invokes
`require("core.treesitter-install").install(true)` from its Lazy build hook.
`core/treesitter-install.lua` expands the configured languages and dependencies,
then passes the entire list to the manager's `installer.update()`.
The manager removes existing parser/query artifacts and reinstalls them, so an
update rebuilds unchanged languages as well as changed ones.

The fix must retain completion checks, custom grammar registration, and the
parser/query verification added to the container audit. Simply removing the wait
or switching every update to install-only would hide the problem rather than
provide correct incremental updates.

## Desired behavior

| Action | Behavior |
| --- | --- |
| Startup | Install missing configured parsers asynchronously; no remote revision checks or updates to existing parsers. |
| Lazy build/update | Reconcile declared parser inputs; build missing or changed parsers only. |
| Explicit update | Reconcile selected languages (all configured languages by default), with clear skip/build reasons. |
| Explicit force rebuild | Rebuild the selected set even when fingerprints match. |
| Audit | Wait, verify artifacts/parsing/queries, and prove unchanged reconciliation does not compile anything. |

A plugin release changing only Lua code must not automatically invalidate every
parser. Dependencies are reconciled individually: changing one language does not
by itself require recompiling its unchanged dependencies.

## Scope and proposed decisions

- Keep `tree-sitter-manager` as the backend; do not introduce a second installer.
- Prefer immutable grammar revisions, including custom `duckdbsql` and `dap_repl`
  sources. Pinning custom grammars is a proposed behavior change to confirm before
  implementation, not an assumption that current unpinned sources are immutable.
- Use namespaced commands, provisionally `DotfilesTSUpdate [languages...]` and
  `DotfilesTSRebuild [languages...]`. Avoid existing TSUpdate/TSUpdateSync command
  collisions. Validate language arguments before changing anything.
- Preserve the existing ten-minute parser-operation deadline and actionable errors.
- Do not promise rollback unless the backend can stage and atomically replace
  artifacts. Never mark failed or partial builds as successful.

Non-goals: changing the language set, automatically pruning unconfigured parsers,
rewriting the manager, or proving every interactive Tree-sitter feature works.

## Phase 1 — Establish backend capabilities and failing tests

Inspect the locked manager implementation for supported APIs to:

1. Resolve effective repository metadata and transitive dependencies.
1. Install/update an explicit subset and wait for completion.
1. Observe the exact source commit used for a build.
1. Refresh query files without removing/recompiling parser binaries.
1. Observe builds initiated by setup/auto-install, not just the Lazy hook.

Add a counting fake backend to `config/nvim/tests/treesitter_build_test.lua`.
Reproduce the current behavior: reconciliation twice requests updates for all
languages even when nothing changed.

Architecture gate: if source provenance or query-only refresh requires copying
large private installer internals, propose a small upstream manager API change
(or a narrowly scoped pinned patch) before implementing the local adapter. Do not
silently replace missing capabilities with a large parallel installer.

## Phase 2 — Define desired state and successful-build metadata

Extend `config/nvim/lua/core/treesitter-install.lua` behind a small backend adapter.
Separate planning from execution so decisions can be tested without network or
filesystem side effects.

### Parser fingerprint

Compute a stable, schema-versioned fingerprint from normalized inputs:

- Repository URL and immutable resolved commit.
- Grammar subdirectory and generation options.
- Tree-sitter CLI version and relevant build options/toolchain identity.
- OS/architecture and parser ABI compatibility requirements.

Do not include the whole manager/plugin commit: unrelated plugin updates must not
force all parsers to rebuild. Check artifact existence and loadability separately;
a matching fingerprint is not proof that the file remains intact.

### Query fingerprint

Track query sources independently, including their content identity and source
layout. Manager queries, grammar-provided queries, and repository-local overrides
must not be conflated. A query-only change should refresh and validate queries
without recompiling an unchanged parser. A changed grammar commit may still
conservatively rebuild that parser even if only query files changed upstream;
content-level grammar comparison is an optional later optimization.

### Storage and lifecycle

- Store per-language metadata under a versioned directory in `stdpath("state")`.
- Include parser location/build identity so moving or replacing artifacts does not
  reuse unrelated metadata.
- Write atomically after build completion and successful validation, not before.
- Record parser and query success separately so query failure cannot falsely
  certify a fully usable installation.
- Treat malformed/unknown-schema metadata as untrusted and report the reason.
- Use an installation lock or equivalent serialization for concurrent Neovim
  processes. Re-read metadata after acquiring it and release it on failure.
- Account for setup's asynchronous installs before reconciliation; avoid duplicate
  jobs and ensure their provenance is either recorded or explicitly untrusted.

Migration: existing artifacts without trustworthy metadata receive a one-time
rebuild during explicit/Lazy reconciliation, not at every startup. Document this
one-time cost rather than fabricating metadata for an unknown installed revision.

## Phase 3 — Implement incremental reconciliation

Replace the boolean update interface with explicit operations, for example:
`ensure`, `reconcile`, and `rebuild`.

For each selected language and dependency:

1. Resolve desired metadata and wait for any relevant in-flight work.
1. Decide: unchanged, missing, changed build inputs, changed queries, incompatible
   artifact, untrusted metadata, or explicitly forced.
1. Run only the required operations through the backend.
1. Wait within the deadline, inspect status, and validate artifacts.
1. Persist successful state and print a concise per-language reason/result.

Inspect existing artifacts in a fresh process where necessary: Neovim may cache a
previously loaded parser library. Do not trust the current process's cached parser
as proof that a newly built library is valid.

For unpinned sources, if retained:

- Resolve the remote commit only on explicit update; do not check remotes on startup.
- Install that resolved commit, not a moving branch HEAD that can change between
  fingerprinting and cloning.
- Report revision-resolution failures; retain working artifacts and do not invent
  a successful update record.

## Phase 4 — Separate parser and query refresh

Use the backend capability established in Phase 1 to refresh query artifacts.
Compile applicable highlights, injections, locals, folds, and indents queries
against the installed parser. Include inherited query dependencies.

A query mismatch must report the language, query, and source. Do not respond by
rebuilding all languages. Query-only resources must not be treated as parser
libraries or require parser fixtures of their own.

## Phase 5 — Integrate commands, Lazy, startup, and audit

Likely files:

- `config/nvim/lua/core/treesitter-install.lua`: planner, execution, metadata adapter.
- `config/nvim/lua/plugins/treesitter.lua`: incremental Lazy hook, custom pins,
  namespaced commands, and coordinated startup installation.
- `config/nvim/tests/treesitter_build_test.lua`: decision/lifecycle regressions.
- `config/nvim/tests/treesitter_audit_test.lua`: verification failure cases.
- `tests/nvim_treesitter_audit.lua`: retain real parser and query verification.
- `tests/install_debian_audit.sh`: explicit unchanged-reconciliation checks.
- `docs/install-audit.md`: behavior, migration, force rebuild, and results.

Important: a second `Lazy restore` may skip build hooks entirely. The repeat audit
must explicitly invoke reconciliation and observe actual backend/compiler calls;
fast runtime or an unchanged file timestamp alone is not sufficient evidence.
Keep startup asynchronous, but keep build/audit operations bounded and awaited.

## Test matrix

| Scenario | Required outcome |
| --- | --- |
| Fresh installation | Every configured parser/dependency installed and verified. |
| Unchanged explicit reconciliation | Zero parser compilations and no unnecessary query writes. |
| One pinned revision changes | Only that parser rebuilds; unchanged dependencies are skipped. |
| Missing/corrupt parser artifact | Only affected parser reinstalls; validation fails if repair fails. |
| Query-only source change | Query refresh/validation, zero parser compilations. |
| Build toolchain/ABI compatibility changes | Only affected cached artifacts invalidated, with reasons. |
| Custom grammar | Exact desired commit built and recorded. |
| Missing/corrupt manifest | One-time reconciliation rebuild; subsequent run skips it. |
| Failed build/query validation | Nonzero result; no false success metadata; next run can retry. |
| Timeout | Bounded failure, lock cleanup, no success metadata. |
| Two simultaneous processes | No duplicate parser builds or torn metadata. |
| Force rebuild of one language | Only selected parser is forced; dependencies checked normally. |
| Plugin-only update | No parser rebuild when effective grammar/build inputs are unchanged. |

Run the final fresh-install and unchanged-reconciliation checks on
`python:3.13-slim-trixie` and `debian:13-slim`, as root and non-root. Preserve logs,
per-language decisions, compile counts, and source revisions. Distinguish network
rate-limit failures from implementation regressions; never count a blocked full
run as an end-to-end pass.

## Acceptance criteria

- An unchanged Tree-sitter update compiles zero parsers.
- Changing one grammar rebuilds only that grammar unless another parser's own
  recorded inputs also changed.
- Missing or invalid artifacts are repaired rather than skipped by the cache.
- Query-only refresh does not unnecessarily compile parsers.
- Fresh installs and existing-installation migration still pass parser/query checks.
- Force rebuild is explicit and available for recovery.
- Failed operations remain visible, retryable, and cannot poison success metadata.
- The four container/user combinations are validated, or blockers are explicitly
  recorded without claiming completion.

## Rollout

1. Land failing planner/backend tests and document API capability findings.
1. Implement metadata and reconciliation with unit tests.
1. Integrate query refresh, commands, and the Lazy/startup lifecycle.
1. Add compile-count assertions to container verification.
1. Validate migration plus the root/non-root matrix and document measured results.

Implementation notes:

- Compilation is still delegated to the existing manager; a narrow adapter adds
  immutable source resolution, successful-build records, query refresh, and locking.
- Custom grammars are pinned to immutable commits. Changed upstream grammar
  commits conservatively rebuild that grammar; content-level diffing is deferred.
- Fresh Python slim/Trixie and Debian 13 slim audits passed as root and non-root,
  including explicit unchanged reconciliation with zero backend builds.
- Late lock-recovery and compile-command-observer hardening passed focused tests;
  see the installation audit for exact validation provenance and log locations.
