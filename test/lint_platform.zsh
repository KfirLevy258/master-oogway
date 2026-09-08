#!/usr/bin/env zsh
# Fails if a plugin or theme file reaches for a raw platform call.
# Everything platform-specific belongs in omz-custom/lib/platform.zsh.
setopt EXTENDED_GLOB
MO_ROOT="${0:A:h:h}"

# lib/platform.zsh is the one place platform-specific calls belong.
typeset -i rc=0

typeset -a banned=(
	'\buname\b'
	'/proc/'
	'\bnproc\b'
	'\bxdg-open\b'
	'\bwl-copy\b'
	'\bxclip\b'
	'date -d'
	'--no-overwrite-dir'
	'/etc/os-release'
	'\bsystemctl\b'
	'apt install'
	'\btrash-put\b'
)

for f in "$MO_ROOT"/omz-custom/plugins/mo-*/**/*(.N) "$MO_ROOT"/omz-custom/themes/**/*(.N); do
	[[ "$f" == *.md ]] && continue
	[[ "$f" == */lib/platform.zsh ]] && continue
	# A file may opt out by declaring why, on one line, near the top. Used for
	# code that is Linux-only by construction — lan-ssh needs cron and systemd
	# and refuses to run on macOS — and for optional-deps metadata, which names
	# Linux package names on purpose.
	if command grep -qE '^#[[:space:]]*platform-lint:[[:space:]]*(linux-only|metadata)\b' "$f"; then
		continue
	fi
	for pat in $banned; do
		if command grep -nE "$pat" "$f" >/dev/null 2>&1; then
			print -r -- "PLATFORM LINT: ${f#$MO_ROOT/} matches /$pat/"
			command grep -nE "$pat" "$f" | sed 's/^/    /'
			rc=1
		fi
	done
done

(( rc == 0 )) && print -r -- "platform lint: clean"
exit $rc
