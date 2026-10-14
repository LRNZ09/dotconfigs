# agents

`agents.toml` here is the `@sentry/dotagents` user-scope record. `~/.agents/agents.toml` is a link to it, made by hand (INSTALL.md step 3). dotagents writes it with a plain in-place write, so `dotagents add`, `remove`, `trust` and `mcp` land here as unstaged modifications, comments intact.

Everything else in `~/.agents` stays there and is not in this repo:

- **`agents.lock`** — dotagents' own machine state. In 3.1.0 `install` never reads it to resolve anything: it re-resolves every source from `agents.toml` on each run, so the lock records what was installed without being able to reproduce it. It only drives pruning, `sync` and `list`. Tracking it would turn every upstream push into a diff here.
- **`skills/`** — the installed copies. Two other tools write into it too: the `twg` CLI's `twg*` directories and Claude Code's `synced/` bucket. Neither is declared here, and neither should be.

## Traps

- **Never run `dotagents sync` here.** It adopts every undeclared directory under `skills/` — the `twg*` ones and `synced/` — as `path:skills/<name>` entries, which then break `install` on any machine without them. `install` and `doctor` cover everything else `sync` does.
- **A missing target is loud in the worst way.** If `agents.toml` disappears from this directory while the directory stays — a rename or `git rm` of the file — every dotagents command but `doctor`, `trust list` included, writes a default config through the link into this repo, and the next `install` prunes every skill. `git restore configs/agents/agents.toml`, then `npx @sentry/dotagents --user install`. `bin/doctor` reports the dangling link.
- **There is no `include` key.** dotagents drops unknown `[[skills]]` keys without a word, so `include = [...]` on a wildcard installs the whole source. An include list is one block per skill, as for getsentry/skills and anthropics/skills here.
- **`add` can't write a getsentry/skills or anthropics/skills block**, `--all` included. Both are plugin marketplaces, so `add` reads the skill name as a plugin name and fails with `Plugin "<name>" not found`. Write the block by hand with only `name` and `source`: `install` finds `skills/<name>` itself.
- **A listed skill that upstream renames or deletes stops `install`.** It exits 1 before pruning or writing the lock, and plugins, MCP and hooks are skipped with it. Fix or drop the block and run install again.
- **`remove <skill>` takes more than its block.** It deletes the block, the skill's folder and its lock entry without asking, and every line up to the next header, which takes the comment above the next block. The comment above the removed block stays behind. Reasons go inline on the `name` line for that reason.
- **A wildcard's `exclude` must stay on one line.** Against a multi-line array `remove` prints "Added … to exclude list" and leaves the file unchanged (getsentry/dotagents#205).
- **`trust add` and `trust remove` rebuild the `github_orgs` line**, dropping any comment on the same line.
- **Only a wildcard-against-wildcard name clash is loud.** Two wildcards that provide the same name stop `install`. An explicit block silently beats a wildcard with the same name, and of two explicit blocks with one name the later silently wins.

## Guard rails

`[trust]` limits sources to four GitHub orgs. `minimum_release_age` holds every source's commits back seven days, except `LRNZ09/*`. getsentry/skills and anthropics/skills are include lists, so a skill added upstream arrives only once it has its own block. The `dotagents` skill is pinned at 3.1.0, the same version as the CLI, which runs unpinned through `npx`.

The in-place write was measured on 3.1.0. dotagents already writes other files by temp-file-and-rename, so a later release could replace the link with a regular file; `bin/doctor`'s link test is what would notice.
