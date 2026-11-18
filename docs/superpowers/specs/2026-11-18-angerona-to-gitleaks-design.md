# Move the work-term guard from angerona to gitleaks

## Why

The guard keeps work terms (employer, clients, codenames) out of public repos. That rarely comes up. A check of gitleaks 8.30.1 (docs, source and hands-on tests, 2026-11-18) showed it covers the parts that matter: case-insensitive matches anywhere in staged changes, commit messages, pushed commits, and MCP calls. The gaps (author names, ref and tag names, tag messages, whole-file reads) don't matter for this use. Moving to gitleaks frees the angerona name for a new project and drops a binary, a release workflow and a tap token to maintain. While at it, the same guard also catches secrets, with gitleaks' built-in rules.

## Goals

- The same protection for commits, pushes and MCP calls, with gitleaks from Homebrew, plus gitleaks' built-in secret rules.
- Work repos and dotclaude stay switched off, through the same git `includeIf` files.
- Claude sessions in a switched-off repo still pass every MCP call (Jira, Confluence), as now.
- A repo with its own gitleaks setup (a work repo's lefthook, pre-commit or CI; dotconfigs' and brewfile's `.gitleaks.toml`) works as before, and its setup doesn't change this guard.

## Non-goals

- Author, committer, branch and tag name checks, and tag messages: gitleaks never scans them.
- The secret rules in work repos: the guard stays off there as a whole (see Work repos with their own gitleaks).
- Anything in the angerona repo: its future is a separate decision; the `v0.1.0` tag stays held.

## Approaches

- **A. Plain gitleaks (picked).** A TOML list, git hooks and a Claude hook, all inline in config, with no script files.
- B. A wrapper script that keeps `terms.txt` and refuses an empty list: a smaller angerona to maintain again.
- C. gitleaks for git, angerona for the Claude hook: keeps angerona installed, so the name can't start over.

## Design

1. **The config:** two files in `~/.config/gitleaks/` (dir 700, files 600), outside every repo:
   - `default.toml`: the secret rules, `[extend] useDefault = true`.
   - `work.toml`: the work terms, one rule per term, `regex = "(?i)\\QTerm\\E"`, so a term needs no escaping. It starts with `[extend] path = "/Users/lorenzo/.config/gitleaks/default.toml"`, so one run checks both. The path must be absolute: gitleaks reads a relative one from the current directory (tested with 8.30.1, which then fails to load the config).
   - Every hook passes `-c ~/.config/gitleaks/work.toml`.
   - Lorenzo makes `work.toml` once from `~/.config/angerona/terms.txt` with a command Lorenzo runs; Claude never reads either list. New terms are added to `work.toml` directly. It is backed up in the password manager, as the list is now.
2. **Git hooks** in `configs/git/config`, by full path `/opt/homebrew/bin/gitleaks`, each with `--no-banner --ignore-gitleaks-allow -c ~/.config/gitleaks/work.toml`:
   - `gitleaks-msg` on `commit-msg`: `gitleaks dir` on the message file git passes.
   - `gitleaks-staged` on `pre-commit`: `gitleaks git --staged`.
   - `gitleaks-push` on `pre-push`: an inline shell command in the config, no script file. It follows dotconfigs' `.lefthook/pre-push/gitleaks.sh`, which handles what a bare `gitleaks git --log-opts` gets wrong: for each pushed commit (git's ref lines on stdin, deletions skipped), it refuses what isn't a commit, since gitleaks passes silently when its `git log` fails; it passes `--no-color --no-ext-diff --no-textconv --root --diff-merges=first-parent`, since user diff settings hide lines otherwise; and it leaves out what the remote-tracking refs hold only when `$1` has no space or glob character, since gitleaks splits `--log-opts` at spaces. The lefthook script stays as it is, for dotconfigs' own config.
3. **Switch-offs:** `config-work.example` and `angerona-off` (renamed `gitleaks-off`) switch off the three `gitleaks-*` hooks.
4. **Claude hook** in dotclaude `settings.json`, replacing the angerona line: pass when the project's git has `hook.gitleaks-push.enabled` false, otherwise `gitleaks stdin --exit-code 2 -c ~/.config/gitleaks/work.toml`, terms and secrets both, with `|| exit 2` so a missing config or any error blocks.
5. **Docs:** the config comment and `INSTALL.md` name gitleaks instead of angerona.
6. **Order, since the guard fails closed:** TOML first and test it; then switch the hooks; check a commit and a push (to a throwaway remote) in a guarded repo, a commit in a work repo, and an MCP call in a work and a non-work session; only then remove `~/.local/bin/angerona` (with an explicit OK). `~/.config/angerona/` stays until Lorenzo says otherwise.

## Work repos with their own gitleaks

- The guard is off in work repos, secret rules included, so it can't refuse what the team's own gitleaks config allows.
- The guard never sets `GITLEAKS_CONFIG` or `GITLEAKS_CONFIG_TOML`, and keeps no global `.gitleaksignore`, so a repo's own gitleaks runs see nothing of it.
- The guard always passes `-c`, so a repo's `.gitleaks.toml` never replaces the term list, and `--ignore-gitleaks-allow`, so a repo's `gitleaks:allow` comments don't mute it. A repo's `.gitleaksignore` still applies (`-i` defaults to the repo); it mutes only findings it lists by fingerprint, which would have to name a term rule's id.
- The switch-offs name the `gitleaks-*` hooks. A work repo that sets up its own config hook under one of those exact names (`hook.gitleaks-staged.*` in its `.git/config`) would be switched off with ours; hooks from lefthook, pre-commit or `.git/hooks` are never touched.
- In a guarded repo that has its own gitleaks setup (dotconfigs, brewfile), both run. The guard ignores that repo's allowlist, so a value the repo allows on purpose (dotconfigs' template files) can still be refused if a built-in rule matches it.

## Known trade-offs (accepted)

- An empty `work.toml` passes everything; a missing one, or a missing `default.toml`, blocks.
- `commit.verbose` is on, so an editor commit's message file holds `#` comments and the diff below the scissors line, and `gitleaks dir` scans them: a commit that removes a term or a secret, or a branch named after a term, is refused. `git commit -m` works around it.
- The built-in rules add false positives, in MCP calls too; `generic-api-key` is the noisy one. If it gets in the way, turn that rule off in `default.toml`.
- In a work session every MCP call passes, GitHub included; angerona still checked GitHub calls to other owners there.
- The push check leaves out only what the pushed-to remote's own tracking refs hold, as dotconfigs' lefthook script does, so a private remote's history never counts as public. A push to a remote that was added but never fetched (a fork, say) scans the whole history, built-in secret rules included, and can be refused for someone else's commit. `git fetch <remote>` first works around it. (Added 2026-11-18, after the final review.)

## Left to the builder

- Exact shell quoting of the git and Claude hook lines, tested with a fake list in a throwaway repo and project. git runs a config hook as `sh -c '<command> "$@"'` with its arguments appended.
- The pre-push command's quoting in the config file, and its end: git appends `"$@"`, so the command must end in something that takes arguments (`; :` after the loop, since `done "$@"` is a syntax error).
- The conversion command for the list, pasteable into fish, tested on a fake `terms.txt`.
- How to turn off one built-in rule in 8.30.1, checked before it goes in the doc.
- Which dotconfigs changes go in which commit: the repo has unrelated uncommitted changes (fish, proto) that stay out.
