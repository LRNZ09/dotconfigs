# Move the Work-Term Guard to gitleaks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the angerona hooks with gitleaks: commit message, staged changes, pushes and Claude Code MCP calls are checked against the work terms and gitleaks' built-in secret rules.

**Architecture:** Two configs outside every repo (`~/.config/gitleaks/default.toml`, `~/.config/gitleaks/work.toml`, the second extending the first). Three git config-based hooks in dotconfigs `configs/git/config`, each an inline shell command (no script files), switched off by the existing `includeIf` files. One shell line in dotclaude `settings.json` for the Claude Code PreToolUse hook. A bats file pins the git hooks' behavior.

**Tech Stack:** gitleaks 8.30.1 (`/opt/homebrew/bin/gitleaks`), git 2.54+ config hooks, POSIX sh, bats-core, jq.

**Spec:** `docs/superpowers/specs/2026-11-18-angerona-to-gitleaks-design.md` (dotconfigs, commit 9e4bb73).

## Global Constraints

- gitleaks by full path `/opt/homebrew/bin/gitleaks`; every run passes `--no-banner --redact -v --ignore-gitleaks-allow -c ~/.config/gitleaks/work.toml`.
- Hook names `gitleaks-msg`, `gitleaks-staged`, `gitleaks-push`; switch-off file `configs/git/gitleaks-off`.
- `work.toml` extends `default.toml` by the absolute path `/Users/lorenzo/.config/gitleaks/default.toml`.
- Never set `GITLEAKS_CONFIG`/`GITLEAKS_CONFIG_TOML`, never add a global `.gitleaksignore`.
- Claude never reads `~/.config/angerona/terms.txt`, `~/.config/gitleaks/work.toml`, or `~/.claude/settings.json` / dotclaude `settings.json` (jq edits it without printing it).
- Never `--no-verify`. Commits signed (`%G?` = `G`), no attribution lines (dotconfigs is public).
- dotconfigs work happens on `feat/gitleaks-guard`. Its uncommitted changes in `INSTALL.md` (outside the guard paragraph), `configs/fish/config.fish`, `configs/proto/.prototools` and the credential-helper and `insteadOf` hunks of `configs/git/config` are not ours: never stage them.
- dotclaude: commit on its current branch (`main`), subject in its style with no type prefix; its uncommitted `settings.json` changes are not ours: never stage them.
- `~/.config/git` links into dotconfigs' working tree, so every edit to `configs/git/config` is live at once. `work.toml` must exist before Task 2 touches the hooks.
- Nothing is pushed, merged or deleted without Lorenzo's explicit go.

## Review Focus

- A user setting that changes `git log -p` output (`color.ui=always`) must not hide a term from the push check: test `push refuses a term with color.ui always` in Task 2.
- A remote named with a glob character (`*`) must not make the push check skip commits: test `push to a remote named * scans every commit` in Task 2.
- A pushed ref that is not a commit (a tag of a blob) must be refused, not passed because gitleaks' `git log` failed: test `push refuses a ref that is not a commit` in Task 2.
- A missing `work.toml` must refuse, not pass: test `staged refuses when work.toml is missing` in Task 2, and the missing-config case in Task 3 Step 3.
- A Claude session started in a work repo must pass MCP calls naming terms: Task 3 Step 3.

---

### Task 1: The two configs

Nothing here is committed: both files live outside every repo.

**Files:**

- Create: `~/.config/gitleaks/default.toml`
- Create (by Lorenzo): `~/.config/gitleaks/work.toml`

**Interfaces:**

- Produces: `~/.config/gitleaks/work.toml`, a gitleaks config whose rules are the built-in ones plus `term-1` … `term-N`, one per term, `description` = the term, `regex` = `(?i)\Q<term>\E`.

- [ ] **Step 1: Create the directory and `default.toml`**

```sh
mkdir -m 700 -p ~/.config/gitleaks
printf '[extend]\nuseDefault = true\n' > ~/.config/gitleaks/default.toml
chmod 600 ~/.config/gitleaks/default.toml
```

- [ ] **Step 2: Check `default.toml` catches a secret**

Build the token from two pieces so no file holds it whole.

Run: `printf '%s' "ghp_""aB3dE5fG7hI9jK1lM3nO5pQ7rS9tU1vW3xY5" | /opt/homebrew/bin/gitleaks stdin --no-banner -c ~/.config/gitleaks/default.toml --exit-code 2; echo $?`
Expected: `2`

- [ ] **Step 3: Hand Lorenzo the conversion, one line each, pasteable into fish**

The jq program builds the backslashes from `\`, so fish's single quotes pass it unchanged. It keeps angerona's list rules: spaces trimmed, blank lines and lines starting with `#` skipped.

```fish
jq -rnR '"[extend]", "path = \"/Users/lorenzo/.config/gitleaks/default.toml\"", (foreach (inputs | sub("^ +"; "") | sub(" +$"; "") | select(. != "" and (startswith("#") | not))) as $t (0; . + 1; "", "[[rules]]", "id = \"term-\(.)\"", "description = \($t | @json)", "regex = \("(?i)\Q\($t)\E" | @json)"))' ~/.config/angerona/terms.txt > ~/.config/gitleaks/work.toml
chmod 600 ~/.config/gitleaks/work.toml
grep -c '^\[\[rules\]\]' ~/.config/gitleaks/work.toml
grep -cvE '^ *(#|$)' ~/.config/angerona/terms.txt
printf '%s' 'xx<one of your terms in capitals>yy' | /opt/homebrew/bin/gitleaks stdin --no-banner -c ~/.config/gitleaks/work.toml --exit-code 2; echo $status
```

Before handing it over, run the same `jq` line on a fake list in the scratchpad (terms `Initech`, `Zürich` with spaces around it, `# comment`, a blank line, `Acme "Widgets"`) and check: `gitleaks stdin -c <fake work.toml>` exits 2 on `myINITECHapp`, `ZÜRICH` and `acme "widgets"`, 0 on `nothing`.

Expected from Lorenzo: the two counts match, and the last line prints `2`. Then back up `work.toml` in the password manager.

---

### Task 2: The git hooks

**Files:**

- Create: `bin/gitleaks-hooks.bats`
- Modify: `configs/git/config` (the uncommitted angerona block, around lines 126-153)
- Modify: `configs/git/config-work.example` (the uncommitted angerona block)
- Rename: `configs/git/angerona-off` → `configs/git/gitleaks-off` (untracked)
- Modify: `INSTALL.md` (the uncommitted angerona paragraph in step 3)

**Interfaces:**

- Consumes: `~/.config/gitleaks/work.toml` (Task 1).
- Produces: config keys `hook.gitleaks-msg.*` (event `commit-msg`), `hook.gitleaks-staged.*` (event `pre-commit`), `hook.gitleaks-push.*` (event `pre-push`). Task 3 reads `hook.gitleaks-push.enabled`.

- [ ] **Step 1: Write the failing tests in `bin/gitleaks-hooks.bats`**

Each test runs in a throwaway repo with a fake `HOME`, so no real config or list is read. Setup, per test:

- `REPO` = the dotconfigs root (as in `bin/doctor.bats`).
- `export HOME="$BATS_TEST_TMPDIR/home" GIT_CONFIG_NOSYSTEM=1`, `unset XDG_CONFIG_HOME GIT_CONFIG_GLOBAL`.
- A fake `$HOME/.config/gitleaks/default.toml` (`useDefault = true`) and `work.toml` extending it by its absolute path, with one rule: `id = "term-1"`, `description = "Initech"`, `regex = "(?i)\\QInitech\\E"`.
- A bare `remote.git`, and a repo `work` with `user.name`, `user.email`, `commit.gpgsign=false`, remote `origin` = `../remote.git`, and one clean commit pushed to `origin main`.
- A helper `hook NAME` that copies `hook.NAME.event` and `hook.NAME.command` from `git config --file "$REPO/configs/git/config"` into the repo's local config.
- The fake token is built from two pieces (`"ghp_""aB3dE5…"`) so dotconfigs' own gitleaks doesn't flag this file.

Tests, one assertion each (`run …` then one `[ "$status" … ]`):

| Test | Hook | Action | Assert |
| --- | --- | --- | --- |
| `msg refuses a message naming a term` | msg | commit `-m "fix for INITECH"` | `-ne 0` |
| `msg passes a clean message` | msg | commit `-m "fix typo"` | `-eq 0` |
| `staged refuses a term inside a longer word` | staged | add a line `myinitechapp`, commit | `-ne 0` |
| `staged refuses a secret` | staged | add a line with the fake token, commit | `-ne 0` |
| `staged passes a clean change` | staged | add a line `hello`, commit | `-eq 0` |
| `staged refuses when work.toml is missing` | staged | remove fake `work.toml`, add `hello`, commit | `-ne 0` |
| `push refuses a commit naming a term` | push | commit `Initech` with no commit hooks, push `origin HEAD:main` | `-ne 0` |
| `push passes a clean commit` | push | commit `hello`, push | `-eq 0` |
| `push skips what the remote holds` | push | commit `Initech` and push before adding the hook; then add it, commit `hello`, push | `-eq 0` |
| `push refuses a term with color.ui always` | push | `git config color.ui always`, commit `Initech`, push | `-ne 0` |
| `push to a remote named * scans every commit` | push | push the clean history plus a commit `Initech` to `origin` without the hook; add `remote.*.url` = `../remote.git` and the hook; commit `hello`; push `'*' HEAD:main` | `-ne 0` |
| `push refuses a ref that is not a commit` | push | `git tag blobtag "$(echo x \| git hash-object -w --stdin)"`, push `origin blobtag` | `-ne 0` |
| `push passes a deletion` | push | push `HEAD:refs/heads/old` without the hook, add it, push `origin :refs/heads/old` | `-eq 0` |

- [ ] **Step 2: Run them to see them fail**

Run: `bats bin/gitleaks-hooks.bats`
Expected: the `refuses` tests fail (no `hook.gitleaks-*` keys in the record yet, so nothing refuses).

- [ ] **Step 3: Rename the three hook sections in place**

```sh
git config --file configs/git/config rename-section hook.angerona-msg hook.gitleaks-msg
git config --file configs/git/config rename-section hook.angerona-staged hook.gitleaks-staged
git config --file configs/git/config rename-section hook.angerona-push hook.gitleaks-push
```

- [ ] **Step 4: Set the three commands with `git config --file configs/git/config set`, which escapes them**

`gitleaks-msg`: git appends the message file's path.

```sh
/opt/homebrew/bin/gitleaks dir --no-banner --redact -v --ignore-gitleaks-allow -c ~/.config/gitleaks/work.toml
```

`gitleaks-staged`:

```sh
/opt/homebrew/bin/gitleaks git --staged --no-banner --redact -v --ignore-gitleaks-allow -c ~/.config/gitleaks/work.toml
```

`gitleaks-push`: one line in the config; shown wrapped here. It follows `.lefthook/pre-push/gitleaks.sh` (read its comments for the why of each part) and ends in `; :` because git appends `"$@"` to the command.

```sh
not=; case $1 in '' | *[[:space:]]* | *[][*?\\]*) ;; *) git remote | grep -qxF -- "$1" && not=" --not --remotes=$1" ;; esac;
while read -r _ sha _ _; do
  case $sha in *[!0]*) ;; *) continue ;; esac;
  git rev-parse -q --verify "$sha^{commit}" >/dev/null || { echo "gitleaks-push: $sha is not a commit, and gitleaks scans only commits" >&2; exit 1; };
  /opt/homebrew/bin/gitleaks git --no-banner --redact -v --ignore-gitleaks-allow -c ~/.config/gitleaks/work.toml --log-opts="--no-color --no-ext-diff --no-textconv --root --diff-merges=first-parent $sha$not" || exit 1;
done; :
```

- [ ] **Step 5: Rewrite the comment above the hooks**

Same shape as the angerona one: the guard is gitleaks with `~/.config/gitleaks/work.toml` (work terms, extending `default.toml`'s built-in secret rules), refuses a commit or push that names a term or holds a secret, `config-work` switches it off under `~/Developer/work`, and `gitleaks-off` in dotclaude. Drop the `angerona doctor` line. Point the dotclaude `includeIf` at `gitleaks-off`.

- [ ] **Step 6: Switch-offs**

`mv configs/git/angerona-off configs/git/gitleaks-off`. In it and in `config-work.example`, rename the three sections to `gitleaks-*` (still `enabled = false`) and say "the work-term guard, gitleaks" in the comments.

- [ ] **Step 7: Run the tests**

Run: `bats bin/gitleaks-hooks.bats`
Expected: all 13 pass.

- [ ] **Step 8: Check the switch-offs, live**

Run: `git -C ~/Developer/LRNZ09/dotclaude config get --type=bool hook.gitleaks-push.enabled` and the same for a repo under `~/Developer/work`.
Expected: `false` both. And in dotconfigs itself: no output, exit 1 (the hook is on).

- [ ] **Step 9: `INSTALL.md`**

Replace the angerona paragraph in step 3: from here the git config runs gitleaks as hooks in every repo with the configs in `~/.config/gitleaks/`, so every commit and push is refused until `default.toml` and `work.toml` are restored (from the password manager).

- [ ] **Step 10: Commit, staging only the guard**

`git add bin/gitleaks-hooks.bats configs/git/gitleaks-off configs/git/config-work.example INSTALL.md`. For `configs/git/config`, write `git diff configs/git/config` to a scratchpad patch, delete the credential-helper and `insteadOf` hunks from it, and `git apply --cached` it. Check `git diff --cached --stat` lists only those five files, and `git diff configs/git/config` still shows the two hunks left out.

```sh
git commit -S -m "feat(git): Guard work terms and secrets with gitleaks hooks"
```

The commit runs through the new hooks: it is the first live check. Expected: committed, `git log -1 --format=%G?` prints `G`.

---

### Task 3: The Claude Code hook

**Files:**

- Modify: `~/Developer/LRNZ09/dotclaude/settings.json` (the PreToolUse hook whose `command` is `~/.local/bin/angerona check-json || exit 2`)

**Interfaces:**

- Consumes: `hook.gitleaks-push.enabled` (Task 2), `~/.config/gitleaks/work.toml` (Task 1).

The new command (POSIX sh; Claude Code runs hook commands through `/bin/sh`, checked live in Step 4):

```sh
[ "$(git -C "${CLAUDE_PROJECT_DIR:-/nonexistent}" config get --type=bool hook.gitleaks-push.enabled 2>/dev/null)" = false ] || /opt/homebrew/bin/gitleaks stdin --no-banner --redact -v --ignore-gitleaks-allow --exit-code 2 -c ~/.config/gitleaks/work.toml >&2 || exit 2
```

- [ ] **Step 1: Check the target exists once, without printing the file**

Run: `ls -l ~/.claude/settings.json` (must link into dotclaude), then `jq '[.. | objects | select(.command? == "~/.local/bin/angerona check-json || exit 2")] | length' ~/Developer/LRNZ09/dotclaude/settings.json`
Expected: `1`.

- [ ] **Step 2: Replace it with jq, in the working file and in a staged copy of `HEAD`'s**

One jq filter, `(.. | objects | select(.command? == $old) | .command) |= $new`, with `--arg old` and `--arg new`. Apply it to the working file (via a scratchpad temp file, then `cat` over the original so the link and flags stay). Apply it to `git show HEAD:settings.json` too, `git hash-object -w --stdin` the result, and `git update-index --cacheinfo 100644,<blob>,settings.json`, so only this change is staged.

Expected: `git -C ~/Developer/LRNZ09/dotclaude diff --cached --numstat` prints `1	1	settings.json`.

- [ ] **Step 3: Test the command by hand**

Run the command through `sh -c` with a JSON body on stdin, each with its own fake `CLAUDE_PROJECT_DIR`:

| Body | `CLAUDE_PROJECT_DIR` | Expected exit |
| --- | --- | --- |
| `{"tool_input":{"body":"meet INITECH"}}` (fake `HOME` with Task 2's fake configs) | a scratch repo with the hook on | 2 |
| same | a scratch repo with `hook.gitleaks-push.enabled false` | 0 |
| `{"tool_input":{"body":"hello"}}` | the first repo | 0 |
| the term body, fake `work.toml` removed | the first repo | 2 |
| the term body | unset | 2 |

- [ ] **Step 4: Live check (Lorenzo)**

In a new Claude Code session in a guarded repo, an MCP call whose input names a term is blocked; in a session under `~/Developer/work`, a Jira or Confluence call goes through.

- [ ] **Step 5: Commit in dotclaude**

```sh
git -C ~/Developer/LRNZ09/dotclaude commit -S -m "Guard MCP calls with gitleaks instead of angerona"
```

Expected: `%G?` = `G`, and `git status --short` still shows `settings.json` modified (the changes that were there before).

---

### Task 4: Retire the old copy

- [ ] **Step 1: Check nothing still calls it**

Run: `git config get --all --show-origin --regexp 'hook\..*\.command'` in dotconfigs, and `jq '[.. | strings | select(contains("angerona"))] | length' ~/Developer/LRNZ09/dotclaude/settings.json`
Expected: no `angerona` in the first; `0` from the second.

- [ ] **Step 2: Remove `~/.local/bin/angerona`, with Lorenzo's explicit OK**

Show the literal path, wait for the OK, then `rm /Users/lorenzo/.local/bin/angerona`. `~/.config/angerona/` stays.

- [ ] **Step 3: Update the angerona `HANDOFF.md` (not committed)**

Replace step 2 ("Switch to the Homebrew copy") with one line: the guard moved to gitleaks (dotconfigs `feat/gitleaks-guard`, dotclaude), the old binary is gone. Keep the held tag and the later items.

- [ ] **Step 4: Report, and hold**

Report the commits and test results. Merging `feat/gitleaks-guard` into dotconfigs `main` and pushing either repo wait for Lorenzo's go.
