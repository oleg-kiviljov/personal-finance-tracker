#!/usr/bin/env bash
# invoker-polish — the QA-polish scan entrypoint (Phase 3). Invoker `Sandbox.exec_stream`s this on the
# `iteration/<id>` integration branch once every standard feature is done; its stdout is parsed by
# `Invoker.Polish.ScanWorker` (via `Invoker.Polish.StreamJSON`). It runs a READ-ONLY finder set,
# runs the challenge gate over the auto-fix bucket, writes the findings + report artifacts, and emits
# two control lines the worker folds into the `Iteration` projection:
#   {"type":"invoker_findings","findings":[…]}                    — the deduped, gated finding set
#   {"type":"invoker_polish_report","sha":"…","path":"…"}         — pointer to the committed report
#
# It must NOT modify product code — the actual repair is a separate `kind: :polish` Feature (Phase 4)
# that rides the normal build pipeline. This scan only READS the checkout and WRITES under
# `.claude/iterations/<id>/` (findings.json, polish-report.md, candidate-lessons.md — the last staged
# for ship-time memory promotion, 4.6). All three are committed to the iteration branch.
#
# Env injected per-sandbox by Invoker.Polish.ScanWorker:
#   REPO_URL BRANCH(=iteration/<id>) BASE_BRANCH(=main) ITERATION_ID
#   GITHUB_TOKEN MODEL MAX_BUDGET_USD  + ONE of: CLAUDE_CODE_OAUTH_TOKEN | ANTHROPIC_API_KEY
set -euo pipefail

: "${REPO_URL:?REPO_URL required}"
: "${BRANCH:?BRANCH required}"
: "${ITERATION_ID:?ITERATION_ID required}"
: "${GITHUB_TOKEN:?GITHUB_TOKEN required}"
if [ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] && [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  echo "FATAL: set CLAUDE_CODE_OAUTH_TOKEN (claude subscription) or ANTHROPIC_API_KEY" >&2
  exit 1
fi
BASE_BRANCH="${BASE_BRANCH:-main}"
MODEL="${MODEL:-claude-opus-4-8}"
APP_DIR=/workspace/app
FINDINGS_DIR=".claude/iterations/${ITERATION_ID}"
FINDINGS_JSON="${FINDINGS_DIR}/findings.json"
REPORT_MD="${FINDINGS_DIR}/polish-report.md"
# Candidate lessons staged for ship-time promotion into .claude/memory (Phase 4.6). Only the DELTA no
# /phx:full session captures: report-only findings (never fixed → lost otherwise) + systemic aggregate
# patterns across the iteration. Rides the iteration branch; the ship step (5.3) promotes it — a
# :failed iteration drops the branch and the candidates die with it (build-confirmed knowledge).
LESSONS_MD="${FINDINGS_DIR}/candidate-lessons.md"

log() { printf '\n=== %s ===\n' "$1"; }

log "starting postgres"
start-postgres

log "configuring git"
git config --global credential.helper '!f() { echo username=x-access-token; echo "password=${GITHUB_TOKEN}"; }; f'
git config --global user.email "invoker@local"
git config --global user.name "invoker"
git config --global init.defaultBranch main

# The iteration branch already exists (cut from main at first feature dispatch) with every accepted
# feature merged into it. Clone it directly — the scan reads/reports on the integration state.
log "cloning ${REPO_URL} (${BRANCH})"
rm -rf "$APP_DIR"
git clone --branch "$BRANCH" "$REPO_URL" "$APP_DIR"
cd "$APP_DIR"

log "bridging agent memory"
# Same bridge as the build entrypoint: prior iterations' lessons (MEMORY.md) load at session start so
# finders/challenge see known systemic patterns; nothing new is written here (polish compounding is
# Phase 4/5), but the bridge keeps the read side consistent.
mkdir -p "$APP_DIR/.claude/memory" /root/.claude/projects/-workspace-app
rm -rf /root/.claude/projects/-workspace-app/memory
ln -s "$APP_DIR/.claude/memory" /root/.claude/projects/-workspace-app/memory

log "installing dependencies"
mix deps.get
mix setup || (mix ash.setup && mix assets.setup && mix assets.build)

log "computing integration delta"
# The diff base is main; HEAD is the iteration branch tip (all merged features). This file list scopes
# every finder to the iteration delta — the cross-feature view a single-feature build never saw.
git fetch origin "$BASE_BRANCH" >/dev/null 2>&1 || true
CHANGED_FILES="$(git diff --name-only "origin/${BASE_BRANCH}...HEAD" 2>/dev/null || git diff --name-only "${BASE_BRANCH}...HEAD" 2>/dev/null || true)"
mkdir -p "$FINDINGS_DIR"

log "running claude"
# Headless read-only finder fan-out + challenge gate. The scan writes exactly two files and does NOT
# touch product code or push. bypassPermissions + IS_SANDBOX=1 (root-guard escape) mirror the build.
#
# CONTRACT the entrypoint depends on (deterministic emission below reads these files, NOT the model's
# stdout): the session MUST write
#   1. ${FINDINGS_JSON} — a JSON ARRAY of finding objects:
#        [{"severity":"low|medium|high|critical","category":"…","file":"…","line":N|null,
#          "summary":"…","bucket":"auto_fix|report_only"}]
#   2. ${REPORT_MD} — a human-readable Markdown report of the REPORT-ONLY findings (the durable audit
#      record). Omit/empty it if there are none.

PROMPT="You are the QA-polish SCANNER for one iteration of this Phoenix/Ash + LiveVue app. You run
READ-ONLY: inspect the code, produce findings, write two files. You MUST NOT modify product code,
run generators/migrations, or push. The actual fixes are a separate build — your only job is to find
and classify.

Scope: the INTEGRATION DELTA of this iteration — the files changed versus ${BASE_BRANCH}:
${CHANGED_FILES:-(unable to compute; scan the whole app)}

This is a green iteration: CI already ran precommit (compile, format, credo --strict, sobelow,
deps.audit, test) on every feature, and each feature was already /phx:review'd and compounded during
its own build. So DO NOT re-report anything precommit or a single-feature review already covers
(formatting, credo lint, sobelow, dep audit, compile warnings, per-feature style). Target ONLY what
those cannot see: the cross-feature / whole-iteration view.

Run these finders as PARALLEL subagents in a single batch (they are read-only and write nothing that
conflicts), each scoped to the delta above:
  - ash-query-optimizer      — Ash N+1 (Ash.load in Enum / missing aggregate), calc-vs-load. [bucket: auto_fix]
  - ash-policy-reviewer      — Ash policy/check/actor-scope gaps sobelow cannot read.        [bucket: report_only unless a localized, safe policy fix — then auto_fix]
  - phoenix-patterns-analyst — cross-feature cohesion: duplicate helpers, naming drift, sneaky coupling, architecture. [bucket: report_only; a clear cross-file DUPLICATE helper is auto_fix]
  - testing-reviewer         — integration/coverage GAPS across features (not per-feature re-review). [bucket: auto_fix]

Then DEDUP findings surfaced by more than one finder (same file+line), and BUCKET each as:
  - auto_fix     — safe, localized, mechanically fixable (Ash N+1, test gaps, cross-feature dup helper).
  - report_only  — architecture / coupling / cohesion; a human decides whether to fix.

CHALLENGE GATE (do this before finalizing): for EVERY finding you bucketed auto_fix, apply adversarial
lenses (what would break this / assumption stress-test / is it actually reproducible on this diff). If
a finding does not clearly survive, DOWNGRADE it to report_only. A false auto_fix wastes a whole build.

Finally WRITE (create the directory if needed):
  1. ${FINDINGS_JSON} — a JSON array of ALL findings (both buckets) in the exact schema:
     [{\"severity\":\"…\",\"category\":\"…\",\"file\":\"…\",\"line\":N or null,\"summary\":\"…\",\"bucket\":\"auto_fix|report_only\"}]
     If there are no findings, write [].
  2. ${REPORT_MD} — a Markdown report of only the report_only findings (title, severity, file:line,
     why it matters, suggested direction). If there are none, write a one-line 'No report-only findings.'
  3. ${LESSONS_MD} — CANDIDATE LESSONS for the project's long-term memory: ONLY things a single
     feature's build could not have learned. Capture (a) each report-only finding phrased as a
     preventive lesson ('WHEN … PREFER …, because …'), and (b) SYSTEMIC aggregate patterns you saw
     REPEATED across features this iteration (e.g. 'N+1 via Ash.load-in-Enum recurred in 3 features').
     Do NOT restate per-feature fixes (those were already compounded during each feature's build). If
     there is nothing cross-cutting to teach, write a one-line 'No systemic lessons.'

You are headless — never stop for input. Do NOT git commit or push; the entrypoint owns that."

BUDGET_ARGS=""
if [ -n "${MAX_BUDGET_USD:-}" ]; then
  BUDGET_ARGS="--max-budget-usd $MAX_BUDGET_USD"
fi

set +e
# shellcheck disable=SC2086
IS_SANDBOX=1 claude --print "$PROMPT" \
  --output-format stream-json --verbose \
  --permission-mode bypassPermissions \
  --model "$MODEL" \
  $BUDGET_ARGS
set -e

log "emitting findings"
# Deterministic emission — read the agent-written findings.json (do NOT trust the model to print the
# control line itself). Wrap the array into the invoker_findings control line. Missing/invalid → [].
if [ -f "$FINDINGS_JSON" ] && jq -e 'type == "array"' "$FINDINGS_JSON" >/dev/null 2>&1; then
  jq -c '{type: "invoker_findings", findings: .}' "$FINDINGS_JSON"
else
  echo "WARN: no valid ${FINDINGS_JSON}; emitting empty finding set" >&2
  printf '{"type":"invoker_findings","findings":[]}\n'
fi

log "committing the polish report"
# Commit ONLY the scan artifacts under .claude/iterations/<id>/ (never product code — a read-only scan
# must not alter the branch's product state). Secret gate over the staged diff, same as the build.
REPORT_SHA=""
if [ -d "$FINDINGS_DIR" ]; then
  git add -f "$FINDINGS_DIR" >/dev/null 2>&1 || true

  if git diff --cached | grep -IqE 'gh[posru]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]+|sk-ant-[A-Za-z0-9-]+'; then
    echo "FATAL: token-shaped string in staged polish artifacts — refusing to commit/push" >&2
    exit 1
  fi

  if ! git diff --cached --quiet; then
    git commit -m "chore(polish): QA scan report for iteration ${ITERATION_ID}" >/dev/null 2>&1 || true
    git push -u origin "$BRANCH" >/dev/null 2>&1 || true
    SHA="$(git rev-parse HEAD)"
    REMOTE_SHA="$(git rev-parse "origin/$BRANCH" 2>/dev/null || true)"
    if [ -z "$REMOTE_SHA" ] || [ "$SHA" != "$REMOTE_SHA" ]; then
      echo "FATAL: polish report $SHA did not land on origin/$BRANCH (remote HEAD: ${REMOTE_SHA:-none})" >&2
      exit 1
    fi
    REPORT_SHA="$SHA"
  fi
fi

# Emit the report pointer only when a report artifact was actually committed.
if [ -n "$REPORT_SHA" ] && [ -f "$REPORT_MD" ]; then
  printf '{"type":"invoker_polish_report","sha":"%s","path":"%s"}\n' "$REPORT_SHA" "$REPORT_MD"
fi
