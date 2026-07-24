#!/usr/bin/env bash
# invoker-build (X2) — the build entrypoint. Invoker `msb exec`s this; its stdout is the build stream
# (claude `--output-format stream-json`) that BuildConsoleLive renders. It must NOT POST a callback.
#
# Env injected per-sandbox by Invoker.Projects.Feature.Changes.DispatchBuild (+ F3 secrets):
#   BRIEF_B64 ACCEPTANCE_CRITERIA_B64 PRODUCT_SPEC_B64 REVIEW_FEEDBACK_B64  (base64 — decoded below)
#   REPO_URL BASE_BRANCH(=main) BRANCH(=build/<id>) FEATURE_ID SESSION_ID
#   GITHUB_TOKEN MODEL MAX_BUDGET_USD  + ONE of: CLAUDE_CODE_OAUTH_TOKEN | ANTHROPIC_API_KEY
set -euo pipefail

: "${REPO_URL:?REPO_URL required}"
: "${BRANCH:?BRANCH required}"
: "${GITHUB_TOKEN:?GITHUB_TOKEN required}"
# claude authenticates with EITHER a Claude-subscription OAuth token (preferred, billed to the
# subscription) OR the metered API key. DispatchBuild injects exactly one; require at least one here.
if [ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] && [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  echo "FATAL: set CLAUDE_CODE_OAUTH_TOKEN (claude subscription) or ANTHROPIC_API_KEY" >&2
  exit 1
fi
BASE_BRANCH="${BASE_BRANCH:-main}"
MODEL="${MODEL:-claude-opus-4-8}"
APP_DIR=/workspace/app

# The free-text context fields (brief, criteria, spec, rework feedback) arrive base64-encoded with a
# _B64 suffix — DispatchBuild encodes them so LLM-authored text (em-dashes, smart quotes, arrows) can
# be injected as env values without tripping the sandbox VMM's non-ASCII guard. Decode them back to
# the bare names used when assembling the prompt below. The `:-` guards keep `set -u` happy when a
# field is absent; an empty/unset value decodes to "" and the downstream `${VAR:-default}` still fires.
decode_b64() { [ -n "${1:-}" ] && printf '%s' "$1" | base64 --decode || true; }
BRIEF="$(decode_b64 "${BRIEF_B64:-}")"
ACCEPTANCE_CRITERIA="$(decode_b64 "${ACCEPTANCE_CRITERIA_B64:-}")"
PRODUCT_SPEC="$(decode_b64 "${PRODUCT_SPEC_B64:-}")"
REVIEW_FEEDBACK="$(decode_b64 "${REVIEW_FEEDBACK_B64:-}")"

log() { printf '\n=== %s ===\n' "$1"; }

log "starting postgres"
start-postgres

log "configuring git"
# Credential helper feeds the scoped token without baking it into the remote URL.
git config --global credential.helper '!f() { echo username=x-access-token; echo "password=${GITHUB_TOKEN}"; }; f'
git config --global user.email "invoker@local"
git config --global user.name "invoker"
git config --global init.defaultBranch main

# The host already scaffolded `main` (template fetch + rename + initial push happen on the host, NOT
# in this VM), so the remote is always populated. A prior attempt — a failed build, or a
# `request_changes` rework — may have already pushed commits to $BRANCH; REUSE them. Continuing on
# top keeps the committed plans (`.claude/plans/**`) and partial implementation instead of rebuilding
# from scratch (too expensive to throw away), and keeps the post-commit push a fast-forward — a
# fresh-from-main branch would non-ff-reject against the prior attempt's remote HEAD and silently
# drop this attempt's commits. No existing branch → branch fresh from $BASE_BRANCH.
rm -rf "$APP_DIR"
if git clone --branch "$BRANCH" "$REPO_URL" "$APP_DIR" 2>/dev/null; then
  log "reusing existing ${BRANCH} (continuing a prior attempt)"
  cd "$APP_DIR"
else
  log "cloning ${REPO_URL} (${BASE_BRANCH}); creating ${BRANCH}"
  git clone --branch "$BASE_BRANCH" "$REPO_URL" "$APP_DIR"
  cd "$APP_DIR"
  git checkout -b "$BRANCH"
fi

log "bridging agent memory"
# Claude Code's auto-memory lives OUTSIDE the repo — keyed by cwd at
# /root/.claude/projects/-workspace-app/memory/ — so the lessons the agent captures in the
# compound phase die with this container. Symlink that path into the repo (.claude/memory, not
# gitignored → committed by the `git add -A` below): prior builds' lessons load at session start
# (Claude Code injects MEMORY.md), and new ones round-trip through git to the next attempt.
mkdir -p "$APP_DIR/.claude/memory" /root/.claude/projects/-workspace-app
rm -rf /root/.claude/projects/-workspace-app/memory
ln -s "$APP_DIR/.claude/memory" /root/.claude/projects/-workspace-app/memory

log "installing dependencies"
mix deps.get
# `mix setup` runs the generated app's own setup alias (deps, ash.setup, assets). Fall back to the
# pieces if the app has no `setup` alias.
mix setup || (mix ash.setup && mix assets.setup && mix assets.build)

log "wiring post-commit push"
# Push every agent commit to the feature branch as it lands (so progress is visible / recoverable).
cat > .git/hooks/post-commit <<HOOK
#!/usr/bin/env bash
git push -u origin "${BRANCH}" >/dev/null 2>&1 || true
HOOK
chmod +x .git/hooks/post-commit

log "running claude"
# Headless agentic build via the plugin's **/phx:full** workflow (plan → work → verify → review →
# compound, with specialist agents + Iron-Law gates). stream-json (the worker parses it) requires
# --verbose with -p; the plugin loads from the repo's committed .claude/settings.json enabledPlugins.
# /phx:full is designed to run autonomously end-to-end (it should NOT stall on a plan-approval prompt).
#
# Permissions: `bypassPermissions` auto-approves EVERY tool (Bash, MCP, …), not just edits. The old
# `acceptEdits` auto-approved file writes ONLY — so `mix`/`git`/chained-bash were all denied with no
# interactive approver, and the agent built blind (couldn't run ash.codegen/tests/precommit or commit).
# claude refuses bypassPermissions as root unless IS_SANDBOX=1 (its root-guard escape) — true here: we
# are a libkrun microVM, an actual sandbox.
#
# The context pack (product spec + acceptance criteria, assembled by DispatchBuild) goes in the
# feature description. We deliberately do NOT pass a "what already exists" digest — /phx:full
# inspects the cloned codebase to learn the current state. Acceptance-test pass in CI is the thesis
# metric, so the tests are the contract: a genuine passing test per criterion, never weakened.

# Rework feedback (REVIEW_FEEDBACK, set by request_changes) goes INSIDE the description so the
# prompt still starts with the /phx:full command.
FEEDBACK_SECTION=""
if [ -n "${REVIEW_FEEDBACK:-}" ]; then
  FEEDBACK_SECTION="## Reviewer feedback (address this FIRST)
${REVIEW_FEEDBACK}
"
fi

PROMPT="/phx:full Implement a feature in this existing Phoenix/Ash + LiveVue app, following the
project's conventions (CLAUDE.md + the loaded skills). Inspect the existing codebase to understand
what is already built before adding to it. Do NOT push — a git hook handles that.

You are running headless — there is no user to answer questions. Never stop to present options or
wait for input; where the workflow asks the user to choose (e.g. discovery's workflow depth),
decide yourself from the feature's complexity and continue. On a fresh scaffold with no existing
domains, the codebase-patterns and library research agents may be skipped when there is nothing
for them to analyze — note the skip in the plan instead.

${FEEDBACK_SECTION}## Product context (the whole product this feature is part of)
${PRODUCT_SPEC:-(none provided)}

## Feature to build
${BRIEF:-(no brief provided)}

## Acceptance criteria — satisfy EVERY one with a genuine passing automated test
${ACCEPTANCE_CRITERIA:-(none specified)}

Each criterion needs a real test (ExUnit / Phoenix.LiveViewTest, or LiveVue.Test for Vue surfaces)
that actually verifies it — never weaken or delete a test to make it pass."

# Budget cap ($): `claude` hard-stops when spend reaches this (only works with --print, which we use).
# MAX_BUDGET_USD is injected by dispatch; guard so a manual run without it doesn't pass an empty value.
# Unquoted expansion is intentional — it's a bare number (no word-splitting risk) or nothing.
BUDGET_ARGS=""
if [ -n "${MAX_BUDGET_USD:-}" ]; then
  BUDGET_ARGS="--max-budget-usd $MAX_BUDGET_USD"
fi

# Don't let an agent failure abort the script — we still want to persist artifacts + emit the SHA so
# the control plane can recover (the dead-end scratchpad survives for the next attempt).
set +e
# shellcheck disable=SC2086
IS_SANDBOX=1 claude --print "$PROMPT" \
  --output-format stream-json --verbose \
  --permission-mode bypassPermissions \
  --model "$MODEL" \
  $BUDGET_ARGS
set -e

log "committing the build"
# WE own the commit — do NOT assume the agent committed. The prompt tells it "Do NOT push — a git
# hook handles that", and it leaves its work as uncommitted working-tree changes. Stage EVERYTHING
# it produced: feature code, plans/scratchpad, and the memory bridged into .claude/memory above.
# Nothing under .claude/ is gitignored in this template, so `git add -A` covers it all; the -f on
# .claude/plans is belt-and-suspenders in case a generated app ever grows a .claude ignore rule.
git add -A >/dev/null 2>&1 || true
[ -d .claude/plans ] && git add -f .claude/plans >/dev/null 2>&1 || true
[ -d .claude/memory ] && git add -f .claude/memory >/dev/null 2>&1 || true

# Secret gate over the WHOLE staged diff (not just plans): the agent ran with a live GITHUB_TOKEN and
# LLM keys in env — if a token-shaped string leaked into ANY file, refuse the commit rather than push
# a secret to a mergeable branch. Unstage and bail loudly so the control plane blocks this attempt.
if git diff --cached | grep -IqE 'gh[posru]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]+|sk-ant-[A-Za-z0-9-]+'; then
  echo "FATAL: token-shaped string in staged changes — refusing to commit/push" >&2
  exit 1
fi

if git diff --cached --quiet; then
  # Nothing staged. Two very different reasons — disambiguate by whether HEAD already moved past base:
  #  - Agent committed its own work: the prompt says "don't PUSH" (not "don't commit"), and /phx:full
  #    often git-commits itself. Then the working tree is clean but HEAD is ahead of base and the
  #    post-commit hook already pushed it — the work IS delivered, the finalize push below just
  #    fast-forwards. NOT a failure; the old "nothing to deliver" WARN here was a false alarm.
  #  - Agent produced nothing at all: HEAD still equals base. Emit no invoker_commit — a false SHA
  #    equal to base would sail through verify (CI green on scaffold) and blow up later at preview.
  #    The "no commits beyond base" guard in finalize then blocks the build, which is correct.
  if [ "$(git rev-parse HEAD)" = "$(git rev-parse "origin/$BASE_BRANCH" 2>/dev/null || true)" ]; then
    echo "WARN: agent produced no changes to commit — nothing to deliver" >&2
  else
    echo "note: agent committed its own work; delivering its commit(s)" >&2
  fi
else
  git commit -m "feat(invoker): build ${FEATURE_ID:-feature}" >/dev/null 2>&1 || true
fi

log "finalizing"
# Push and VERIFY the remote actually advanced. The post-commit hook's push is fire-and-forget
# (git ignores its exit code), so a failed push is otherwise SILENT — the whole reason a build can
# report a commit that never landed. Keep push output off the stream (the credential helper feeds
# the token over stdout), then compare local HEAD to origin/$BRANCH and only emit invoker_commit
# when they match. A mismatch (or a branch with no commits beyond base) fails the build loudly.
git push -u origin "$BRANCH" >/dev/null 2>&1 || true
SHA="$(git rev-parse HEAD)"
REMOTE_SHA="$(git rev-parse "origin/$BRANCH" 2>/dev/null || true)"

if [ -z "$REMOTE_SHA" ] || [ "$SHA" != "$REMOTE_SHA" ]; then
  echo "FATAL: build commit $SHA did not land on origin/$BRANCH (remote HEAD: ${REMOTE_SHA:-none})" >&2
  exit 1
fi

if [ "$SHA" = "$(git rev-parse "origin/$BASE_BRANCH" 2>/dev/null || true)" ]; then
  echo "FATAL: $BRANCH has no commits beyond $BASE_BRANCH — nothing was built" >&2
  exit 1
fi

# Control line the worker reads for the feature's commit_sha.
printf '{"type":"invoker_commit","sha":"%s"}\n' "$SHA"
