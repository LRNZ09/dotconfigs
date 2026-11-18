#!/usr/bin/env bats
# dotconfigs/bin/gitleaks-hooks.bats — the work-term guard's git hooks, as
# configs/git/config defines them, run in throwaway repos. Each test copies the
# hooks it needs into a repo of its own, under a fake HOME with a fake term
# list, so neither the real list nor the global git config is read.
#
# Run it with: bats bin/gitleaks-hooks.bats

setup() {
	REPO=$(cd -- "$(dirname -- "$BATS_TEST_FILENAME")/.." && pwd -P)
	export HOME="$BATS_TEST_TMPDIR/home" GIT_CONFIG_NOSYSTEM=1
	unset XDG_CONFIG_HOME GIT_CONFIG_GLOBAL
	mkdir -p "$HOME/.config/gitleaks"
	printf '[extend]\nuseDefault = true\n' >"$HOME/.config/gitleaks/default.toml"
	printf '[extend]\npath = "%s"\n\n[[rules]]\nid = "term-1"\ndescription = "Initech"\nregex = "(?i)\\\\QInitech\\\\E"\n' \
		"$HOME/.config/gitleaks/default.toml" >"$HOME/.config/gitleaks/work.toml"
	# In two pieces, so dotconfigs' own gitleaks doesn't flag this file.
	ghp="ghp_""aB3dE5fG7hI9jK1lM3nO5pQ7rS9tU1vW3xY5"

	git init -q --bare "$BATS_TEST_TMPDIR/remote.git"
	git init -q -b main "$BATS_TEST_TMPDIR/work"
	cd "$BATS_TEST_TMPDIR/work"
	git config user.name Test
	git config user.email test@users.noreply.github.com
	git config commit.gpgsign false
	git config tag.gpgsign false
	git remote add origin ../remote.git
	commit clean hello
	git push -q origin main
}

# Copies hook $1's event and command from the record into this repo.
hook() {
	git config "hook.$1.event" "$(git config --file "$REPO/configs/git/config" "hook.$1.event")"
	git config "hook.$1.command" "$(git config --file "$REPO/configs/git/config" "hook.$1.command")"
}

# Commits a file $1 holding the line $2.
commit() {
	printf '%s\n' "$2" >"$1"
	git add "$1"
	git commit -qm "add $1"
}

@test "msg refuses a message naming a term" {
	hook gitleaks-msg
	echo x >f
	git add f
	run git commit -qm "fix for INITECH"
	[ "$status" -ne 0 ]
}

@test "msg passes a clean message" {
	hook gitleaks-msg
	echo x >f
	git add f
	run git commit -qm "fix typo"
	[ "$status" -eq 0 ]
}

@test "staged refuses a term inside a longer word" {
	hook gitleaks-staged
	run commit f myinitechapp
	[ "$status" -ne 0 ]
}

@test "staged refuses a secret" {
	hook gitleaks-staged
	run commit f "$ghp"
	[ "$status" -ne 0 ]
}

@test "staged passes a clean change" {
	hook gitleaks-staged
	run commit f hello
	[ "$status" -eq 0 ]
}

@test "staged refuses when work.toml is missing" {
	hook gitleaks-staged
	rm "$HOME/.config/gitleaks/work.toml"
	run commit f hello
	[ "$status" -ne 0 ]
}

@test "push refuses a commit naming a term" {
	hook gitleaks-push
	commit f Initech
	run git push -q origin HEAD:main
	[ "$status" -ne 0 ]
}

@test "push refuses a commit whose message names a term" {
	hook gitleaks-push
	echo x >f
	git add f
	git commit -qm "port the Initech fix"
	run git push -q origin HEAD:main
	[ "$status" -ne 0 ]
}

@test "push passes a clean commit" {
	hook gitleaks-push
	commit f hello
	run git push -q origin HEAD:main
	[ "$status" -eq 0 ]
}

@test "push skips what the remote holds" {
	commit f Initech
	git push -q origin main
	hook gitleaks-push
	commit g hello
	run git push -q origin HEAD:main
	[ "$status" -eq 0 ]
}

@test "push refuses a term with color.ui always" {
	hook gitleaks-push
	git config color.ui always
	commit f Initech
	run git push -q origin HEAD:main
	[ "$status" -ne 0 ]
}

@test "push refuses a term a textconv driver would hide" {
	hook gitleaks-push
	echo '* diff=blank' >.git/info/attributes
	git config diff.blank.textconv true
	commit f Initech
	run git push -q origin HEAD:main
	[ "$status" -ne 0 ]
}

@test "push refuses a term in a root commit with log.showRoot off" {
	hook gitleaks-push
	git config log.showRoot false
	git switch -q --orphan other
	commit f Initech
	run git push -q origin other
	[ "$status" -ne 0 ]
}

@test "push refuses a term only a merge adds" {
	hook gitleaks-push
	git switch -q -c side
	commit s hello
	git switch -q main
	commit m hello
	git merge -q --no-commit side
	printf 'Initech\n' >f
	git add f
	git commit -qm merge
	run git push -q origin HEAD:main
	[ "$status" -ne 0 ]
}

@test "push to a remote named * scans every commit" {
	commit f Initech
	git push -q origin main
	git config 'remote.*.url' ../remote.git
	hook gitleaks-push
	commit g hello
	run git push -q '*' HEAD:main
	[ "$status" -ne 0 ]
}

@test "push refuses a ref that is not a commit" {
	hook gitleaks-push
	git tag blobtag "$(echo x | git hash-object -w --stdin)"
	run git push -q origin blobtag
	[ "$status" -ne 0 ]
}

@test "push passes a deletion" {
	git push -q origin HEAD:refs/heads/old
	hook gitleaks-push
	run git push -q origin :refs/heads/old
	[ "$status" -eq 0 ]
}
