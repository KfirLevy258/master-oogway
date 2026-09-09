source "$MO_ROOT/omz-custom/lib/platform.zsh"

# Behavioural coverage for the commands the audit found dead on macOS behind a
# green suite. Each asserts on output, not merely on a zero exit.

_mo_b() {
	local plug="$1"; shift
	zsh -c "
		setopt EXTENDED_GLOB
		export ZSH_CUSTOM='$MO_ROOT/omz-custom'
		for f in '$MO_ROOT'/omz-custom/lib/*.zsh(#qN); do source \$f; done
		source '$MO_ROOT/omz-custom/plugins/$plug/$plug.plugin.zsh' 2>/dev/null
		$*
	" 2>&1
}

# ── mo-welcome: every field must report a real value ─────────────────────────
# The suite previously checked only that this file parses. Each field is called
# by its own function and the result is pattern-matched, so a field that starts
# returning an error string — or nothing — fails instead of passing on the noise.
local -A _want=(
	[host]='.+@.+'
	[os]='[A-Za-z]+ ?[0-9.]*'
	[sys]='[0-9]+\.[0-9]+'
	[now]='[0-9]'
	[up]='[0-9]+[dhm]'
	[shell]='zsh [0-9]+\.[0-9]+'
	[load]='[0-9]+\.[0-9]+'
	[mem]='[0-9.]+ */ *[0-9.]+ *GB'
	[disk]='[0-9]+%'
	[arch]='(arm64|x86_64|aarch64)'
)
# The plugin prints its banner when sourced; silence it so each assertion sees
# only the field it asked for.
export MO_WELCOME_FIELDS=""
local _f _out
for _f in ${(k)_want}; do
	_out=$(_mo_b mo-welcome "_mo_welcome_field_${_f}")
	assert_not_contains "$_out" "command not found" "welcome field '$_f' exists"
	assert_match "$_out" "${_want[$_f]}" "welcome field '$_f' reports a real value"
done
unset MO_WELCOME_FIELDS

# disk read the sealed APFS system snapshot, which is a couple of percent
# whatever the machine is doing, so the 70/90 thresholds could never fire.
local _pct=$(_mo_disk_pct)
assert_match "$_pct" '^[0-9]+$' "disk_pct is a bare integer"
if _mo_is_macos; then
	assert_eq "$(df -P /System/Volumes/Data | awk 'NR==2{gsub(/%/,"",$5); print $5}')" "$_pct" \
		"disk_pct measures the writable volume, not the system snapshot"
	# And the field must actually call the primitive. It did not: the primitive
	# was added and mo-welcome kept its own `df -P /`, so the banner still
	# reported the snapshot's 2% while the primitive tested clean.
	export MO_WELCOME_FIELDS=""
	assert_contains "$(_mo_b mo-welcome '_mo_welcome_field_disk' | sed $'s/\x1b\[[0-9;]*m//g')" \
		"${_pct}%" "the disk field reports what disk_pct measured"
	unset MO_WELCOME_FIELDS
fi

# local_ip must fall through to ifconfig for interfaces ipconfig cannot answer
# for (static addresses, VPN tunnels) — the Linux branch has that second tier.
assert_match "$(_mo_local_ip)" '^([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)?$' "local_ip is an address or empty"

# ── connected: who -u differs by one field between the platforms ─────────────
# GNU prints one ISO date token, BSD prints three, so parsing by column put the
# wrong value in every field after the username. _mo_who_sessions parses from
# the right, where both agree.
_parse_who() {
	print -r -- "$1" | awk '
		NF >= 5 {
			host = ""; last = NF
			if ($NF ~ /^\(.*\)$/) { host = substr($NF, 2, length($NF) - 2); last = NF - 1 }
			login = ""
			for (i = 3; i <= last - 2; i++) login = login (login == "" ? "" : " ") $i
			printf "%s|%s|%s|%s", $1, login, $last, host
		}'
}
assert_eq "kfir|2026-09-08 21:38|1234|192.168.1.9" \
	"$(_parse_who 'kfir pts/0 2026-09-08 21:38 . 1234 (192.168.1.9)')" \
	"who parser handles the GNU shape"
assert_eq "kfir|Sep 8 21:38|66764|192.168.1.9" \
	"$(_parse_who 'kfir ttys002 Sep 8 21:38 00:03 66764 (192.168.1.9)')" \
	"who parser handles the BSD shape"
assert_eq "kfir|Sep 8 21:38|905|" \
	"$(_parse_who 'kfir console Sep 8 21:38 16:18 905')" \
	"who parser handles a local session with no host"

# connected -v needed `ss`, which macOS has no port of.
assert_ok "ssh_peer answers without ss" _mo_ssh_peer 127.0.0.1

# ── mo-search: two parsers that returned nothing on macOS ────────────────────
# `man -k ''` matches everything under man-db and nothing under mandoc.
# `man -k` of any kind needs a built index, and `command -v man` does not tell
# you there is one. Installing packages leaves man-db rebuilding its cache in
# the background, and inside that window every apropos query returns nothing —
# which failed this assertion on a CI runner while saying nothing whatever about
# the pattern under test. Probe with a concrete page first: no index means the
# comparison is moot, a working index means a `.` that finds nothing is real.
if command -v man &>/dev/null; then
	if (( $(man -k ls 2>/dev/null | wc -l) > 0 )); then
		assert_true "man -k . finds pages (man -k '' finds none under mandoc)" \
			"$(man -k . 2>/dev/null | wc -l) > 0"
	else
		t_skip "man -k . finds pages" "no man index on this machine"
	fi
fi

# The apropos output shape differs: man-db separates the section, mandoc glues
# it on. One regex has to cover both.
_parse_man() {
	print -r -- "$1" | awk '
		{
			if (!match($0, /[A-Za-z0-9_.:@\[\]-]+[ ]?\([0-9a-zA-Z]+\)/)) next
			tok = substr($0, RSTART, RLENGTH)
			p = index(tok, "(")
			name = substr(tok, 1, p - 1); sub(/[ ,]+$/, "", name)
			sec  = substr(tok, p + 1);    sub(/\)$/, "", sec)
			print sec, name
		}'
}
assert_eq "1 ls" "$(_parse_man 'ls(1) - list directory contents')"  "fman parses the mandoc shape"
assert_eq "1 ls" "$(_parse_man 'ls (1)              - list dir')"   "fman parses the man-db shape"

# BWK awk cannot split on NUL, so frg's NF == 2 guard never fired and the
# picker stayed empty no matter what was typed.
assert_eq "2" "$(printf 'a\0b\n' | tr '\0' '\t' | awk 'BEGIN{FS="\t"}{print NF}')" \
	"the tr shim gives awk two fields where a NUL FS gives one"

# ── zsh's % is an anchor in a substitution pattern ───────────────────────────
# EDITOR_LINENO_FMT has never worked on any platform without the escape.
local _fmt='hx %f:%l' _got
_got="${_fmt//\%f//tmp/x}"; _got="${_got//\%l/42}"
assert_eq "hx /tmp/x:42" "$_got" "EDITOR_LINENO_FMT substitutes both placeholders"

# ── install.sh prompts for a git identity it may not be able to read ─────────
# Structural, like the picker checks above: driving a real install to this point
# costs an install. The bug was upstream's and pre-dates this branch — confirm()
# was fixed in 0e768f5 ("detect controlling tty by opening /dev/tty, not -r")
# and _install_gitconfig kept the check that commit had just declared wrong.
# `[[ -r /dev/tty ]]` only stats the device node, mode 666, so it passes with no
# controlling terminal; the read then failed and, under set -e, killed the
# install AFTER ~/.zshrc and ~/.zshenv had already been replaced.
# The optional-package report runs at the very bottom of install.sh, after every
# dotfile is linked, so it cannot block anything. It used to `exit 1` there —
# reporting failure for an install that had succeeded, so `install.sh && x` never
# ran x — while printing text that read as though nothing had been installed.
local _report_fn
_report_fn=$(awk '/^_report_optional_deps\(\)/,/^}$/' "$MO_ROOT/install.sh" \
	| command grep -v '^[[:space:]]*#')
assert_not_contains "$_report_fn" "exit 1" \
	"the optional-package report does not fail a completed install"
assert_not_contains "$_report_fn" "install without the recommended" \
	"the report does not imply the install was skipped"

local _inst="$MO_ROOT/install.sh"
local _gitcfg_fn
# Comment lines are stripped, as lint_platform.zsh does: the comment explaining
# why the old check was wrong quotes it verbatim, and matched this assertion.
_gitcfg_fn=$(awk '/^_install_gitconfig\(\)/,/^}$/' "$_inst" | command grep -v '^[[:space:]]*#')
assert_not_contains "$_gitcfg_fn" '[[ -r /dev/tty ]]' \
	"the identity prompt does not gate on -r /dev/tty"
assert_contains "$_gitcfg_fn" '{ : < /dev/tty; }' \
	"the identity prompt probes the tty by opening it"
# Both reads must handle EOF; a bare `read` aborts the run on Ctrl-D.
assert_eq "2" "$(print -r -- "$_gitcfg_fn" | command grep -c 'read -r git_.* || _die_no_git_identity')" \
	"both identity reads handle a closed input"
assert_contains "$(command cat "$_inst")" "_die_no_git_identity()" \
	"the refusal is defined in one place"

# ── the package hints must not make claims that are false on macOS ───────────
if _mo_is_macos; then
	assert_not_contains "$(_mo_pkg_hint xclip)"    "check your PATH" "xclip hint does not claim macOS ships it"
	assert_not_contains "$(_mo_pkg_hint iproute2)" "check your PATH" "iproute2 hint does not claim macOS ships it"
	assert_contains "$(_mo_pkg_hint build-essential fzf)" "fzf" \
		"a non-formula entry no longer swallows the rest of the list"
	assert_contains "$(_mo_pkg_hint nmap texlive-xetex)" "--cask" \
		"casks are emitted as their own brew invocation"
	assert_not_contains "$(_mo_pkg_hint unrar)" "brew install unrar" \
		"the removed unrar formula is not suggested"
	# xclip and wl-clipboard carry the same note, and it was emitted per package,
	# so a real install printed the identical sentence twice on one line.
	assert_eq "1" \
		"$(_mo_pkg_hint xclip wl-clipboard | command grep -o 'pbcopy/pbpaste' | command wc -l | command tr -d ' ')" \
		"a note shared by two packages is printed once"
	# The hint is displayed as a line to paste, so a note must not sit after a
	# "; " where it reads as another command.
	assert_not_contains "$(_mo_pkg_hint nmap xclip)" "; macOS" \
		"notes are not appended as if they were shell commands"
fi

# ── color pick owns the tty for the whole session ────────────────────────────
# Structural, not behavioural: exercising the picker needs a real pty and
# keystroke timing, which the unit suite has no way to provide. The behaviour
# was verified by hand — sending Ctrl+C after navigating returns 130 with this
# structure and kills the shell with the old one — and these assertions pin the
# structure that makes it true.
#
# The bug: raw mode was set and restored around every single keystroke, so ISIG
# was re-enabled between reads. A Ctrl+C landing in that window arrived as a
# real SIGINT instead of the \x03 the reader turns into "cancel".
local _pick="$MO_ROOT/omz-custom/plugins/mo-color/_mo_color_pick.zsh"
if [[ -r "$_pick" ]]; then
	local _reader
	_reader=$(awk '/^_mo_pick_read_key\(\)/,/^}$/' "$_pick")
	assert_not_contains "$_reader" "stty -echo" \
		"the key reader does not set raw mode per keystroke"
	assert_not_contains "$_reader" 'stty "$stty_save"' \
		"the key reader does not restore the tty per keystroke"
	assert_contains "$(<$_pick)" 'stty "$_MO_PICK_STTY"' \
		"the picker restores the tty from its trap"
	# The saved mode must be global. zsh tears a function's locals down before
	# running its EXIT trap, so a trap naming a local restores `stty ""` and
	# leaves the terminal with no echo and no Ctrl+C.
	assert_contains "$(<$_pick)" 'typeset -g _MO_PICK_STTY' \
		"the saved tty mode outlives the function's locals"
	assert_contains "$(<$_pick)" '} always {' \
		"the picker also restores the tty from an always block"
	assert_eq "1" "$(command grep -c 'stty -echo -icanon -isig' "$_pick")" \
		"raw mode is set exactly once, around the whole loop"
	# The Esc timeout must stay zsh's own: `read -k` re-applies VMIN/VTIME from
	# the shell's saved state, so an stty-based timeout is silently undone.
	assert_contains "$(<$_pick)" 'read -t 0.05 -k1' \
		"Esc disambiguation uses zsh's read timeout, not stty"
fi
